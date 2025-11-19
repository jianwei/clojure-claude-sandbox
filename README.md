# Clojure + Node.js + Claude Code Docker Image

Docker image combining Clojure development tools with Node.js ecosystem and Claude Code CLI, optimized for **unattended** Clojure development with Claude Code in a sandbox.

I find lately that I can largely trust Claude Code to work unattended, and I wanted an environment where I can safely do that and just disable all security and questions of "can I use this?".

This image has all the tools needed for running Bruce Hauman's clojure-mcp and clojure-mcp-light, and it has a start at a script that will appear in the docker shell called `claude-setup-clojure` that puts the stuff in place that clojure-mcp-light currently has. YMMV.

The image *tries* to mount your Claude configs and sessions so that if you've already logged in to a subscription then it'll "just work".

Claude wrote almost everything here with my direction. I have not been particularly critical of the documentation, but I did glance through it.

**Docker Hub:** `tonykayclj/clojure-node-claude:latest`
**Architecture:** ARM64 (Apple Silicon / aarch64)
**Base Image:** `eclipse-temurin:21-jdk-alpine`

---

## Quick Start

### Prerequisites

```bash
# Install Claude Code CLI on your Mac (if not already installed)
npm install -g @anthropic-ai/claude-code

# Login with your Claude subscription
claude login  # Creates ~/.claude with your credentials
```

**For multiple accounts:** Maintain different Claude config directories (e.g., `~/.claude-work`, `~/.claude-personal`) and use the `--claude-config` option.

### Using the Container Startup Script (Recommended)

Copy `scripts/start-dev-container.sh` to somewhere on your PATH, then:

```bash
# Start a development container (auto-detects SSH keys)
start-dev-container.sh ~/projects/my-clojure-app

# With custom options
start-dev-container.sh --name my-repl --port 7890 ~/projects/my-app

# Use SSH agent forwarding (recommended for security)
start-dev-container.sh --ssh agent ~/projects/my-app

# Daemon mode (container keeps running in background)
start-dev-container.sh --daemon ~/projects/my-app

# Use different Claude account
start-dev-container.sh --claude-config ~/.claude-work ~/projects/my-app
```

Inside the container:
```bash
cd project-you-want-to-work-on
claude
# or use the ccode alias:
ccode  # Same as: claude --dangerously-skip-permissions
```

The script will:
- Find an available nREPL port (default: 7888-8888 range)
- Write the port to `PROJECT_DIR/.nrepl-port`
- Mount your project at `/workspace`
- Mount your Claude config directory to `/home/ralph/.claude`
- Configure SSH credentials based on `--ssh` mode (default: auto-detect from git remotes)
- Forward the nREPL port from container to host
- Start as user `ralph` (with sudo access)

**User:** The container runs as `ralph` (after Ralph Wiggum of The Simpsons). The idea being that your user is just blindly saying "sure, do that" without thinking. Ralph has sudo, so Claude can install anything else your session might need.

### Manual Docker Commands

```bash
# Pull the image
docker pull tonykayclj/clojure-node-claude:latest

# Run interactively
docker run -it --rm tonykayclj/clojure-node-claude:latest

# Mount your project directory with nREPL port and Claude config
docker run -it --rm \
  -v $(pwd):/workspace \
  -v ~/.claude:/home/ralph/.claude \
  -w /workspace \
  -p 7888:7888 \
  tonykayclj/clojure-node-claude:latest
```

---

## Included Tools

### Core Tools
- **Clojure CLI** 1.11.1.1435
- **Java/OpenJDK** 25 (Temurin)
- **Node.js** v20 (from official Node image)
- **Claude Code** Latest via npm global install
- **Babashka** Latest (from official babashka image)
- **bbin** Latest (package manager for Babashka)
- **git**, **bash**, **openssh**, **ripgrep**

### Clojure Development Tools (via bbin)
- **cljfmt** (0.15.4): Code formatting
- **clj-paren-repair-claude-hook**: Automatic parenthesis repair for Claude Code
- **clj-nrepl-eval**: nREPL evaluation support for Claude Code
- **parinfer-rust** (v0.4.3): Delimiter inference (compiled from source for ARM64)

