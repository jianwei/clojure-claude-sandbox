FROM babashka/babashka:latest AS babashka
FROM clojure:temurin-25-tools-deps

# Copy babashka from official image
COPY --from=babashka /usr/local/bin/bb /usr/local/bin/bb

# Layer 1: Install system packages (rarely changes)
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    ca-certificates \
    nodejs \
    npm \
    awscli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 1.5: Install bbin and configure environment
RUN bb --version && \
    curl -sLO https://raw.githubusercontent.com/babashka/bbin/main/bbin && \
    chmod +x bbin && \
    mv bbin /usr/local/bin/ && \
    sed -i '1s|^#!/usr/bin/env bb|#!/usr/local/bin/bb|' /usr/local/bin/bbin && \
    mkdir -p /root/.local/bin && \
    echo 'export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"' >> /root/.profile && \
    echo 'export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"' >> /root/.bashrc

# Layer 1.6: Build and install parinfer-rust (requires Rust toolchain)
# We build from source since ARM binaries aren't provided in releases
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
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Layer 1.7: Install cljfmt via bbin
ENV PATH="/usr/local/bin:/root/.local/bin:${PATH}"
RUN /usr/local/bin/bb /usr/local/bin/bbin install io.github.weavejester/cljfmt --as cljfmt

# Layer 1.8: Install clojure-mcp-light tools
RUN /usr/local/bin/bb /usr/local/bin/bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.1.1 && \
    /usr/local/bin/bb /usr/local/bin/bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.1.1 \
      --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'

# Layer 2: Install and configure nvm (rarely changes)
ENV NVM_DIR="/root/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && \
    echo 'export NVM_DIR="$HOME/.nvm"' >> /root/.profile && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /root/.profile && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> /root/.profile && \
    echo 'export NVM_DIR="$HOME/.nvm"' >> /root/.bashrc && \
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /root/.bashrc && \
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> /root/.bashrc && \
    echo 'alias ccode="claude --dangerously-disable-permissions"' >> /root/.bashrc

# Layer 3: Install global npm packages (changes when updating packages)
# Add new global packages here, each on its own line for better caching
RUN npm install -g @anthropic-ai/claude-code

# Layer 4: Add Claude setup script and resources (may change during development)
COPY scripts/claude-setup-clojure /usr/local/bin/claude-setup-clojure
COPY scripts/resources/.cljfmt.edn /usr/local/share/claude-clojure/.cljfmt.edn
RUN chmod +x /usr/local/bin/claude-setup-clojure && \
    mkdir -p /usr/local/share/claude-clojure

# Layer 5: Verification
RUN node --version && \
    npm --version && \
    claude --version && \
    bash -c '. "$NVM_DIR/nvm.sh" && nvm --version' && \
    bb --version && \
    bbin --version && \
    ls -la /usr/local/bin/parinfer-rust && \
    ls -la /root/.local/bin/cljfmt && \
    ls -la /root/.local/bin/clj-paren-repair-claude-hook && \
    ls -la /root/.local/bin/clj-nrepl-eval && \
    /usr/local/bin/claude-setup-clojure --help

# Default command
CMD ["/bin/bash"]
