# How I Put Claude Code in a Sandbox (And Why You Should Too)

## What This Is About

I use Claude Code — Anthropic's AI coding assistant that runs in your terminal. It's powerful. It can read files, edit code, run commands, and basically act like a very fast developer sitting at your keyboard. That power is exactly why I wanted to put guardrails around it.

By default, Claude Code runs directly on your computer. That means it *could* theoretically read or modify files anywhere on your machine — your Documents folder, your Desktop, your personal files. It probably won't do anything malicious, but I like the principle of least privilege: give any tool access to only what it needs, and nothing more.

So I set up a **Docker sandbox** — a sealed-off container that Claude Code runs inside. Think of it like giving someone a room to work in, but locking all the other doors in the house. Claude can only see and touch the files I explicitly put in front of it.

Here's exactly how I did it, step by step.

> **Want to skip the reading and just do it?** This repo includes two companion prompt templates:
> - [**sandbox-setup-prompt.md**](sandbox-setup-prompt.md) — Paste this into Claude and it will walk you through the entire setup interactively.
> - [**sandbox-verification-prompt.md**](sandbox-verification-prompt.md) — Paste this into a *different* LLM (like ChatGPT) to get an independent, unbiased verification that the sandbox is actually secure.

---

## Native Mode vs. Docker Sandbox Mode

There are two ways to run Claude Code. Understanding the difference matters before you decide whether this guide is for you.

**Native mode** is the default. Claude Code runs directly on your machine as your user account. It can read and modify any file you have access to — your code, your documents, your downloads, everything. This is fine if you trust the tool completely, but it violates the principle of least privilege.

**Docker sandbox mode** is what this guide sets up. Claude Code runs inside a container that can only see files you explicitly mount into it. Everything else on your machine is invisible — not hidden, not restricted, but *nonexistent* from the container's perspective.

Here's how the file access differs:

```
  Your Computer (Host)                   Docker Container
 ┌─────────────────────┐               ┌──────────────────┐
 │                     │               │                  │
 │ ~/Desktop/          │  (blocked)    │                  │
 │ ~/Documents/        │  (blocked)    │                  │
 │ ~/Photos/           │  (blocked)    │                  │
 │                     │               │                  │
 │ ~/claude_sandbox/ ─────── rw ──────>│ /workspace/      │
 │   ├── Dockerfile    │               │   ├── Dockerfile │
 │   ├── my-project/   │               │   ├── my-project/│
 │   └── ...           │               │   └── ...        │
 │                     │               │                  │
 │ ~/.ssh/ ───────────────── ro ──────>│ /root/.ssh/      │
 │                     │               │                  │
 └─────────────────────┘               │ Claude Code runs │
                                       │ here — can only  │
                                       │ see /workspace   │
                                       └──────────────────┘

 rw = read-write    ro = read-only    (blocked) = not mounted, does not exist
```

The `claude_sandbox` folder on your host is the **only** directory that appears inside the container. It shows up as `/workspace`. Your SSH keys are also mounted, but read-only — Claude can use them to push and pull code, but cannot modify or exfiltrate them. Everything else on your machine simply does not exist from the container's point of view.

---

## What You'll Need Before Starting

