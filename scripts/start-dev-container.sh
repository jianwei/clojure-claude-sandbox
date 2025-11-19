#!/usr/bin/env bash

set -e

VERSION="1.1.0"
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
  -n, --name NAME          Container name (default: auto-generated from project dir)
  -p, --port PORT          Host port for nREPL (default: auto-discover)
  -c, --claude-config DIR  Claude config directory (default: ~/.claude)
  -s, --ssh MODE           SSH credential mode: auto|agent|none (default: auto)
  --ssh-key PATH           Specific SSH key to mount (can be used multiple times)
  --daemon                 Start in daemon mode
  -h, --help               Show this help message

SSH Modes:
  auto    - Detect git remotes and mount only required SSH keys (default)
  agent   - Use SSH agent forwarding (requires SSH_AUTH_SOCK)
  none    - No SSH credentials mounted

The script will:
  1. Find an available non-privileged port on the host (or use specified port)
  2. Write the port number to PROJECT_DIR/.nrepl-port
  3. Start the container with PROJECT_DIR mounted at /workspace
  4. Mount Claude config directory to /home/ralph/.claude
  5. Configure SSH credentials based on --ssh mode
  6. Forward the host port to container port ${CONTAINER_NREPL_PORT} for nREPL

Examples:
  $(basename "$0") ~/projects/my-clojure-app
  $(basename "$0") --name my-repl --port 7888 ~/projects/my-app
  $(basename "$0") --claude-config ~/.claude-work ~/projects/my-app
  $(basename "$0") --ssh agent ~/projects/my-app
  $(basename "$0") --ssh-key ~/.ssh/id_ed25519 ~/projects/my-app
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