### Claude Code Integration
- **claude-setup-clojure** v1.0.0 - Project setup script for Claude Code hooks

---

## SSH Credentials for Git Operations

**Requirements**: `start-dev-container.sh` v1.1.0+ (includes bash 3.2 compatibility fixes)

The container supports secure SSH credential mounting for git operations with three modes:

### Auto Mode (Default, Recommended)

Automatically detects SSH keys needed based on your project's git remotes:

```bash
start-dev-container.sh ~/projects/my-app
# Or explicitly:
start-dev-container.sh --ssh auto ~/projects/my-app
```

This mode:
- Parses `.git/config` to find SSH remotes (e.g., `git@github.com:user/repo.git`)
- Checks `~/.ssh/config` for host-specific IdentityFile directives
- Falls back to default keys (`id_ed25519`, `id_rsa`, `id_ecdsa`) if no config found
- Creates a temporary directory with ONLY the required keys
- Mounts the temporary directory to `/home/ralph/.ssh` in the container
- Automatically cleans up the temporary directory on exit (interactive mode)

**Security:** Only the specific SSH keys needed for your project's git remotes are exposed to the container, not your entire `~/.ssh` directory.

### Agent Mode

Uses SSH agent forwarding instead of mounting keys:

```bash
start-dev-container.sh --ssh agent ~/projects/my-app
```

Requirements:
- SSH agent must be running on host (`ssh-add -l` to verify)
- `SSH_AUTH_SOCK` environment variable must be set

Benefits:
- Keys never leave the host system
- Works with hardware security keys (YubiKey, etc.)
- No temporary file cleanup needed

### Manual Mode

Specify exact keys to mount:

```bash
start-dev-container.sh --ssh-key ~/.ssh/id_ed25519 ~/projects/my-app

# Multiple keys
start-dev-container.sh \
  --ssh-key ~/.ssh/work_key \
  --ssh-key ~/.ssh/personal_key \
  ~/projects/my-app
```

Use when:
- Auto-detection doesn't find the right keys
- You want explicit control over which keys are available
- Working with non-standard key paths

### No SSH Mode

Disable SSH credential mounting:

```bash
start-dev-container.sh --ssh none ~/projects/my-app
```

Use when working with HTTPS git remotes or when SSH isn't needed.

### What Gets Mounted

In auto and manual modes, the temporary SSH directory includes:
- The specified SSH private key(s)
- Corresponding public keys (`.pub` files)
- `~/.ssh/known_hosts` (to avoid host verification prompts)
- `~/.ssh/config` (for host-specific settings)

All files maintain proper permissions (600 for private keys, 644 for public keys).

### Troubleshooting SSH

**Check what SSH setup is active:**
The startup script shows the SSH configuration in its output:
```
Starting container 'clj-dev-my-app'...
  SSH:            auto-detected: /Users/you/.ssh/id_ed25519
```

**Verify SSH works inside container:**
```bash
# List mounted SSH keys
ls -la ~/.ssh/

# Test SSH connection
ssh -T git@github.com

# Check git remote configuration
git remote -v
```

**Common issues:**
- **"Permission denied (publickey)"**: Your key may not be authorized with the git host. Verify on host: `ssh -T git@github.com`
- **"No SSH keys detected"**: Project uses HTTPS remotes or no `.git` directory. Check: `git remote -v`
- **"SSH_AUTH_SOCK not set"**: Agent mode requires running SSH agent. Check: `ssh-add -l`
- **"local: -n: invalid option"**: Script requires bash 3.2+. This is fixed in v1.1.0+
- **Empty ~/.ssh/ directory in container**: Using daemon mode with older script version. The SSH directory cleanup ran too early. Use v1.1.0+ or manually mount SSH keys
- **"no such identity: /home/ralph/.ssh/keyname"**: SSH config references keys not mounted. The script mounts only detected keys. Use `--ssh-key` to add specific keys, or use `--ssh agent` mode
- **Wrong key detected**: Script uses SSH config parsing to find the right key. Verify your `~/.ssh/config` has correct `IdentityFile` for the host. Script supports both `IdentityFile ~/.ssh/key` and `IdentityFile=~/.ssh/key` formats

