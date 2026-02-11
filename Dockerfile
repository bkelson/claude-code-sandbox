FROM node:20-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code

# Install GitHub CLI (for gh commands inside the container)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Create workspace directory
RUN mkdir -p /workspace

# Set working directory
WORKDIR /workspace

# Configure git to trust the mounted workspace
RUN git config --global --add safe.directory /workspace

# SSH config: don't prompt for host key verification on first connect
RUN mkdir -p /root/.ssh && \
    echo "Host github.com\n  StrictHostKeyChecking accept-new\n  IdentityFile /root/.ssh/id_ed25519" \
    > /root/.ssh/config && \
    chmod 600 /root/.ssh/config

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose port for MCP HTTP/OAuth server
EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Keep the container running so you can exec into it with:
#   docker compose exec claude-sandbox claude
CMD ["sleep", "infinity"]
