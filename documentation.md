# Clojure + Node.js + Claude Code Docker Image

Docker image combining Clojure development tools with Node.js ecosystem and Claude Code CLI, optimized for Clojure development with Claude Code.

## Image Details

**Base Image:** `clojure:temurin-25-tools-deps` (Debian-based)
**Docker Hub:** `tonykayclj/clojure-node-claude:latest`
**Architecture:** ARM64 (Apple Silicon / aarch64)

## Included Tools

### Core Tools
- **Clojure CLI** 1.12.3.1577
- **Java/OpenJDK** 25.0.1 (Temurin LTS)
- **Node.js** v18.20.4
- **npm** 9.2.0
- **nvm** 0.40.1 (for Node version management)
- **Claude Code** 2.0.37
- **git**, **bash**, **curl**, **ca-certificates**, **awscli**

### Clojure Development Tools
- **Babashka** v1.12.209 (Fast-starting Clojure scripting environment)
- **bbin** 0.2.4 (Babashka package manager)
- **parinfer-rust** 0.4.3 (Delimiter inference/fixing, compiled from source)
- **cljfmt** 0.15.4 (Code formatting)

### Claude Code Integration (clojure-mcp-light)
- **clj-paren-repair-claude-hook** - Automatic parenthesis repair with optional cljfmt integration
- **clj-nrepl-eval** - nREPL evaluation support for Claude Code
- **claude-setup-clojure** v1.0.0 - Project setup script for Claude Code hooks

## Quick Start

### Option 1: Using the Container Startup Script (Recommended)

```bash
# Start a development container for your project
./scripts/start-dev-container.sh ~/projects/my-clojure-app

# Or with custom options
./scripts/start-dev-container.sh --name my-repl --port 7890 ~/projects/my-app

# Interactive shell mode
./scripts/start-dev-container.sh --shell ~/projects/my-app
```

The script will:
- Find an available nREPL port (default: 7888-8888 range)
- Write the port to `PROJECT_DIR/.nrepl-port`
- Mount your project at `/workspace`
- Forward the nREPL port from container to host

### Option 2: Manual Docker Commands

```bash
# Pull the image
docker pull tonykayclj/clojure-node-claude:latest

# Run interactively
docker run -it --rm tonykayclj/clojure-node-claude:latest

# Mount your project directory with nREPL port
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  -p 7888:7888 \
  tonykayclj/clojure-node-claude:latest
```

## Setting Up a Clojure Project for Claude Code

Inside the container, run the setup script:

```bash
# Setup with defaults
claude-setup-clojure

# Preview changes without creating files
claude-setup-clojure --dry-run

# Overwrite existing configuration
claude-setup-clojure --force

# Skip creating slash commands
claude-setup-clojure --no-commands

# Disable cljfmt in hooks
claude-setup-clojure --no-cljfmt-hook
```

The script creates:
- `.claude/settings.local.json` - Hook configuration for parinfer and cljfmt
- `.cljfmt.edn` - Code formatting configuration (if missing)
- `.claude/commands/nrepl-eval.md` - Slash command for nREPL evaluation
- `.claude/commands/nrepl-eval-buffer.md` - Slash command for buffer evaluation

### Available Hooks

The setup script configures these Claude Code hooks:

**PreToolUse** - Before Write/Edit operations:
- Repairs parentheses using `clj-paren-repair-claude-hook`
- Optionally formats code with cljfmt

**PostToolUse** - After Write/Edit operations:
- Repairs parentheses and formats code

**SessionEnd** - When Claude Code session ends:
- Final cleanup and repair

### Shell Alias

A `ccode` alias is available for running Claude Code without permission checks:
```bash
ccode  # Equivalent to: claude --dangerously-disable-permissions
```

## Using nvm

Node.js v18.20.4 is installed by default. To manage Node versions with nvm:

```bash
# List available Node versions
nvm ls-remote

# Install a specific version
nvm install 20

# Switch versions
nvm use 20

# Check current version
node --version
```

Note: nvm is automatically loaded in interactive bash sessions via `.bashrc`

## Dockerfile Layer Structure

The Dockerfile is optimized for Docker layer caching, with heavy/stable operations first and frequently-changing operations last:

### Layer 1: System Packages (Rarely Changes)
```dockerfile
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    ca-certificates \
    nodejs \
    npm \
    awscli
```
These packages rarely change. This layer will be cached and reused unless you modify the package list.

