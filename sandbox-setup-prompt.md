# Claude Code Sandbox Setup Prompt

Copy and paste everything below the line into a new Claude conversation to be guided through the full setup.

---

Help me set up a Docker sandbox for Claude Code so it can only access files inside a single folder on my computer — nothing else.

Use plain language. Assume I'm comfortable with the terminal but not a Docker expert. Show complete file contents — no placeholders. Proactively warn me about things that could go wrong.

## Phase 1: Prerequisites and file creation (give me all of this in a single response)

First, tell me what I need before starting (Docker Desktop, Anthropic API key, where to get them).

Then give me the complete contents of every file I need to create inside a new `claude_sandbox` folder. Explain briefly what each file does as you go. The files are:

1. **Dockerfile** — Base image `node:20-bookworm`. Install Claude Code via npm, Git, GitHub CLI. Configure SSH. Use `CMD ["sleep", "infinity"]` so the container stays alive in the background — Claude Code sessions are started separately via `docker compose exec`.
2. **entrypoint.sh** — Copy read-only SSH keys to a writable temp location (fixes macOS permission issues). Use `git config --global core.sshCommand` (not an environment variable export) to point Git at the copied keys — this ensures the SSH config persists for `docker compose exec` sessions, not just the entrypoint process. Rebuild node_modules for Linux. Print a ready message. Then exec the passed command (`sleep infinity` by default).
3. **docker-compose.yml** — This is the core sandboxing file. Mount ONLY the sandbox folder as `/workspace`. Mount `~/.ssh` read-only. Use a named volume for Claude config persistence. Enable `stdin_open` and `tty`. Load env vars from `.env`. Set resource limits (4GB RAM, 2 CPUs).
4. **.claude/settings.json** — Enable sandbox mode. Set `autoAllowBashIfSandboxed: false`. Deny `Read`, `Edit`, `Grep`, `Glob` on `../`. Allow them on `./**`.
5. **.claude/settings.local.json** — Pre-approve `WebSearch`, `Bash(node:*)`, `Bash(curl:*)`.
6. **.env** (with placeholder API key), **.env.example**, **.gitignore**, **.dockerignore** — Keep secrets out of Git and Docker images.

End Phase 1 by showing me the expected folder structure and asking me to confirm all files are created.

## Phase 2: Build, start, and verify (walk me through this interactively)

Once I confirm the files are in place, guide me through:

1. `docker compose build` to build the image, then `docker compose up -d` to start the container in the background. Then `docker compose exec claude-sandbox claude` to start an interactive Claude Code session. Explain that this persistent container model (as opposed to `docker compose run --rm`) avoids losing writable-layer state between sessions — named volumes persist auth tokens either way, but container-layer config like `git config --global core.sshCommand` only survives in a persistent container. Also explain that `run --rm` creates containers with random names, which breaks `docker inspect` verification commands.
2. Suggest I add a `claude_docker` shell function to my `~/.bashrc` or `~/.zshrc` so I can launch sandboxed Claude from anywhere. Warn me NOT to name it `claude` — that would shadow the native Claude Code binary. The function should run `docker compose -f ~/claude_sandbox/docker-compose.yml up -d` first (to ensure the container is running), then `docker compose -f ~/claude_sandbox/docker-compose.yml exec claude-sandbox claude "$@"`.
3. Verification tests, one at a time — wait for my results before proceeding:
   - Create a canary file on my Desktop, search for it from inside the running container using `docker compose exec`
   - `docker inspect claude-sandbox` to confirm `Privileged` is `false`
   - `docker inspect claude-sandbox` to confirm only expected host paths are in `HostConfig.Binds`
   - Confirm `/var/run/docker.sock` is NOT mounted

After verification passes, give me a short summary of what protections are in place and why I can be confident Claude's access is contained.

Let's start.
