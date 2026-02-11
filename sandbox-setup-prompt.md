# Claude Code Sandbox Setup Prompt

Copy and paste everything below the line into a new Claude conversation to be guided through the full setup.

---

Help me set up a Docker sandbox for Claude Code so it can only access files inside a single folder on my computer — nothing else.

Use plain language. Assume I'm comfortable with the terminal but not a Docker expert. Show complete file contents — no placeholders. Proactively warn me about things that could go wrong.

## Phase 1: Prerequisites and file creation (give me all of this in a single response)

First, tell me what I need before starting (Docker Desktop, Anthropic API key, where to get them).

Then give me the complete contents of every file I need to create inside a new `claude_sandbox` folder. Explain briefly what each file does as you go. The files are:

1. **Dockerfile** — Base image `node:20-bookworm`. Install Claude Code via npm, Git, GitHub CLI. Configure SSH.
2. **entrypoint.sh** — Copy read-only SSH keys to a writable temp location (fixes macOS permission issues), rebuild node_modules for Linux, print a ready message, then exec the passed command.
3. **docker-compose.yml** — This is the core sandboxing file. Mount ONLY the sandbox folder as `/workspace`. Mount `~/.ssh` read-only. Use a named volume for Claude config persistence. Enable `stdin_open` and `tty`. Load env vars from `.env`. Set resource limits (4GB RAM, 2 CPUs).
4. **.claude/settings.json** — Enable sandbox mode. Set `autoAllowBashIfSandboxed: false`. Deny `Read`, `Edit`, `Grep`, `Glob` on `../`. Allow them on `./**`.
5. **.claude/settings.local.json** — Pre-approve `WebSearch`, `Bash(node:*)`, `Bash(curl:*)`.
6. **.env** (with placeholder API key), **.env.example**, **.gitignore**, **.dockerignore** — Keep secrets out of Git and Docker images.

End Phase 1 by showing me the expected folder structure and asking me to confirm all files are created.

## Phase 2: Build, run, and verify (walk me through this interactively)

Once I confirm the files are in place, guide me through:

1. `docker compose build` and `docker compose run --rm claude-sandbox`
2. Verification tests, one at a time — wait for my results before proceeding:
   - Create a canary file on my Desktop, search for it from inside the container
   - `docker inspect` to confirm `Privileged` is `false`
   - `docker inspect` to confirm only expected host paths are in `HostConfig.Binds`
   - Confirm `/var/run/docker.sock` is NOT mounted

After verification passes, give me a short summary of what protections are in place and why I can be confident Claude's access is contained.

Let's start.
