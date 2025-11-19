# Claude MCP Light Setup Plan

## Overview
Add support for clojure-mcp-light to the Docker image and provide an easy setup script for configuring projects.

**Key Goal:** Users can run `claude-setup-clojure` in any project directory to configure Claude Code with Clojure tooling support.

---

## Phase 1: Update Dockerfile

### 1.1 Install Babashka
Add to Dockerfile after Layer 1 (system packages):
```dockerfile
# Layer 1.5: Install Babashka (stable, rarely changes)
RUN curl -sLO https://raw.githubusercontent.com/babashka/babashka/master/install && \
    chmod +x install && \
    ./install && \
    rm install
```

### 1.2 Install bbin (Babashka package manager)
Add after Babashka installation:
```dockerfile
# Layer 1.6: Install bbin
RUN curl -sLO https://raw.githubusercontent.com/babashka/bbin/main/bbin && \
    chmod +x bbin && \
    mv bbin /usr/local/bin/ && \
    mkdir -p /root/.local/bin && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc
```

### 1.3 Install parinfer-rust
Add after bbin:
```dockerfile
# Layer 1.7: Install parinfer-rust
RUN curl -sLO https://github.com/eraserhd/parinfer-rust/releases/download/v0.4.6/parinfer-rust-linux.tar.gz && \
    tar -xzf parinfer-rust-linux.tar.gz && \
    mv parinfer-rust /usr/local/bin/ && \
    rm parinfer-rust-linux.tar.gz
```

### 1.4 Install cljfmt (optional but recommended)
Add to Layer 3 or create new layer:
```dockerfile
# Layer 1.8: Install cljfmt via bbin
RUN /root/.local/bin/bbin install io.github.weavejester/cljfmt --as cljfmt
```

### 1.5 Install clojure-mcp-light tools
Add after cljfmt:
```dockerfile
# Layer 1.9: Install clojure-mcp-light tools
RUN /root/.local/bin/bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.1.1 && \
    /root/.local/bin/bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.1.1 \
      --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'
```

### 1.6 Add setup script and resources to image
```dockerfile
# Layer 1.10: Add Claude setup script and resources
COPY scripts/claude-setup-clojure /usr/local/bin/claude-setup-clojure
COPY scripts/resources/.cljfmt.edn /usr/local/share/claude-clojure/.cljfmt.edn
RUN chmod +x /usr/local/bin/claude-setup-clojure
```

---

## Phase 2: Create Babashka Setup Script

### 2.1 Script Location
- File: `scripts/claude-setup-clojure`
- Will be copied to: `/usr/local/bin/claude-setup-clojure` in Docker image

### 2.2 Script Functionality
The script should:
1. Check if `.claude` directory exists, create if not
2. Create/update `.claude/settings.local.json` with hooks configuration
3. Copy `.cljfmt.edn` to project root if it doesn't already exist
4. Optionally create `.claude/commands/` directory
5. Optionally copy/create sample slash commands
6. Provide feedback on what was created

### 2.3 Script Features
- **--force**: Overwrite existing configuration files (settings.local.json and commands)
- **--force-cljfmt**: Overwrite existing .cljfmt.edn (by default, existing file is preserved)
- **--no-commands**: Skip slash command setup
- **--cljfmt**: Enable cljfmt in hooks (default: enabled)
- **--dry-run**: Show what would be created without creating
- **--help**: Show usage information

### 2.4 Configuration Template
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "clj-paren-repair-claude-hook --cljfmt"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "clj-paren-repair-claude-hook --cljfmt"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "clj-paren-repair-claude-hook --cljfmt"
          }
        ]
      }
    ]
  }
}
```

### 2.5 Resource Files

#### .cljfmt.edn Template
Located at: `/usr/local/share/claude-clojure/.cljfmt.edn` in Docker image
Source: `scripts/resources/.cljfmt.edn`

This configuration provides:
- 2-space indentation for all forms
- Aligned map columns
- Standard formatting options
- Compatible with IntelliJ/Cursive settings

The script will copy this to project root if `.cljfmt.edn` doesn't already exist.
Use `--force-cljfmt` to overwrite existing file.

### 2.6 Slash Commands to Create
- `.claude/commands/clojure-eval.md` - Evaluate Clojure code in running nREPL
- `.claude/commands/start-nrepl.md` - Instructions for starting nREPL server

---

## Phase 3: Implementation Steps

### Step 1: Create scripts directory structure
```bash
mkdir -p scripts/resources
cp .cljfmt.edn scripts/resources/.cljfmt.edn
```

### Step 2: Write claude-setup-clojure script
Create `scripts/claude-setup-clojure` as a Babashka script with:
- Shebang: `#!/usr/bin/env bb`
- Command-line argument parsing
- JSON generation for settings
- File creation logic (.claude/settings.local.json, .cljfmt.edn, slash commands)
- Smart handling of existing files (preserve unless --force or --force-cljfmt)
- User feedback showing what was created/skipped

