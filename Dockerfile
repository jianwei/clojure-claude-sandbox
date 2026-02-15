# Stage 1: Build parinfer-rust (use Debian for build, we only copy the binary)
FROM rust:slim AS parinfer-builder
# Configure Aliyun mirror for Debian
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources \
    && sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources
# Configure cargo mirror (TUNA) for faster crate downloads
RUN mkdir -p /root/.cargo && echo '[source.crates-io]\nreplace-with = "tuna"\n[source.tuna]\nregistry = "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git"' > /root/.cargo/config.toml
RUN apt-get update && apt-get install -y \
    git \
    libclang-dev \
    && git clone --depth 1 --branch v0.4.3 https://github.com/eraserhd/parinfer-rust.git /tmp/parinfer-rust \
    && cd /tmp/parinfer-rust \
    && cargo build --release \
    && strip /tmp/parinfer-rust/target/release/parinfer-rust

# Stage 2: Node.js (for Claude Code)
FROM node:20 AS node-builder

# Stage 3: Get Babashka
FROM babashka/babashka:latest AS babashka

# Stage 4: Final image (Ubuntu 24.04)
FROM eclipse-temurin:21-jdk-noble

# Configure Aliyun mirror for Ubuntu
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list.d/ubuntu.sources \
    && sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list.d/ubuntu.sources

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

# Install Clojure CLI tools and sudo
ENV CLOJURE_VERSION=1.11.1.1435
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    openssh-client \
    ca-certificates \
    rlwrap \
    sudo \
    vim \
    ripgrep \
    && curl -L -O https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh \
    && chmod +x linux-install.sh \
    && ./linux-install.sh \
    && rm linux-install.sh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create ralph user with sudo access
RUN useradd -m -s /bin/bash ralph \
    && echo "ralph ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Copy Node.js and npm from node image
COPY --from=node-builder /usr/local/bin/node /usr/local/bin/node
COPY --from=node-builder /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Copy Babashka from official image
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

# Configure npm to use npmmirror (TaoBao) for faster downloads
RUN npm config set registry https://registry.npmmirror.com

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
# Fix CRLF line endings from Windows git checkout
RUN sed -i 's/\r$//' /usr/local/bin/claude-setup-clojure \
    && chmod +x /usr/local/bin/claude-setup-clojure \
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