# Extract SSH hosts from git remotes
get_git_ssh_hosts() {
    local project_dir="$1"
    local hosts=()

    if [ ! -d "$project_dir/.git" ]; then
        return 0
    fi

    # Get all git remotes and extract SSH hosts
    while IFS= read -r remote_url; do
        # Match SSH URLs like git@github.com:user/repo.git
        if [[ "$remote_url" =~ ^([^@]+@)?([^:]+): ]]; then
            local host="${BASH_REMATCH[2]}"
            hosts+=("$host")
        # Match SSH URLs like ssh://git@github.com/user/repo.git
        elif [[ "$remote_url" =~ ^ssh://([^@]+@)?([^/]+)/ ]]; then
            local host="${BASH_REMATCH[2]}"
            hosts+=("$host")
        fi
    done < <(cd "$project_dir" && git remote -v 2>/dev/null | awk '{print $2}' | sort -u)

    # Return unique hosts
    printf '%s\n' "${hosts[@]}" | sort -u
}

# Find SSH key for a given host
find_ssh_key_for_host() {
    local host="$1"
    local ssh_config="$HOME/.ssh/config"
    local identity_file=""

    # Check SSH config for IdentityFile directive
    if [ -f "$ssh_config" ]; then
        # Look for Host block matching this host
        local in_host_block=0
        while IFS= read -r line; do
            # Check if we're entering a relevant Host block (supports both "Host foo" and "Host=foo")
            if [[ "$line" =~ ^[[:space:]]*Host[=[:space:]]+(.+)$ ]]; then
                local host_pattern="${BASH_REMATCH[1]}"
                # Simple pattern matching (supports wildcards)
                if [[ "$host" == $host_pattern ]]; then
                    in_host_block=1
                else
                    in_host_block=0
                fi
            # Match IdentityFile (supports both "IdentityFile foo" and "IdentityFile=foo")
            elif [[ $in_host_block -eq 1 && "$line" =~ ^[[:space:]]*IdentityFile[=[:space:]]+(.+)$ ]]; then
                identity_file="${BASH_REMATCH[1]}"
                # Expand ~ to home directory
                identity_file="${identity_file/#\~/$HOME}"
                break
            fi
        done < "$ssh_config"
    fi

    # If no specific key found, use default keys
    if [ -z "$identity_file" ]; then
        for default_key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
            if [ -f "$default_key" ]; then
                identity_file="$default_key"
                break
            fi
        done
    fi

    echo "$identity_file"
}

# Detect SSH keys needed for project
detect_ssh_keys() {
    local project_dir="$1"
    local keys=()

    # Get SSH hosts from git remotes
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        local key=$(find_ssh_key_for_host "$host")
        if [ -n "$key" ] && [ -f "$key" ]; then
            keys+=("$key")
        fi
    done < <(get_git_ssh_hosts "$project_dir")

    # Return unique keys
    printf '%s\n' "${keys[@]}" | sort -u
}

# Setup SSH directory with selective key mounting
# Pass keys as separate arguments: setup_ssh_dir "${keys[@]}"
setup_ssh_dir() {
    local ssh_temp_dir=$(mktemp -d)

    # Copy each key and its public counterpart
    for key in "$@"; do
        if [ -f "$key" ]; then
            cp "$key" "$ssh_temp_dir/$(basename "$key")"
            chmod 600 "$ssh_temp_dir/$(basename "$key")"

            # Copy public key if it exists
            if [ -f "${key}.pub" ]; then
                cp "${key}.pub" "$ssh_temp_dir/$(basename "${key}.pub")"
                chmod 644 "$ssh_temp_dir/$(basename "${key}.pub")"
            fi
        fi
    done

    # Copy known_hosts if it exists
    if [ -f "$HOME/.ssh/known_hosts" ]; then
        cp "$HOME/.ssh/known_hosts" "$ssh_temp_dir/known_hosts"
        chmod 644 "$ssh_temp_dir/known_hosts"
    fi

    # Copy SSH config if it exists
    if [ -f "$HOME/.ssh/config" ]; then
        cp "$HOME/.ssh/config" "$ssh_temp_dir/config"
        chmod 600 "$ssh_temp_dir/config"
    fi

    echo "$ssh_temp_dir"
}

# Parse arguments
CONTAINER_NAME=""
HOST_PORT=""
START_SHELL=true
PROJECT_DIR=""
CLAUDE_CONFIG_DIR=""
SSH_MODE="auto"
SSH_KEYS=()

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
        -c|--claude-config)
            CLAUDE_CONFIG_DIR="$2"
            shift 2
            ;;
        -s|--ssh)
            SSH_MODE="$2"
            if [[ ! "$SSH_MODE" =~ ^(auto|agent|none)$ ]]; then
                echo "ERROR: Invalid SSH mode: $SSH_MODE (must be auto, agent, or none)" >&2
                exit 1
            fi
            shift 2
            ;;
        --ssh-key)
            SSH_KEYS+=("$2")
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

# Set default Claude config directory if not specified
if [ -z "$CLAUDE_CONFIG_DIR" ]; then
    CLAUDE_CONFIG_DIR="$HOME/.claude"
fi

# Convert to absolute path and check if it exists
if [ -d "$CLAUDE_CONFIG_DIR" ]; then
    CLAUDE_CONFIG_DIR=$(cd "$CLAUDE_CONFIG_DIR" && pwd)
    CLAUDE_MOUNT_ARGS="-v $CLAUDE_CONFIG_DIR:/home/ralph/.claude -e CLAUDE_CONFIG_DIR=/home/ralph/.claude"
    CLAUDE_STATUS="$CLAUDE_CONFIG_DIR -> /home/ralph/.claude"
else
    CLAUDE_MOUNT_ARGS=""
    CLAUDE_STATUS="not found - Claude will need to be configured in container"
fi

# Setup SSH credentials
SSH_MOUNT_ARGS=""
SSH_STATUS="none"
SSH_TEMP_DIR=""
CLEANUP_REQUIRED=false

