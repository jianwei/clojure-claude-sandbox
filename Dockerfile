# Stage 1: Build parinfer-rust (use Debian for build, we only copy the binary)
FROM rust:slim AS parinfer-builder
RUN apt-get update && apt-get install -y \
    git \
    libclang-dev \
    && git clone --depth 1 --branch v0.4.3 https://github.com/eraserhd/parinfer-rust.git /tmp/parinfer-rust \
    && cd /tmp/parinfer-rust \
    && cargo build --release \
    && strip /tmp/parinfer-rust/target/release/parinfer-rust

# Stage 2: Node.js (for Claude Code)
FROM node:20-alpine AS node-builder

# Stage 3: Get Babashka
FROM babashka/babashka:latest AS babashka

# Stage 4: Final image
FROM eclipse-temurin:21-jdk-alpine

# Build metadata labels
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=1.0.0
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/fulcrologic/claude-sandbox" \
      org.opencontainers.image.title="Clojure Node Claude Development Environment" \
      org.opencontainers.image.description="Docker image for Clojure development with Claude Code integration"

# Install Clojure CLI tools, glibc compatibility, and sudo
ENV CLOJURE_VERSION=1.11.1.1435
RUN apk add --no-cache \
    bash \
    curl \
    git \
    openssh \
    ca-certificates \
    rlwrap \
    gcompat \
    sudo \
    vim \
    ripgrep \
    && curl -L -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh \
    && chmod +x linux-install.sh \
    && ./linux-install.sh \
    && rm linux-install.sh

# Create ralph user with sudo access
RUN adduser -D -s /bin/bash ralph \
    && echo "ralph ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Copy Node.js and npm from node image
COPY --from=node-builder /usr/local/bin/node /usr/local/bin/node
COPY --from=node-builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node-builder /opt/yarn-* /opt/
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Copy Babashka from official image (needs gcompat for glibc compatibility)
COPY --from=babashka /usr/local/bin/bb /usr/local/bin/bb

# Install bbin and configure environment for ralph
RUN curl -sLO https://raw.githubusercontent.com/babashka/bbin/main/bbin \
    && chmod +x bbin \
    && mv bbin /usr/local/bin/ \
    && mkdir -p /home/ralph/.local/bin /home/ralph/.npm-global \
    && chown -R ralph:ralph /home/ralph/.local /home/ralph/.npm-global \
    && echo 'export NPM_CONFIG_PREFIX="$HOME/.npm-global"' >> /home/ralph/.profile \
    && echo 'export PATH="/usr/local/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"' >> /home/ralph/.profile \
    && echo 'export USE_BUILTIN_RIPGREP=0' >> /home/ralph/.profile \
    && echo 'alias ccode="claude --dangerously-skip-permissions"' >> /home/ralph/.bashrc \
    && echo 'alias vi=vim' >> /home/ralph/.bashrc \
    && echo 'set -o vi' >> /home/ralph/.bashrc \
    && chown ralph:ralph /home/ralph/.profile /home/ralph/.bashrc

# Copy parinfer-rust from builder stage
COPY --from=parinfer-builder /tmp/parinfer-rust/target/release/parinfer-rust /usr/local/bin/parinfer-rust

# Switch to ralph user for installations
USER ralph
ENV PATH="/usr/local/bin:/home/ralph/.npm-global/bin:/home/ralph/.local/bin:${PATH}"
ENV NPM_CONFIG_PREFIX="/home/ralph/.npm-global"

# Install Claude Code as ralph user (allows ralph to update it)
RUN npm install -g @anthropic-ai/claude-code

# Install cljfmt via bbin
RUN bb /usr/local/bin/bbin install io.github.weavejester/cljfmt --as cljfmt

# Install clojure-mcp-light tools
RUN bb /usr/local/bin/bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.2.0 && \
    bb /usr/local/bin/bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.2.0 \
      --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'

# Switch back to root for copying files
USER root

# Add Claude setup script and resources
COPY scripts/claude-setup-clojure /usr/local/bin/claude-setup-clojure
COPY scripts/resources/.cljfmt.edn /usr/local/share/claude-clojure/.cljfmt.edn
COPY scripts/resources/.clojure /home/ralph/.clojure
RUN chmod +x /usr/local/bin/claude-setup-clojure \
    && mkdir -p /usr/local/share/claude-clojure

# Verification (as ralph user)
USER ralph
RUN node --version && \
    npm --version && \
    clojure --version && \
    bb --version && \
    bbin --version && \
    ls -la /usr/local/bin/parinfer-rust && \
    ls -la /home/ralph/.local/bin/cljfmt && \
    ls -la /home/ralph/.local/bin/clj-paren-repair-claude-hook && \
    ls -la /home/ralph/.local/bin/clj-nrepl-eval && \
    ls -la /home/ralph/.npm-global/bin/claude && \
    claude --version && \
    /usr/local/bin/claude-setup-clojure --help

# Set working directory and default user
WORKDIR /home/ralph
USER ralph

# Default command
CMD ["/bin/bash"]