### Layer 1.5: Babashka & bbin (Stable)
```dockerfile
# Copy bb from official babashka image (multi-stage build)
COPY --from=babashka /usr/local/bin/bb /usr/local/bin/bb

# Install and configure bbin
RUN bb --version && \
    curl -sLO https://raw.githubusercontent.com/babashka/bbin/main/bbin && \
    chmod +x bbin && \
    mv bbin /usr/local/bin/ && \
    mkdir -p /root/.local/bin
```

### Layer 1.6: parinfer-rust Build (Heavy, Rarely Changes)
```dockerfile
RUN apt-get update && apt-get install -y \
    cargo \
    rustc \
    libclang-dev \
    && git clone --depth 1 --branch v0.4.3 https://github.com/eraserhd/parinfer-rust.git /tmp/parinfer-rust \
    && cd /tmp/parinfer-rust \
    && cargo build --release \
    && cp target/release/parinfer-rust /usr/local/bin/ \
    && cd / \
    && rm -rf /tmp/parinfer-rust /root/.cargo \
    && apt-get remove -y cargo rustc libclang-dev \
    && apt-get autoremove -y
```
This layer compiles parinfer-rust from source (required for ARM64) and cleans up all build dependencies in the same layer to minimize image size.

### Layer 1.7-1.8: bbin Package Installation (Stable)
```dockerfile
# Install cljfmt
RUN bbin install io.github.weavejester/cljfmt --as cljfmt

# Install clojure-mcp-light tools
RUN bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.1.1 && \
    bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.1.1 \
      --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'
```

### Layer 2: nvm Installation (Rarely Changes)
```dockerfile
ENV NVM_DIR="/root/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && \
    echo 'export NVM_DIR="$HOME/.nvm"' >> /root/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /root/.bashrc && \
    echo 'alias ccode="claude --dangerously-disable-permissions"' >> /root/.bashrc
```

### Layer 3: Global npm Packages (May Change)
```dockerfile
RUN npm install -g @anthropic-ai/claude-code
```
Global npm packages are installed in their own layer for better caching.

### Layer 4: Scripts and Resources (Most Likely to Change)
```dockerfile
COPY scripts/claude-setup-clojure /usr/local/bin/claude-setup-clojure
COPY scripts/resources/.cljfmt.edn /usr/local/share/claude-clojure/.cljfmt.edn
RUN chmod +x /usr/local/bin/claude-setup-clojure
```
Scripts are placed late in the build to avoid invalidating heavy layers during development.

### Layer 5: Verification
```dockerfile
RUN node --version && \
    npm --version && \
    claude --version && \
    nvm --version && \
    bb --version && \
    bbin --version && \
    ls -la /usr/local/bin/parinfer-rust && \
    ls -la /root/.local/bin/cljfmt && \
    ls -la /root/.local/bin/clj-paren-repair-claude-hook && \
    ls -la /root/.local/bin/clj-nrepl-eval && \
    claude-setup-clojure --help
```

## Container Startup Script

The `scripts/start-dev-container.sh` script provides a convenient way to start development containers:

```bash
start-dev-container.sh [OPTIONS] PROJECT_DIR

Options:
  -n, --name NAME    Container name (default: auto-generated from project dir)
  -p, --port PORT    Host port for nREPL (default: auto-discover)
  --shell           Start an interactive shell instead of daemon mode
  -h, --help        Show help message

Examples:
  # Start container in daemon mode
  start-dev-container.sh ~/projects/my-app

  # Start with custom name and port
  start-dev-container.sh --name my-repl --port 7890 ~/projects/my-app

  # Interactive shell mode
  start-dev-container.sh --shell ~/projects/my-app
```

The script automatically:
- Finds an available port in the 7888-8888 range
- Writes the port to `.nrepl-port` in your project
- Mounts your project directory at `/workspace`
- Forwards the nREPL port from container to host
- Names the container based on your project directory

### Accessing the Container

```bash
# If started in daemon mode
docker exec -it clj-dev-my-app bash

# Stop the container
docker stop clj-dev-my-app

# View logs
docker logs clj-dev-my-app
```

## Extending the Image

### Adding System Packages
Add to Layer 1 (will invalidate subsequent layers):
```dockerfile
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    ca-certificates \
    nodejs \
    npm \
    awscli \
    postgresql-client \  # New package
    redis-tools
```

### Adding Global npm Packages
Add to Layer 3 (minimal cache invalidation):
```dockerfile
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g typescript
RUN npm install -g ts-node
```

### Adding Babashka Libraries
Install additional bbin packages:
```dockerfile
RUN bbin install io.github.babashka/http-server
```

