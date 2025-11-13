# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a Docker image for Clojure development with Claude Code integration. The image combines Clojure CLI tools, Node.js, and Claude Code CLI with specialized Clojure tooling from the clojure-mcp-light project.

**Docker Hub Image:** `tonykayclj/clojure-node-claude:latest`
**Architecture:** ARM64 (Apple Silicon / aarch64)

## Key Components

### Docker Image (`Dockerfile`)
Multi-stage Docker build that creates a Clojure development environment with:
- Base: `eclipse-temurin:21-jdk-alpine`
- User: `ralph` (with sudo access)
- Working directory: `/home/ralph`

The Dockerfile uses multi-stage builds to:
1. **parinfer-builder stage**: Compiles parinfer-rust from source (required for ARM64)
2. **node-builder stage**: Installs Claude Code CLI and Node.js packages
3. **babashka stage**: Copies Babashka binary from official image
4. **Final stage**: Combines everything with Alpine Linux for minimal size

### Claude Setup Script (`scripts/claude-setup-clojure`)
Babashka script (v1.0.0) that configures Clojure projects for Claude Code. Creates:
- `.claude/settings.local.json` - Hook configuration for automatic parenthesis repair with parinfer and optional cljfmt formatting
- `.cljfmt.edn` - Code formatting configuration (if missing)
- `.claude/commands/clojure-eval.md` - Slash command for nREPL evaluation
- `.claude/commands/start-nrepl.md` - Instructions for starting nREPL server

The script preserves existing files by default and supports `--force`, `--force-cljfmt`, `--no-commands`, `--no-cljfmt-hook`, and `--dry-run` options.

### Container Startup Script (`scripts/start-dev-container.sh`)
Bash script (v1.0.0) that simplifies starting development containers:
- Auto-discovers available nREPL port (7888-8888 range)
- Writes port to `.nrepl-port` in project directory
- Mounts project directory at `/workspace`
- Mounts Claude config directory to `/home/ralph/.claude`
- Supports custom container names, ports, and Claude config directories
- Offers both interactive shell and daemon modes

### Configuration Files
- `.cljfmt.edn` - Code formatting configuration with 2-space indentation (matching IntelliJ/Cursive defaults) and aligned map columns
- `scripts/resources/.cljfmt.edn` - Template cljfmt config copied to new projects

## Common Development Tasks

### Building the Docker Image
```bash
docker build -t tonykayclj/clojure-node-claude:latest .
```

### Testing the Image Locally
```bash
docker run --rm tonykayclj/clojure-node-claude:latest bash -c \
  'clojure --version && node --version && claude --version && bb --version'
```

### Starting a Development Container
```bash
# Interactive shell mode (recommended for development)
./scripts/start-dev-container.sh ~/projects/my-clojure-app

# Daemon mode
./scripts/start-dev-container.sh --daemon ~/projects/my-clojure-app

# With custom options
./scripts/start-dev-container.sh --name my-repl --port 7890 ~/projects/my-app

# Using alternate Claude config (for different accounts)
./scripts/start-dev-container.sh --claude-config ~/.claude-work ~/projects/my-app
```

### Setting Up a Project for Claude Code
Inside the container:
```bash
claude-setup-clojure                    # Setup with defaults
claude-setup-clojure --dry-run          # Preview changes
claude-setup-clojure --force            # Overwrite existing config
claude-setup-clojure --no-cljfmt-hook   # Disable cljfmt in hooks
```

## Architecture and Design Patterns

### Multi-Stage Build Strategy
The Dockerfile is optimized for layer caching with stable operations first:
1. System packages (rarely changes)
2. Rust compilation of parinfer (heavy, stable)
3. Babashka and bbin setup (stable)
4. bbin package installations (moderately stable)
5. Scripts and resources (most likely to change)
6. Verification (can be removed for faster builds)

This ordering minimizes cache invalidation during development.

### User Management
- Container runs as user `ralph` (not root) for better security
- `ralph` has sudo access via NOPASSWD configuration
- bbin packages install to `/home/ralph/.local/bin`
- PATH configured in both `.bashrc` and `.profile` to include `/home/ralph/.local/bin`