**Debug SSH issues:**
```bash
# Check what was mounted
docker inspect CONTAINER_NAME --format '{{json .Mounts}}' | python3 -m json.tool

# Check if SSH directory exists on host (daemon mode)
ls -la /var/folders/.../tmp.*  # Path shown in startup output

# Test SSH from container with verbose output
docker exec CONTAINER_NAME ssh -vT git@github.com 2>&1 | grep -E "(identity|key)"
```

---

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
- `.claude/commands/clojure-eval.md` - Slash command for nREPL evaluation
- `.claude/commands/start-nrepl.md` - Instructions for starting nREPL server

### Available Hooks

The setup script configures these Claude Code hooks:

**PreToolUse** - Before Write/Edit operations:
- Repairs parentheses using `clj-paren-repair-claude-hook`
- Optionally formats code with cljfmt

**PostToolUse** - After Write/Edit operations:
- Repairs parentheses and formats code

**SessionEnd** - When Claude Code session ends:
- Final cleanup and repair

---

## Playwright Integration

This image supports browser automation via Playwright MCP by running the MCP server on the host Mac with network transport. Playwright does not officially support Alpine Linux on ARM64, so the MCP server and browsers run on the host, and the container connects via HTTP (using `/mcp` or legacy `/sse` endpoints).

### Architecture

1. **Run Playwright MCP Server on Mac** with `--port` and `--allowed-hosts '*'` flags for network transport
2. **Start Container** normally (no port forwarding needed)
3. **Container Connects** to host via `http://host.docker.internal:PORT/mcp` (or legacy `/sse`)

### Two Modes

**Headless Mode** (automated testing/scraping):
- Command: `npx @playwright/mcp@latest --port 8931 --allowed-hosts '*'`
- Launches fresh browser instances
- No logged-in state or cookies

**Extension Mode** (logged-in sessions):
- Command: `npx @playwright/mcp@latest --extension --port 8931 --allowed-hosts '*'`
- Requires Playwright MCP Bridge Chrome extension
- Access to logged-in sessions, cookies, browser state
- Tab selection UI on first interaction

### Network Architecture

- Playwright MCP server runs on the host Mac (not in the container)
- No port forwarding needed - container connects outward to the host
- From inside container, MCP clients connect to `http://host.docker.internal:PORT/mcp` (or legacy `/sse`)
- Default MCP server port is 8931 (customizable)
- The `--allowed-hosts '*'` flag is required to allow connections from the Docker container
- `host.docker.internal` automatically resolves to the host machine's localhost from inside the container

---

## Development & Testing

### Building the Docker Image

```bash
docker build -t tonykayclj/clojure-node-claude:latest .
```

### Testing the Image Locally

```bash
docker run --rm tonykayclj/clojure-node-claude:latest bash -c \
  'clojure --version && node --version && claude --version && bb --version'
```

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

### Port Management

The startup script auto-discovers available ports in the 7888-8888 range and writes the selected port to `.nrepl-port` in the project directory. This allows:
- Multiple containers running simultaneously without port conflicts
- IDEs to automatically discover the nREPL port
- Consistent port forwarding from host to container (container always uses 7888)

---

## SSH Integration Testing Results

**Test Date:** 2025-11-19
**Status:** ✅ All tests passed

### Test Environment
- **Project**: fulcro (git@github.com:fulcrologic/fulcro.git)
- **SSH Config**: Non-standard format with `Host=` and `IdentityFile=` syntax
- **Key Used**: `~/.ssh/tony` (specified in SSH config for github.com)
- **Platform**: macOS with bash 3.2

### Issues Found & Fixed

#### 1. Bash 3.2 Compatibility (Line 156)
**Problem**: `local -n keys_array=$1` nameref syntax not supported on macOS default bash 3.2
```
Error: local: -n: invalid option
```
**Fix**: Changed `setup_ssh_dir()` to accept keys as positional parameters (`$@`) instead of nameref
- Changed: `setup_ssh_dir DETECTED_KEYS` → `setup_ssh_dir "${DETECTED_KEYS[@]}"`
- Changed: `setup_ssh_dir SSH_KEYS` → `setup_ssh_dir "${SSH_KEYS[@]}"`