- **A Mac** (this was built on macOS, but it works on Linux too)
- **Docker Desktop** installed ([download here](https://www.docker.com/products/docker-desktop/))
- **An Anthropic API key** (you get this from [console.anthropic.com](https://console.anthropic.com/))
- Basic comfort with the terminal (you'll be copying and pasting commands)

---

## Step 1: Create a Folder That Will Be Claude's Entire World

First, I created a folder on my computer. This single folder is the *only* thing Claude will ever be able to see or touch.

```bash
mkdir claude_sandbox
cd claude_sandbox
```

Everything from here on out happens inside this folder. Any project files you want Claude to work on go in here. Anything outside this folder is invisible to Claude.

---

## Step 2: Create the Dockerfile (Claude's Operating Environment)

A Dockerfile is like a recipe that tells Docker how to build the container. I created a file called `Dockerfile` with the following contents:

```dockerfile
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
```

**What this does in plain English:**
- Starts with a standard Linux environment that has Node.js installed
- Installs Git, curl, and a few other basic tools
- Installs Claude Code (the same way you'd install it normally, with `npm`)
- Installs the GitHub CLI so Claude can interact with GitHub
- Creates a `/workspace` folder inside the container — this is where your files will appear
- Sets up SSH configuration so Git push/pull works with GitHub
- Uses `sleep infinity` as the default command to keep the container running in the background — you start Claude by exec-ing into the container (explained in Step 7)

---

## Step 3: Create the Entrypoint Script (What Runs When the Container Starts)

I created a file called `entrypoint.sh`. This runs once when the container boots up:

```bash
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
```

**What this does in plain English:**
- Prints a welcome message so you know the container started
- Handles a tricky SSH permissions issue: your SSH keys are mounted read-only (for safety), but SSH is picky about file permissions. So the script copies them to a temporary location with the right permissions, then configures Git to use the copies. Because this is stored in `git config` (not an environment variable), it remains available for any process you later exec into the container — including Claude Code sessions.
- If any of your projects have Node.js dependencies (`node_modules`), it rebuilds them for Linux, since your Mac's versions won't work inside the container
- Runs the container's default command (`sleep infinity`), which keeps the container alive in the background

---

## Step 4: Create the Docker Compose File (The Master Configuration)

Docker Compose lets you define your entire container setup in one clean file. I created `docker-compose.yml`:

```yaml
services:
  claude-sandbox:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: claude-sandbox
    stdin_open: true    # Allocate stdin for interactive exec sessions
    tty: true           # Allocate a TTY for terminal colors and input

    # Load secrets from .env file
    env_file:
      - .env

    ports:
      # MCP bridge OAuth/HTTP server
      - "3000:3000"

    volumes:
      # Mount your project files (this is the ONLY host directory visible)
      - ./:/workspace

      # Mount SSH keys for Git push/pull (read-only for safety)
      - ~/.ssh:/root/.ssh:ro

      # Persist Claude Code config between container restarts
      - claude-config:/root/.claude

    # Resource limits (prevents runaway processes)
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: "2.0"

volumes:
  claude-config:
```

**What this does in plain English:**

This is the most important file for understanding the sandbox. Here's what each piece does:

- **`stdin_open` and `tty`**: These allocate a terminal so that interactive sessions (via `docker compose exec`) work properly with Claude Code's input and colored output.
- **`env_file: .env`**: Loads your API key from a separate file (so it's not hardcoded anywhere).
- **`volumes`** — this is where the sandboxing happens:
  - `./:/workspace` — Mounts your `claude_sandbox` folder as `/workspace` inside the container. **This is the only part of your computer Claude can see.** Your home folder, Desktop, Documents, photos, everything else — completely invisible.
  - `~/.ssh:/root/.ssh:ro` — Mounts your SSH keys so Git works, but the `:ro` means **read-only**. Claude can use the keys to push/pull code, but it cannot modify or delete them.
  - `claude-config:/root/.claude` — This is a Docker-managed volume that stores Claude's own configuration. It persists between restarts so you don't have to re-authenticate every time.
- **Resource limits**: Caps the container at 4GB of RAM and 2 CPU cores. This prevents any runaway process from eating up your entire machine.

---

## Step 5: Set Up Claude Code's Own Permission Rules

Docker keeps Claude from seeing files outside the sandbox folder. But I added a second layer of protection using Claude Code's built-in permission system. Inside the sandbox folder, I created `.claude/settings.json`:

```json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": false
  },
  "permissions": {
    "deny": [
      "Read(../)",
      "Edit(../)",
      "Grep(../)",
      "Glob(../)"
    ],
    "allow": [
      "Read(./**)",
      "Edit(./**)",
      "Grep(./**)",
      "Glob(./**)"
    ]
  }
}
```

**What this does in plain English:**
- **Sandbox mode is on.** Claude Code operates in its restricted mode.
- **`autoAllowBashIfSandboxed: false`** — Even inside the sandbox, Claude still has to ask you before running any shell command. It doesn't get a free pass.
- **Deny rules**: Claude is explicitly blocked from reading, editing, searching, or listing files in any parent directory (`../` means "go up one level"). This prevents any attempt to escape the workspace.
- **Allow rules**: Claude *can* read, edit, search, and list files within the workspace and all its subfolders (`./**` means "everything under the current directory").

I also created `.claude/settings.local.json` for a few additional pre-approved tools:

```json
{
  "permissions": {
    "allow": [
      "WebSearch",
      "Bash(node:*)",
      "Bash(curl:*)"
    ]
  }
}
```

This lets Claude search the web, run Node.js, and use curl without asking every time — since those are safe, normal operations for coding work.

---

## Step 6: Set Up Your API Key

I created a `.env` file to hold the Anthropic API key:

```
# Anthropic API key
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxxx

# Auth0 credentials (optional, for MCP bridge)
AUTH0_DOMAIN=
AUTH0_AUDIENCE=

# MCP bridge HTTP port
PORT=3000
```

Replace `sk-ant-xxxxxxxxxxxxxxxxxxxxx` with your actual API key from [console.anthropic.com](https://console.anthropic.com/).

**Important:** This file contains your secret key. Never commit it to Git. That's why I also created a `.gitignore` file:

```
# Environment secrets
.env
.env.*
!.env.example
```

And a `.dockerignore` to keep secrets out of the Docker image itself:

```
**/node_modules
**/.git
.env
.env.*
!.env.example
.DS_Store
**/.DS_Store
```

---

## Step 7: Build and Run

With all the files in place, building and launching the sandbox is straightforward.

### First time: build the image and start the container

```bash
# Build the container image (only needed the first time, or after changing the Dockerfile)
docker compose build

# Start the container in the background
docker compose up -d
```

The container starts, runs the entrypoint script (SSH setup, node_modules rebuild), then stays alive in the background via `sleep infinity`. You can verify it's running with `docker compose ps`.

### Start a Claude Code session

```bash
docker compose exec claude-sandbox claude
```

This opens an interactive Claude Code session inside the running container. When you're done, just exit Claude normally (`/exit` or Ctrl+C). The container keeps running in the background, ready for your next session.

### Day-to-day usage

You only need two commands for daily use:

```bash
# If the container isn't already running:
docker compose up -d

# Start Claude:
docker compose exec claude-sandbox claude
```

### Optional: create an alias

To save typing, add a function to your `~/.bashrc` or `~/.zshrc`:

```bash
claude_docker() {
    docker compose -f ~/claude_sandbox/docker-compose.yml up -d && \
    docker compose -f ~/claude_sandbox/docker-compose.yml exec claude-sandbox claude "$@"
}
```

This starts the container if it isn't already running (`up -d` is a no-op if it's already up), then opens a Claude session. You can launch a sandbox session from anywhere with just `claude_docker`.

### Stopping the container

When you want to shut the sandbox down completely:

```bash
docker compose down
```

This stops the container but preserves your workspace files and the `claude-config` volume (so authentication tokens persist). To start again later, just run `docker compose up -d`.

### Why not `docker compose run --rm`?

Older versions of this guide used `docker compose run --rm claude-sandbox` to start sessions. This creates an **ephemeral container** — a fresh, temporary container that is destroyed when you exit. While it can work, it introduces several issues:

1. **No stable container identity.** `run --rm` creates a container with a random name each time. Commands like `docker inspect claude-sandbox` target the named service container and won't find the ephemeral one. This silently breaks the entire verification workflow in Step 8.
2. **Writable-layer state doesn't persist.** Named volumes (like `claude-config:/root/.claude`) *do* persist across `run --rm` sessions — so authentication tokens stored in that volume are retained. However, any state written to the container's own writable layer (such as `git config --global core.sshCommand` set by the entrypoint) is lost when the container is removed. This means SSH and Git configuration must be rebuilt from scratch every session.
3. **Redundant work every session.** The entrypoint script (SSH key copy, node_modules rebuild) runs from scratch every time you start a session, adding unnecessary startup delay.

The persistent model (`up -d` + `exec`) avoids all three issues. The container starts once, stays running, and every `exec` session shares the same writable layer, named volumes, and configuration state.

---

## Common Mistakes

### Don't override the `claude` command with a shell function

It's tempting to add something like this to your shell profile:

```bash
# DON'T DO THIS
claude() {
    docker compose exec claude-sandbox claude "$@"
}
```

This shadows the real `claude` binary. If you ever install Claude Code natively (or already have it installed), the shell function intercepts the command and you'll have no way to run native Claude Code without removing or bypassing the function. Scripts and tools that call `claude` will also get the Docker version unexpectedly.

### Use `claude_docker` instead

A distinct name eliminates ambiguity:

```bash
# DO THIS
claude_docker() {
    docker compose -f ~/claude_sandbox/docker-compose.yml up -d && \
    docker compose -f ~/claude_sandbox/docker-compose.yml exec claude-sandbox claude "$@"
}
```

Now `claude` always means native Claude Code, and `claude_docker` always means the sandboxed version. You always know which mode you're in.

### Docker Compose must be run from the sandbox directory

`docker compose` looks for `docker-compose.yml` in the current working directory. If you run `docker compose up -d` from your home directory or a project folder, it will either fail (no compose file found) or start a different compose project entirely.

Either `cd` into the sandbox directory first:

```bash
cd ~/claude_sandbox
docker compose up -d
```

Or use the `-f` flag to specify the compose file explicitly:

```bash
docker compose -f ~/claude_sandbox/docker-compose.yml up -d
```

The `claude_docker` function shown above already handles this for `exec` sessions, but you'll still need to be in the right directory (or use `-f`) when running `up`, `down`, `build`, or `ps`.

### Don't use `sudo` with Docker commands

On **macOS**, Docker Desktop runs as your user and `sudo` should never be necessary. If you find yourself needing `sudo` for Docker commands on a Mac, something is misconfigured — reinstall Docker Desktop.

On **Linux**, if Docker requires `sudo`, the correct fix is to add your user to the `docker` group:

```bash
sudo usermod -aG docker $USER
```

Then log out and back in.

On either platform, running `sudo docker compose ...` creates files owned by root, can introduce unexpected permission issues inside the container, and undermines the isolation model by running the Docker client as the superuser.

---

## Step 8: Verify the Sandbox With a Second Opinion (Don't Trust One LLM to Grade Its Own Work)

There's one more thing I did that I think is important.

Claude helped me design this sandbox. But if you ask an AI whether its own setup is secure, there's always a risk of subtle bias. Even if it's unintentional, you're still asking the same system to validate its own architecture.

So I brought in a second LLM — ChatGPT — and treated it as an independent reviewer. Not to redesign everything. Just to verify it.

Here's the exact process I used so anyone can repeat it.

**Important:** All verification commands below assume the container is already running via `docker compose up -d`. If it's not running, start it first.

### Step 8.1: Create a Canary File Outside the Sandbox

On my Mac, I created a file on my Desktop — somewhere that should absolutely be invisible to the container:

```bash
echo "THIS SHOULD NEVER BE VISIBLE" > ~/Desktop/CLAUDE_CANARY_DO_NOT_READ.txt
```

If the container could ever see this file, the sandbox would be broken.

### Step 8.2: Run a Full Filesystem Check Inside the Container

Then I ran this test inside the running sandbox container:

```bash
docker compose exec claude-sandbox bash -c '
  echo "=== SANDBOX ESCAPE TEST ==="
  echo ""
  echo "Mounted filesystems:"
  cat /proc/mounts
  echo ""
  echo "Searching for canary file:"
  find / -name "CLAUDE_CANARY_DO_NOT_READ.txt" 2>/dev/null
  echo ""
  echo "Direct access test (path traversal from workspace):"
  cat /workspace/../Desktop/CLAUDE_CANARY_DO_NOT_READ.txt 2>&1
'
```

**What this does in plain English:**
- Prints every mounted filesystem inside the container
- Searches the entire container for the canary file
- Attempts to read the canary by traversing up from `/workspace` — this should fail because `/workspace/..` resolves to the container's root filesystem, not your host machine. The host's `~/Desktop` simply doesn't exist inside the container.

If the sandbox were leaking access to my home directory, this test would expose it.

In my case, nothing was found. The path didn't even exist inside the container.

### Step 8.3: Verify the Container Is Not Running in Privileged Mode

Filesystem isolation only means something if the container isn't running with elevated kernel permissions. With the container still running, I ran this from my normal Mac terminal:

```bash
docker inspect claude-sandbox --format '{{json .HostConfig.Privileged}}'
```

It returned:

```
false
```

**What this means in plain English:**
- The container is not running in "god mode."
- It does not have elevated kernel-level access.
- It cannot bypass Docker's normal isolation boundaries.

If it had returned `true`, the sandbox would not be considered secure.

### Step 8.4: Confirm Exactly What Is Mounted

Still outside the container, I ran:

```bash
docker inspect claude-sandbox --format '{{json .HostConfig.Binds}}'
```

This prints the exact host paths mounted into the container.

In my case, the only host directories visible were:
- The `claude_sandbox` folder (as `/workspace`)
- My SSH directory (read-only)

Nothing else. No home directory. No Desktop. No Documents. No hidden mounts.

That's hard evidence — not an assumption.

### Why This Matters

This step wasn't about distrusting Claude. It was about avoiding single-system bias.

When one LLM helps you design something and also tells you it's secure, you're relying on a single reasoning engine. By bringing in a second model and forcing it to independently evaluate the setup, you reduce blind spots.

Instead of trusting a narrative, I verified behavior. That's the difference between "this seems safe" and "this has been tested."

### A Repeatable Verification Checklist

If you want to confirm your own sandbox is properly isolated, here's the full validation flow:

1. Start the container with `docker compose up -d`.
2. Create a canary file outside the sandbox.
3. Search for it from inside the container using `docker compose exec`.
4. Attempt to read it directly.
5. Inspect `/proc/mounts`.
6. Confirm `Privileged` is `false`.
7. Inspect `HostConfig.Binds`.
8. Confirm `/var/run/docker.sock` is not mounted.

If all of those checks pass, you have strong evidence that:
- The container cannot see your local filesystem.
- It cannot escalate privileges.
- It cannot mount arbitrary host paths.

That's not blind trust. That's layered verification.

---

## How This All Comes Together

When working with powerful AI tools, the safest mindset isn't paranoia — it's systems thinking.

- Limit scope.
- Verify boundaries.
- Confirm assumptions.
- Validate with independent tools.

By combining Docker isolation, Claude's internal permission system, and third-party verification with another LLM, you remove single-system bias and replace it with observable evidence. Here's why this setup lets me trust Claude Code with real work without worrying about what it might access:

### Two independent layers of protection

The sandbox works at two completely separate levels:

1. **Docker (the outer wall):** The container literally cannot see your filesystem. It's not that Claude is told not to look — the files *do not exist* from the container's perspective. This is enforced by the operating system's container isolation, the same technology that banks and cloud providers rely on to keep their systems separated.

2. **Claude Code permissions (the inner wall):** Even inside the container, Claude's own permission system blocks it from going above the workspace directory. If something somehow went wrong with the Docker mount, this second layer would still catch it.

### You control what goes in

Nothing appears in the sandbox unless you put it there. Want Claude to work on a project? Drop the folder into `claude_sandbox`. Want to keep something private? Just don't put it in that folder. It's that simple.

### SSH keys are read-only

Your GitHub SSH keys are mounted so that Git push/pull works, but with the `:ro` (read-only) flag. Claude can use them to authenticate, but it cannot modify, copy, or exfiltrate your private keys.

### Bash commands require approval

Even inside this locked-down environment, Claude has to ask before running shell commands. You see exactly what it wants to run and can say no. There are no surprise commands happening in the background.

### Resource limits prevent runaway processes

The 4GB memory and 2 CPU core limits mean that even if something goes haywire — an infinite loop, a massive build — it can't take down your whole machine. The container hits its ceiling and stops.

### The container stays ready between sessions

The persistent container model means you start the container once with `docker compose up -d`, and it stays running in the background. Each `docker compose exec` session connects to the same container, sharing the same filesystem state, authentication tokens, and SSH configuration. When you exit Claude, the container keeps running — ready for your next session instantly. Your workspace files persist on your host (they're mounted in), and Claude's configuration persists in the `claude-config` Docker volume.

To fully shut down the container, use `docker compose down`. To start it again later, use `docker compose up -d`.

### Third-party verified

The sandbox wasn't just designed — it was independently tested. A second LLM reviewed the architecture, and concrete tests (canary files, privilege checks, mount inspections) confirmed the isolation with observable evidence.

---

## The File Structure

When you're done, your `claude_sandbox` folder should look like this:

```
claude_sandbox/
  .claude/
    settings.json          # Claude Code permission rules
    settings.local.json    # Additional allowed tools
  .dockerignore            # Keeps secrets out of Docker image
  .env                     # Your API key (never committed to Git)
  .env.example             # Template for others to follow
  .gitignore               # Keeps .env out of Git
  Dockerfile               # Recipe for building the container
  docker-compose.yml       # Container configuration and volume mounts
  entrypoint.sh            # Startup script that runs inside the container
  your-project-folder/     # Any projects you want Claude to work on
```

---

## Final Thoughts

This entire setup took about an hour to put together and test. Once it's running, the day-to-day experience is almost identical to running Claude Code directly — you just launch it with a Docker command instead. The small inconvenience of running inside a container is, for me, completely worth the peace of mind.

Claude Code is a remarkable tool. But remarkable tools deserve thoughtful boundaries. This sandbox gives Claude everything it needs to do great work, and nothing it doesn't.

---

## Companion Resources

This repo includes two prompt templates to make the process easier to repeat and verify:

- [**sandbox-setup-prompt.md**](sandbox-setup-prompt.md) — A copy-paste prompt for Claude that guides you through building the entire sandbox interactively. Optimized to minimize token usage on your account.
- [**sandbox-verification-prompt.md**](sandbox-verification-prompt.md) — A copy-paste prompt for a non-Claude LLM (ChatGPT, Gemini, etc.) that independently reviews your configuration files and diagnostic test results to verify the sandbox is properly isolated. Because you shouldn't trust one AI to grade its own work.