# If --ssh-key was provided, override SSH_MODE to use those specific keys
if [ ${#SSH_KEYS[@]} -gt 0 ]; then
    SSH_MODE="manual"
fi

case "$SSH_MODE" in
    auto)
        # Detect SSH keys from git config
        echo "Detecting SSH keys from git remotes..."
        DETECTED_KEYS=()
        while IFS= read -r key; do
            [ -n "$key" ] && DETECTED_KEYS+=("$key")
        done < <(detect_ssh_keys "$PROJECT_DIR")

        if [ ${#DETECTED_KEYS[@]} -gt 0 ]; then
            SSH_TEMP_DIR=$(setup_ssh_dir "${DETECTED_KEYS[@]}")
            SSH_MOUNT_ARGS="-v $SSH_TEMP_DIR:/home/ralph/.ssh"
            SSH_STATUS="auto-detected: ${DETECTED_KEYS[*]}"
            CLEANUP_REQUIRED=true
            echo "Found ${#DETECTED_KEYS[@]} SSH key(s): ${DETECTED_KEYS[*]}"
        else
            echo "No SSH keys detected from git remotes"
            SSH_STATUS="auto-detect: no keys found"
        fi
        ;;
    agent)
        # Use SSH agent forwarding
        if [ -z "$SSH_AUTH_SOCK" ]; then
            echo "WARNING: SSH_AUTH_SOCK not set, SSH agent forwarding unavailable" >&2
            SSH_STATUS="agent: SSH_AUTH_SOCK not set"
        else
            SSH_MOUNT_ARGS="-v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent"
            SSH_STATUS="agent forwarding: $SSH_AUTH_SOCK"
        fi
        ;;
    manual)
        # Use explicitly specified SSH keys
        if [ ${#SSH_KEYS[@]} -eq 0 ]; then
            echo "ERROR: --ssh-key specified but no keys provided" >&2
            exit 1
        fi

        # Validate all keys exist
        for key in "${SSH_KEYS[@]}"; do
            if [ ! -f "$key" ]; then
                echo "ERROR: SSH key not found: $key" >&2
                exit 1
            fi
        done

        SSH_TEMP_DIR=$(setup_ssh_dir "${SSH_KEYS[@]}")
        SSH_MOUNT_ARGS="-v $SSH_TEMP_DIR:/home/ralph/.ssh"
        SSH_STATUS="manual: ${SSH_KEYS[*]}"
        CLEANUP_REQUIRED=true
        ;;
    none)
        SSH_STATUS="disabled"
        ;;
esac

# Cleanup function for SSH temp directory
cleanup_ssh() {
    # Only cleanup in interactive mode (daemon containers need persistent SSH mounts)
    if [ "$START_SHELL" = true ] && [ "$CLEANUP_REQUIRED" = true ] && [ -n "$SSH_TEMP_DIR" ] && [ -d "$SSH_TEMP_DIR" ]; then
        echo "Cleaning up temporary SSH directory: $SSH_TEMP_DIR"
        rm -rf "$SSH_TEMP_DIR"
    fi
}

# Register cleanup on exit for interactive mode only
if [ "$START_SHELL" = true ]; then
    trap cleanup_ssh EXIT INT TERM
fi

# Start container
echo "Starting container '$CONTAINER_NAME'..."
echo "  Project dir:    $PROJECT_DIR"
echo "  Workspace:      /workspace"
echo "  Claude config:  $CLAUDE_STATUS"
echo "  SSH:            $SSH_STATUS"
echo "  nREPL port:     localhost:$HOST_PORT -> container:$CONTAINER_NREPL_PORT"
echo "  User:           ralph (with sudo)"

if [ "$START_SHELL" = true ]; then
    # Interactive shell mode
    docker run -it --rm \
        --name "$CONTAINER_NAME" \
        -v "$PROJECT_DIR:/workspace" \
        $CLAUDE_MOUNT_ARGS \
        $SSH_MOUNT_ARGS \
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
        $SSH_MOUNT_ARGS \
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
    if [ -n "$SSH_TEMP_DIR" ] && [ -d "$SSH_TEMP_DIR" ]; then
        echo "  rm -rf $SSH_TEMP_DIR  # Cleanup SSH temp directory"
    fi
    echo ""
    echo "To view logs:"
    echo "  docker logs $CONTAINER_NAME"
    echo ""
    echo "nREPL available at: localhost:$HOST_PORT"
fi
