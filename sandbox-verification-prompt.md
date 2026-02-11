# Sandbox Verification Prompt (For a Non-Claude LLM)

Paste this into ChatGPT, Gemini, or any LLM that was NOT involved in building the sandbox. The goal is to get an independent, unbiased assessment of whether the Docker container properly isolates Claude Code's file access.

---

I used Claude Code (Anthropic's AI coding assistant) to help me build a Docker sandbox that restricts Claude's file access to a single folder on my computer. Since Claude designed the sandbox, I don't want to rely on Claude alone to tell me it's secure. I want you to independently verify it.

I'm going to give you my configuration files and the output of several diagnostic commands. For each one, tell me:
- What it shows
- Whether it's safe or concerning
- Any gaps or risks I should be aware of

Use plain language. Be direct. If something is wrong, say so clearly.

## My configuration files

### docker-compose.yml

```yaml
[PASTE YOUR docker-compose.yml HERE]
```

### Dockerfile

```dockerfile
[PASTE YOUR Dockerfile HERE]
```

### .claude/settings.json

```json
[PASTE YOUR .claude/settings.json HERE]
```

### .claude/settings.local.json

```json
[PASTE YOUR .claude/settings.local.json HERE]
```

## Diagnostic commands and their output

Before pasting the outputs below, run these commands on your machine and paste the results in place of each `[PASTE OUTPUT]` placeholder.

**Important:** All test commands that run inside the container use `docker compose exec`, which executes commands in the already-running service container (started with `docker compose up -d`). Make sure the container is running before you begin. If it's not, start it with:

```bash
docker compose up -d
```

### Test 1: Canary file search

I created a test file outside the sandbox that the container should never be able to see:

```bash
echo "THIS SHOULD NEVER BE VISIBLE" > ~/Desktop/CLAUDE_CANARY_DO_NOT_READ.txt
```

Then I searched for it from inside the running container:

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

**Output:**

```
[PASTE OUTPUT]
```

### Test 2: Privileged mode check

With the container running (via `docker compose up -d`):

```bash
docker inspect claude-sandbox --format '{{json .HostConfig.Privileged}}'
```

**Output:**

```
[PASTE OUTPUT]
```

### Test 3: Mounted host paths

```bash
docker inspect claude-sandbox --format '{{json .HostConfig.Binds}}'
```

**Output:**

```
[PASTE OUTPUT]
```

### Test 4: Docker socket access

```bash
docker inspect claude-sandbox --format '{{json .HostConfig.Binds}}' | grep -c "docker.sock"
```

**Output:**

```
[PASTE OUTPUT]
```

## What I need from you

Based on everything above:

1. **Is the container properly isolated?** Can it access files outside the sandbox folder?
2. **Are there any privilege escalation risks?** Could the container break out of its boundaries?
3. **Are the mounted volumes appropriate?** Is anything mounted that shouldn't be?
4. **Is the Docker socket exposed?** Could the container spin up other containers or access the host Docker daemon?
5. **Are Claude Code's internal permission rules sound?** Do the deny/allow rules in settings.json effectively block access outside the workspace?
6. **Are there any other risks or gaps I haven't tested for?** Anything you'd add to this verification?

Give me a clear pass/fail for each check, then an overall assessment of whether this sandbox is trustworthy for running an AI coding assistant with restricted file access.