### Hook System
Claude Code hooks are configured to run `clj-paren-repair-claude-hook` at three points:
- **PreToolUse** (before Write/Edit): Repairs delimiters before Claude writes code
- **PostToolUse** (after Write/Edit): Repairs delimiters after Claude edits code
- **SessionEnd**: Final cleanup when session ends

With `--cljfmt` flag, hooks also format code using the project's `.cljfmt.edn` configuration.

### Port Management
The startup script auto-discovers available ports in the 7888-8888 range and writes the selected port to `.nrepl-port` in the project directory. This allows:
- Multiple containers running simultaneously without port conflicts
- IDEs to automatically discover the nREPL port
- Consistent port forwarding from host to container (container always uses 7888)

## Included Tools and Versions

### Core Development Tools
- Clojure CLI: 1.11.1.1435
- Java/OpenJDK: 25 (Temurin)
- Node.js: v20 (from official Node image)
- Claude Code: Latest via npm global install
- Babashka: Latest (from official babashka image)
- bbin: Latest (package manager for Babashka)

### Clojure-Specific Tools (via bbin)
- **cljfmt** (0.15.4): Code formatting
- **clj-paren-repair-claude-hook**: Automatic parenthesis repair for Claude Code
- **clj-nrepl-eval**: nREPL evaluation support for Claude Code
- **parinfer-rust** (v0.4.3): Delimiter inference (compiled from source)

### Shell Aliases
- `ccode`: Alias for `claude --dangerously-skip-permissions` (configured in `.bashrc`)

## ARM64 Considerations

This image is built for ARM64 (Apple Silicon). Key points:
- **parinfer-rust**: Must be compiled from source (no ARM64 binaries in releases)
- **Babashka**: Copied from official multi-arch image
- **All other tools**: Use native ARM64 packages or are architecture-independent

For x86_64 support, the Dockerfile would need modifications to the parinfer-rust build stage (could potentially use pre-built binaries).

## File Structure

```
.
├── Dockerfile                          # Multi-stage Docker image definition
├── documentation.md                     # Comprehensive user documentation
├── claude-setup.md                     # Original planning document
├── .cljfmt.edn                         # Default cljfmt configuration for this repo
└── scripts/
    ├── claude-setup-clojure            # Babashka script to configure projects
    ├── start-dev-container.sh          # Bash script to start dev containers
    └── resources/
        └── .cljfmt.edn                 # Template cljfmt config for new projects
```

## Working with Scripts

### Modifying claude-setup-clojure
- Written in Babashka (Clojure scripting)
- Uses `cheshire.core` for JSON generation
- Test locally: `bb scripts/claude-setup-clojure --dry-run`
- After changes, rebuild Docker image to include updated script

### Modifying start-dev-container.sh
- Pure bash script
- No Docker rebuild needed (runs on host)
- Uses `lsof` to check port availability
- Requires bash-specific features (arrays, string operations)

## Testing Changes

When modifying the Dockerfile:
1. Build image: `docker build -t tonykayclj/clojure-node-claude:latest .`
2. Run verification: `docker run --rm tonykayclj/clojure-node-claude:latest bash -c 'node --version && claude --version && bb --version'`
3. Test setup script: Create a test project directory and run `./scripts/start-dev-container.sh` with it
4. Inside container, run `claude-setup-clojure --dry-run` to verify script functionality

## Environment Variables

- `NVM_DIR`: Not currently used (nvm removed in favor of Node from official image)
- `PATH`: Includes `/usr/local/bin` and `/home/ralph/.local/bin`
- `CLAUDE_CONFIG_DIR`: Set to `/home/ralph/.claude` by container startup script
- `CONTAINER_NREPL_PORT`: Fixed at 7888 (container-side port)

## Important Notes

- The image uses Alpine Linux (not Debian) for smaller size, with gcompat for glibc compatibility
- Scripts are copied into `/usr/local/bin/` for global availability
- Default cljfmt configuration uses `:indents ^:replace {#".*" [[:inner 0]]}` for consistent 2-space indentation
- The startup script requires `lsof` on the host machine to check port availability
- Container must have access to `.claude` directory from host for Claude Code authentication