### Creating a Custom Image
```dockerfile
FROM tonykayclj/clojure-node-claude:latest

# Add your custom tools
RUN apt-get update && apt-get install -y postgresql-client
RUN npm install -g typescript

# Copy your project files
COPY . /app
WORKDIR /app

CMD ["/bin/bash"]
```

## Building the Image

```bash
# Build locally
docker build -t tonykayclj/clojure-node-claude:latest .

# Test the build
docker run --rm tonykayclj/clojure-node-claude:latest bash -c \
  'clojure --version && node --version && claude --version && bb --version'

# Push to Docker Hub
docker push tonykayclj/clojure-node-claude:latest
```

## Common Use Cases

### Running a Clojure REPL
```bash
docker run -it --rm tonykayclj/clojure-node-claude:latest clojure
```

### Running a Babashka Script
```bash
docker run --rm -v $(pwd):/app -w /app tonykayclj/clojure-node-claude:latest bb script.clj
```

### Running a Node.js Script
```bash
docker run --rm -v $(pwd):/app -w /app tonykayclj/clojure-node-claude:latest node script.js
```

### Using Claude Code
```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  tonykayclj/clojure-node-claude:latest \
  claude
```

### Using the ccode Alias
```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  tonykayclj/clojure-node-claude:latest \
  ccode
```

### Development Environment with nREPL
```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  -p 7888:7888 \
  -p 3000:3000 \
  tonykayclj/clojure-node-claude:latest \
  bash
```

Then inside the container:
```bash
# Setup Claude Code hooks
claude-setup-clojure

# Start an nREPL server
clojure -M:nrepl
```

Your editor can now connect to `localhost:7888` (or the port in `.nrepl-port`).

## Image Size Considerations

This image uses Debian (not Alpine) for better compatibility with glibc-based binaries like Babashka. Current size: ~1.5 GB (includes JDK, Node.js, Rust-compiled parinfer, and all tools).

The largest components:
- OpenJDK 25: ~300 MB
- Node.js + npm: ~150 MB
- parinfer-rust (compiled): ~12 MB
- Babashka: ~82 MB

To reduce size:
- Remove verification layer (minimal savings)
- Use multi-stage builds to copy only runtime artifacts
- Consider removing AWS CLI if not needed
- Remove nvm if you don't need multiple Node.js versions

## Troubleshooting

### nvm command not found
If running non-interactive commands, source nvm first:
```bash
docker run --rm tonykayclj/clojure-node-claude:latest bash -c '. "$NVM_DIR/nvm.sh" && nvm --version'
```

### bbin tools not in PATH
bbin installs to `/root/.local/bin`. Ensure PATH includes this:
```bash
export PATH="/usr/local/bin:/root/.local/bin:$PATH"
```
This is configured automatically in `.bashrc` and `.profile`.

### Permission issues
The image runs as root by default. To run as a different user:
```bash
docker run -it --rm -u $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  tonykayclj/clojure-node-claude:latest
```

### Node version mismatch
The image provides Node.js v18.x from Debian repos. To use a different version:
```bash
nvm install 20
nvm use 20
node --version
```

### parinfer-rust or cljfmt not working
Ensure you're using the full paths or that PATH is properly configured:
```bash
/usr/local/bin/parinfer-rust --help
/root/.local/bin/cljfmt --help
```

Or source the environment:
```bash
. /root/.bashrc
parinfer-rust --help
cljfmt --help
```

### Claude Code hooks not triggering
Make sure you ran `claude-setup-clojure` in your project directory to create the `.claude/settings.local.json` configuration.

## Architecture Notes

This image is built for ARM64 (Apple Silicon / aarch64). Key architectural considerations:

1. **Babashka**: Uses multi-stage build to copy binary from official babashka image
2. **parinfer-rust**: Compiled from source because ARM64 binaries aren't provided in releases
3. **All other tools**: Use native ARM64 packages or are architecture-independent (Node.js, Java, etc.)

For x86_64 support, the Dockerfile would need minor modifications (mainly the parinfer-rust build might use pre-built binaries).

## Project Structure

```
.
├── Dockerfile                          # Main image definition
├── documentation.md                     # This file
├── claude-setup.md                     # Planning document
└── scripts/
    ├── claude-setup-clojure            # Babashka setup script
    ├── start-dev-container.sh          # Container startup script
    └── resources/
        └── .cljfmt.edn                 # Default cljfmt configuration
```

## License

This Dockerfile is provided as-is for community use.
