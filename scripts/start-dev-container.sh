#!/usr/bin/env bash

set -e

VERSION="1.0.0"
IMAGE_NAME="tonykayclj/clojure-node-claude:latest"
CONTAINER_NREPL_PORT=7888

usage() {
    cat <<EOF
start-dev-container.sh v${VERSION}

Start a Clojure development container with nREPL access.

Usage: $(basename "$0") [OPTIONS] PROJECT_DIR

Arguments:
  PROJECT_DIR    Path to the project directory to mount in the container

Options:
  -n, --name NAME   Container name (default: auto-generated from project dir)
  -p, --port PORT   Host port for nREPL (default: auto-discover)
  --daemon          Start in daemon mode
  -h, --help        Show this help message

The script will:
  1. Find an available non-privileged port on the host (or use specified port)
  2. Write the port number to PROJECT_DIR/.nrepl-port
  3. Start the container with PROJECT_DIR mounted at /workspace
  4. Forward the host port to container port ${CONTAINER_NREPL_PORT} for nREPL

Examples:
  $(basename "$0") ~/projects/my-clojure-app
  $(basename "$0") --name my-repl --port 7888 ~/projects/my-app
  $(basename "$0") --shell ~/projects/my-app
EOF
}

find_available_port() {
    local start_port=7888
    local end_port=8888
    local port=$start_port

    while [ $port -le $end_port ]; do
        if ! lsof -i :$port >/dev/null 2>&1; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done

    echo "ERROR: No available ports found in range $start_port-$end_port" >&2
    return 1
}

# Parse arguments
CONTAINER_NAME=""
HOST_PORT=""
START_SHELL=true
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -p|--port)
            HOST_PORT="$2"
            shift 2
            ;;
        --daemon)
            START_SHELL=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            if [ -z "$PROJECT_DIR" ]; then
                PROJECT_DIR="$1"
            else
                echo "ERROR: Multiple project directories specified" >&2
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate project directory
if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: PROJECT_DIR is required" >&2
    usage
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory does not exist: $PROJECT_DIR" >&2
    exit 1
fi

# Convert to absolute path
PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)

# Generate container name if not provided
if [ -z "$CONTAINER_NAME" ]; then
    PROJECT_BASENAME=$(basename "$PROJECT_DIR")
    CONTAINER_NAME="clj-dev-${PROJECT_BASENAME}"
fi

# Find or validate port
if [ -z "$HOST_PORT" ]; then
    echo "Finding available port..."
    HOST_PORT=$(find_available_port)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    echo "Found available port: $HOST_PORT"
else
    if lsof -i :$HOST_PORT >/dev/null 2>&1; then
        echo "ERROR: Port $HOST_PORT is already in use" >&2
        exit 1
    fi
fi

# Write .nrepl-port file
NREPL_PORT_FILE="$PROJECT_DIR/.nrepl-port"
echo "$HOST_PORT" > "$NREPL_PORT_FILE"
echo "Wrote nREPL port to: $NREPL_PORT_FILE"

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "WARNING: Container '$CONTAINER_NAME' already exists"
    read -p "Remove existing container? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker rm -f "$CONTAINER_NAME"
    else
        echo "Aborted"
        exit 1
    fi
fi

# Start container
echo "Starting container '$CONTAINER_NAME'..."
echo "  Project dir: $PROJECT_DIR"
echo "  Workspace:   /workspace"
echo "  Claude config: ~/.claude -> /root/.claude"
echo "  nREPL port:  localhost:$HOST_PORT -> container:$CONTAINER_NREPL_PORT"

# Check if ~/.claude directory exists
CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_MOUNT_ARGS=""
if [ -d "$CLAUDE_CONFIG_DIR" ]; then
    CLAUDE_MOUNT_ARGS="-v $CLAUDE_CONFIG_DIR:/root/.claude"
else
    echo "  Note: ~/.claude not found - Claude will need to be configured in container"
fi

if [ "$START_SHELL" = true ]; then
    # Interactive shell mode
    docker run -it --rm \
        --name "$CONTAINER_NAME" \
        -v "$PROJECT_DIR:/workspace" \
        $CLAUDE_MOUNT_ARGS \
        -w /workspace \
        -p "$HOST_PORT:$CONTAINER_NREPL_PORT" \
        "$IMAGE_NAME" \
        /bin/bash
else
    # Daemon mode - keep container running
    docker run -d \
        --name "$CONTAINER_NAME" \
        -v "$PROJECT_DIR:/workspace" \
        $CLAUDE_MOUNT_ARGS \
        -w /workspace \
        -p "$HOST_PORT:$CONTAINER_NREPL_PORT" \
        "$IMAGE_NAME" \
        tail -f /dev/null

    echo ""
    echo "Container started successfully!"
    echo ""
    echo "To access the container:"
    echo "  docker exec -it $CONTAINER_NAME bash"
    echo ""
    echo "To stop the container:"
    echo "  docker stop $CONTAINER_NAME"
    echo ""
    echo "To view logs:"
    echo "  docker logs $CONTAINER_NAME"
    echo ""
    echo "nREPL available at: localhost:$HOST_PORT"
fi
