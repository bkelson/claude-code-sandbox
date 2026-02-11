#!/bin/bash
set -e

echo "==================================="
echo "  Claude Code Sandbox Container"
echo "==================================="

# SSH keys are mounted read-only for security. Copy them so SSH can use them
# (SSH refuses keys with group/other-readable permissions, and ro mounts keep macOS perms)
if [ -d /root/.ssh ] && [ "$(ls -A /root/.ssh 2>/dev/null)" ]; then
    cp -r /root/.ssh /tmp/.ssh-copy 2>/dev/null || true
    if [ -d /tmp/.ssh-copy ]; then
        chmod 700 /tmp/.ssh-copy
        find /tmp/.ssh-copy -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true
        find /tmp/.ssh-copy -type f -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
        find /tmp/.ssh-copy -type f -name "config" -exec chmod 600 {} \; 2>/dev/null || true
        # Configure git to use the writable key copy.
        # Uses git config (not an env var) so it persists for exec'd sessions.
        git config --global core.sshCommand "ssh -i /tmp/.ssh-copy/id_ed25519 -o UserKnownHostsFile=/tmp/.ssh-copy/known_hosts -o StrictHostKeyChecking=accept-new"
        echo "[ssh] Keys loaded from read-only mount"
    fi
fi

# Rebuild node_modules for Linux if any project has them
for pkg in /workspace/*/package.json; do
    if [ -f "$pkg" ]; then
        project_dir=$(dirname "$pkg")
        project_name=$(basename "$project_dir")

        if [ -d "$project_dir/node_modules" ]; then
            echo "[setup] Rebuilding node_modules for $project_name (macOS -> Linux)..."
            cd "$project_dir"
            npm rebuild 2>/dev/null || npm install
            cd /workspace
        fi
    fi
done

echo ""
echo "[ready] Workspace: /workspace"
echo "[ready] Port 3000 mapped for MCP HTTP server"
echo "[ready] Start Claude with: docker compose exec claude-sandbox claude"
echo ""

# Execute the container's CMD (default: sleep infinity to keep container alive)
exec "$@"