#### 2. SSH Temp Directory Cleanup in Daemon Mode
**Problem**: EXIT trap deleted SSH directory immediately after starting daemon container, resulting in empty mount
```
ls -la ~/.ssh/    # Inside container: total 0
```
**Fix**: Only register cleanup trap for interactive mode; daemon mode provides manual cleanup command
- Added check: `if [ "$START_SHELL" = true ]; then trap cleanup_ssh EXIT INT TERM; fi`
- Added cleanup instructions in daemon mode output

#### 3. SSH Config Format Support
**Problem**: Regex only matched standard `Host github.com` format, not `Host=github.com`
- Script detected `~/.ssh/id_rsa` (default key) instead of `~/.ssh/tony` (configured key)
**Fix**: Updated regex to support both formats with optional `=`
- `Host[[:space:]]+` → `Host[=[:space:]]+`
- `IdentityFile[[:space:]]+` → `IdentityFile[=[:space:]]+`

### Test Results
All SSH integration tests passed:
```bash
# ✓ Correct key detected
Found 1 SSH key(s): /Users/tonykay/.ssh/tony

# ✓ Key mounted in container
-rw------- 1 ralph ralph 1675 tony
-rw-r--r-- 1 ralph ralph  405 tony.pub

# ✓ GitHub authentication working
Hi awkay! You've successfully authenticated

# ✓ Git operations working
From github.com:fulcrologic/fulcro
   4c877e56..308f42b0  main -> origin/main
```

### Lessons Learned
1. **Bash compatibility**: Always test on macOS default bash (3.2), not just Linux bash (4.x+)
2. **Daemon mode**: Cleanup traps trigger on script exit, not container exit
3. **SSH config parsing**: Support non-standard formats (some tools generate `Key=value` instead of `Key value`)
4. **Testing approach**: Live integration tests caught issues that syntax checks missed

---

## File Structure

```
.
├── Dockerfile                          # Multi-stage Docker image definition
├── CLAUDE.md                           # Project context for Claude Code
├── .cljfmt.edn                         # Default cljfmt configuration for this repo
└── scripts/
    ├── claude-setup-clojure            # Babashka script to configure projects
    ├── start-dev-container.sh          # Bash script to start dev containers (v1.1.0)
    └── resources/
        └── .cljfmt.edn                 # Template cljfmt config for new projects
```

---

## ARM64 Considerations

This image is built for ARM64 (Apple Silicon). Key points:
- **parinfer-rust**: Must be compiled from source (no ARM64 binaries in releases)
- **Babashka**: Copied from official multi-arch image
- **All other tools**: Use native ARM64 packages or are architecture-independent

For x86_64 support, the Dockerfile would need modifications to the parinfer-rust build stage (could potentially use pre-built binaries).

---

## Important Notes

- The image uses Alpine Linux (not Debian) for smaller size, with gcompat for glibc compatibility
- Scripts are copied into `/usr/local/bin/` for global availability
- Default cljfmt configuration uses `:indents ^:replace {#".*" [[:inner 0]]}` for consistent 2-space indentation
- The startup script requires `lsof` on the host machine to check port availability
- Container must have access to `.claude` directory from host for Claude Code authentication
- `start-dev-container.sh` v1.1.0+ is required for full SSH support with bash 3.2 compatibility

---

## Environment Variables

- `PATH`: Includes `/usr/local/bin` and `/home/ralph/.local/bin`
- `CLAUDE_CONFIG_DIR`: Set to `/home/ralph/.claude` by container startup script
- `CONTAINER_NREPL_PORT`: Fixed at 7888 (container-side port)
- `USE_BUILTIN_RIPGREP`: Set to 0 to prefer system ripgrep over Claude's built-in version

---

## License

See individual tool licenses. This Docker configuration and scripts are provided as-is for development use.