### Step 3: Update Dockerfile
Add all the new layers in the correct order to optimize caching.

### Step 4: Test locally
```bash
# Build image
docker build -t tonykayclj/clojure-node-claude:latest .

# Test script
docker run --rm -v $(pwd)/test-project:/workspace -w /workspace \
  tonykayclj/clojure-node-claude:latest \
  claude-setup-clojure

# Verify files were created
docker run --rm -v $(pwd)/test-project:/workspace -w /workspace \
  tonykayclj/clojure-node-claude:latest \
  bash -c 'ls -la .claude && cat .claude/settings.local.json && ls -la .cljfmt.edn'
```

### Step 5: Update documentation.md
Add section about:
- Running `claude-setup-clojure` to configure projects
- What the script does
- Script options
- How to use the configured hooks and commands

---

## Phase 4: Enhanced Features (Future)

### 4.1 Project Detection
Script could detect if project is already using:
- deps.edn (tools.deps project)
- project.clj (Leiningen project)
- shadow-cljs.edn (ClojureScript project)

And adjust configuration accordingly.

### 4.2 nREPL Port Configuration
Allow specifying default nREPL port in configuration.

### 4.3 Multiple Configuration Profiles
Support different profiles:
- `--profile minimal` - Just parinfer, no formatting
- `--profile full` - All features enabled
- `--profile fulcro` - Fulcro-specific optimizations

---

## Dependencies Summary

### System Packages (Alpine apk)
- bash (already installed)
- curl (already installed)
- git (already installed)

### Binary Installations
- Babashka (via install script)
- bbin (via curl from GitHub)
- parinfer-rust (binary from GitHub releases)

### Babashka/bbin Packages
- cljfmt (via bbin from io.github.weavejester/cljfmt)
- clj-paren-repair-claude-hook (via bbin from clojure-mcp-light repo)
- clj-nrepl-eval (via bbin from clojure-mcp-light repo)

---

## Testing Checklist

- [ ] Dockerfile builds successfully
- [ ] All tools are on PATH
- [ ] `bb --version` works
- [ ] `bbin --version` works
- [ ] `parinfer-rust --version` works
- [ ] `cljfmt --version` works
- [ ] `clj-paren-repair-claude-hook --help` works
- [ ] `clj-nrepl-eval --help` works
- [ ] `claude-setup-clojure --help` works
- [ ] Script creates `.claude` directory
- [ ] Script creates valid JSON in `settings.local.json`
- [ ] Script creates `.cljfmt.edn` if it doesn't exist
- [ ] Script preserves existing `.cljfmt.edn` by default
- [ ] Script overwrites `.cljfmt.edn` with `--force-cljfmt`
- [ ] Script creates slash commands (if enabled)
- [ ] Hooks execute successfully when using Claude Code
- [ ] Claude Code can use the slash commands
- [ ] cljfmt uses the .cljfmt.edn configuration correctly

---

## Current Status

- [ ] Phase 1: Update Dockerfile
  - [ ] 1.1 Install Babashka
  - [ ] 1.2 Install bbin
  - [ ] 1.3 Install parinfer-rust
  - [ ] 1.4 Install cljfmt
  - [ ] 1.5 Install clojure-mcp-light tools
  - [ ] 1.6 Add setup script to image

- [ ] Phase 2: Create Babashka Setup Script
  - [ ] 2.1 Create scripts directory structure
  - [ ] 2.2 Copy .cljfmt.edn to scripts/resources/
  - [ ] 2.3 Write main script logic
  - [ ] 2.4 Add command-line argument parsing
  - [ ] 2.5 Add JSON generation
  - [ ] 2.6 Add .cljfmt.edn copy logic
  - [ ] 2.7 Add slash command creation

- [ ] Phase 3: Implementation
  - [ ] Step 1: Create scripts directory
  - [ ] Step 2: Write setup script
  - [ ] Step 3: Update Dockerfile
  - [ ] Step 4: Test locally
  - [ ] Step 5: Update documentation

- [ ] Phase 4: Documentation
  - [ ] Update documentation.md
  - [ ] Add usage examples
  - [ ] Add troubleshooting section
