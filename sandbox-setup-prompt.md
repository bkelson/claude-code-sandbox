# Claude Code Sandbox Setup Prompt

Copy and paste everything below the line into a new Claude conversation to be guided through the full setup.

---

I want you to help me set up a Docker sandbox for Claude Code so that when Claude runs, it can only access files inside a single folder on my computer — and nothing else.

Walk me through this step by step, one step at a time. Wait for me to confirm each step is done before moving to the next one. If I run into errors, help me troubleshoot before continuing.

Here is exactly what I need you to help me build:

## What we're building

A Docker container that runs Claude Code in isolation. The container should:

- Only have access to one folder on my computer (the sandbox folder)
- Mount my SSH keys as read-only so Git push/pull still works
- Have Claude Code's built-in permissions configured to deny access outside the workspace
- Have resource limits (4GB RAM, 2 CPUs) to prevent runaway processes
- Persist Claude Code configuration between restarts using a Docker volume
- Require my approval before Claude runs any shell command

## The steps I need you to guide me through

1. **Prerequisites check** — Confirm I have Docker Desktop installed and an Anthropic API key. If I don't, tell me where to get them.

2. **Create the sandbox folder** — Have me create a single folder that will be Claude's entire world. Explain that anything outside this folder will be invisible to Claude.

3. **Create the Dockerfile** — Walk me through creating a Dockerfile that installs Node.js, Claude Code (via npm), Git, GitHub CLI, and configures SSH. Use `node:20-bookworm` as the base image. Include an entrypoint script.

4. **Create the entrypoint script** (`entrypoint.sh`) — This should handle copying read-only SSH keys to a writable temp location (fixing macOS permission issues), rebuilding any node_modules for Linux, and printing a ready message.

5. **Create docker-compose.yml** — This is the critical sandboxing file. It should:
   - Mount only the sandbox folder as `/workspace`
   - Mount `~/.ssh` as read-only
   - Use a named Docker volume for Claude config persistence
   - Set `stdin_open: true` and `tty: true` for interactive sessions
   - Load environment variables from a `.env` file
   - Set memory and CPU limits

6. **Create Claude Code permission rules** — Create `.claude/settings.json` inside the sandbox folder with:
   - Sandbox mode enabled
   - `autoAllowBashIfSandboxed` set to false
   - Deny rules for `Read`, `Edit`, `Grep`, `Glob` on `../` (parent directory)
   - Allow rules for `Read`, `Edit`, `Grep`, `Glob` on `./**` (workspace and below)
   - A separate `.claude/settings.local.json` that pre-approves `WebSearch`, `Bash(node:*)`, and `Bash(curl:*)`

7. **Set up the API key** — Have me create a `.env` file with my Anthropic API key, plus a `.gitignore` and `.dockerignore` to make sure secrets never get committed or baked into the Docker image.

8. **Build and run** — Walk me through `docker compose build` and `docker compose run --rm claude-sandbox`. Explain what the `--rm` flag does.

9. **Verify the sandbox** — After it's running, guide me through these verification tests:
   - Create a canary file on my Desktop and try to find it from inside the container
   - Check that the container is not running in privileged mode (`docker inspect` for `HostConfig.Privileged`)
   - Confirm exactly what host paths are mounted (`docker inspect` for `HostConfig.Binds`)
   - Confirm `/var/run/docker.sock` is NOT mounted

## Important guidelines for you

- Explain everything in plain, simple language. Assume I'm comfortable with the terminal but not an expert in Docker.
- Show me the complete file contents for every file I need to create. Don't skip anything or use placeholders like "add your config here."
- If something could go wrong at a given step (like Docker not running, or SSH keys not existing), proactively tell me what to check.
- After all steps are done, give me a summary of what protections are in place and why I can be confident that Claude's access is contained.

Let's start with Step 1.
