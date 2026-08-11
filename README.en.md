# dkagent

> 📖 中文文档: [README.md](README.md)

> One bash command turns any directory into an isolated AI Agent runtime.

A Docker-based sandbox for AI Agent CLIs. Launch a container in one line with Claude Code, Gemini CLI, Codex, Pi, and OpenCode pre-installed. Supports **per-directory read-only mounts**, **multiple image profiles**, and uses 🟢🟡🔴 colors so you can see at a glance how much power you've handed the Agent each run.

---

## Design philosophy: simple, with safety delegated to Docker

dkagent is essentially **a ~750-line bash script** with no self-rolled sandbox logic. It does exactly one thing: **orchestrate Docker's existing isolation into a usable command line**.

- **Safety = Docker itself**: Container isolation relies on Docker's native namespace / cgroup / bind-mount — kernel mechanisms proven in production for a decade. dkagent doesn't reinvent them; it just calls them.
- **Risk level = what you mount**: Every 🟢🟡🔴 tier maps directly to the scope of mounted volumes, with no hidden logic. `--dry-run` shows you the full `docker run` command before execution — what you see is what you get.
- **Auditable**: The whole tool is one script. No background process, no daemon, no runtime injection. Reading the source once is enough to fully understand what it does to your system.

This is also why dkagent can safely hand `--dangerously-skip-permissions` to the Agent — the real security boundary is the container, not the Agent's own permission prompts.

---

## Why dkagent

**1. Per-directory read/write control, one command away**
Mount multiple directories directly on the command line, each independently read-only or writable — no config files needed:
```bash
# Original project read-only, copy directory writable
dkagent -m ./original -r -m ./workspace/my-copy claude
```
The "reference project A's code, edit project B" scenario works in one line — read-only dirs are pinned at the kernel level via Docker bind mounts and cannot be written to.

**2. Unified entry point for multiple Agents — switch between five in one environment**
No need to configure environments and install dependencies separately for each Agent. dkagent bundles Claude / Gemini / Codex / Pi / OpenCode into one image, and the persistent Home volume keeps all Agent login credentials and configs — seamless switching.

**3. Kali toolchain ready — out-of-the-box for security research**
The default image is based on Kali Linux, with Playwright browser, nmap, fd, ripgrep, oh-my-zsh and a full toolkit built in. Want something lighter? Switch to the `slim` profile (based on Debian slim, roughly two-thirds smaller).

---

## Quick start

We recommend starting with the **slim image** (based on Debian slim — small, fast to build, ~2-3 min), then switching to Kali as needed.

```bash
# 1. Install the CLI tool (auto-creates ~/.config/dkagent/ and copies the .env template)
chmod +x install.sh && ./install.sh

# 2. Fill in your API keys (edit this file after first install; never commit to git)
vi ~/.config/dkagent/.env

# 3. Build the slim image (fast, ~2-3 min)
docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim .

# 4. From any directory, launch in one line
cd ~/my-project
dkagent -p slim claude --dangerously-skip-permissions
```

> **About `--dangerously-skip-permissions`**: since dkagent already isolates via a container, you can safely hand this "fully automatic" flag to the Agent, letting it execute commands inside the container without confirmation — this is the core payoff of containerization.

### Want the Kali image? (optional)

The Kali image ships the full security-research toolchain (nmap, metasploit, Playwright, etc.), but it's **about 10 GB and the first build takes 15-30 minutes** (depending on network):

```bash
docker compose build              # build the kali image (my-kali-agent)
dkagent claude                    # uses the kali profile by default
```

> **macOS users**: this script uses bash 4+ associative arrays. macOS ships bash 3.2 (2007); install a newer bash first with `brew install bash`. See [Platform support](#platform-support) below.

---

## Platform support

| Platform | Status | Notes |
| :--- | :--- | :--- |
| **Linux** | ✅ Native | Verified |
| **WSL2** | ✅ Native | Verified. Windows users should use WSL2 + Docker Desktop |
| **macOS** | ⚠️ Theoretically works, untested | The script uses bash 4+ associative arrays; macOS system bash is 3.2, needs `brew install bash`. Feedback from macOS users welcome |
| **Windows native** | ❌ Not supported | No bash/sudo; use WSL2 |

---

## Image profiles (switching environments)

dkagent switches run environments via profiles. All profiles **share the same persistent Home volume**, so when you switch images your zsh config, command history, and Agent login credentials are all preserved.

| Profile | Base image | Size | Use case |
| :--- | :--- | :--- | :--- |
| **`kali`** (default) | Kali Linux | Large | Security research, pentesting, needs the full toolchain |
| **`slim`** | Debian slim | Small | Daily coding, CI/CD, prioritizing startup speed |

```bash
# Default uses kali
dkagent claude

# Switch to the slim image
docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim .   # build once first
dkagent -p slim claude

# Specify any custom image directly (escape hatch)
dkagent --image my-custom-agent claude
```

**Adding a custom profile**: append a line to `~/.config/dkagent/profiles`:
```
node=my-node-agent
rust=my-rust-agent
```
Then `dkagent -p node claude` works.

> **⚠️ Custom image constraint**: for the persistent Home volume to be reusable across images, your custom image's Dockerfile must create a `kali` user and use `/home/kali` as the home path (see `dockerfiles/Dockerfile.slim`). Otherwise run with `-e` (ephemeral Home) mode.

---

## Config migration (reusing host login state)

If you've already logged into an Agent on the host, you can copy the login state into the dkagent persistent volume once, avoiding a fresh login inside the container. Run the following commands on the **host**.

### Agent config path cheatsheet

| Agent | Config dir | Key credential file | Notes |
| :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/` + `~/.claude.json` | `~/.claude/.credentials.json` (0600) | Must also copy the `~/.claude.json` file separately |
| Codex | `~/.codex/` | `~/.codex/auth.json` | If missing, it uses the keychain and can't be migrated |
| OpenCode | `~/.config/opencode/` + `~/.local/share/opencode/` | `~/.local/share/opencode/auth.json` | Config and credentials are two dirs; copy both |
| Pi | `~/.pi/agent/` | `~/.pi/agent/auth.json` | |

### Claude Code example

```bash
# 1. Copy the ~/.claude/ config dir (contains login credentials)
docker run --rm \
  -v agent_docker_kali-home:/home/kali \
  -v "$HOME/.claude:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/.claude && cp -a /src/. /home/kali/.claude/"

# 2. Copy the ~/.claude.json user config file (note: it's a file, not a dir)
docker run --rm \
  -v agent_docker_kali-home:/home/kali \
  -v "$HOME/.claude.json:/src:ro" \
  alpine sh -c "cp -a /src /home/kali/.claude.json"
```

### Codex example

```bash
# Precheck: if ~/.codex/auth.json is missing, credentials are in the keychain and can't be migrated via files
ls ~/.codex/auth.json

docker run --rm \
  -v agent_docker_kali-home:/home/kali \
  -v "$HOME/.codex:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/.codex && cp -a /src/. /home/kali/.codex/"
```

> [!WARNING]
> **Migration caveats**
> - **Gemini: re-login inside the container is recommended**: it stores credentials in the system keyring by default, with the encryption key bound to hostname + username. Migration into a container usually fails to decrypt.
> - **Overwrite risk**: the commands above overwrite same-named files in the container. Back up first if you already have configs there.
> - **Cross-platform**: keychain credentials from macOS cannot be migrated via files; re-login inside the container.
> - **Ownership**: if credentials can't be read after migration, it's usually an ownership mismatch — fix inside the container with `sudo chown -R kali:kali ~/.<dir>`.

---

## Safety model: see how much power you gave the Agent at a glance

AI Agents hold powerful filesystem permissions during a task. To prevent an Agent — under a malicious prompt or a misjudgment — from deleting or wiping host files (the `rm -rf` risk), dkagent combines **mount mode × Home persistence** into clear risk tiers, printed on every run.

```
  Safety ▲
        │
   🟢 Isolated      --no-mount + -e          fully isolated, ephemeral
        │
   🟢 Low risk      --no-mount               host files isolated, persistent home has config-tamper risk
   🟢 Low risk      all read-only + -e       read-only, leaves no trace on exit
        │
   🟡 Med-low risk  all read-only            read-only, but persistent home has config-tamper risk
   🟡 Medium risk   has writable + -e        can act on mounts, leaves no trace on exit
        │
   🔴 High risk     has writable             can act on mounts + persistent home can plant backdoors
        │
   ☠️ Escape level  --docker-socket          docker.sock = host root, overrides all tiers above
        │
        └────────────────────────────────────────────────▶ convenience
```

### Full run-mode safety comparison

| Command | Home | Mount mode | Risk | Use case |
| :--- | :--- | :--- | :--- | :--- |
| **`dkagent --no-mount -e`** | 🧊 ephemeral | 🟢 none | **none (🟢)** | pure sandbox testing |
| **`dkagent --no-mount`** | 🏠 persistent vol | 🟢 none | **low (🟢)** | configuring the in-container env |
| **`dkagent -e -m ./dir -r ...`** | 🧊 ephemeral | 🟢 all read-only | **low (🟢)** | read-only reference across projects |
| **`dkagent -m ./dir -r ...`** | 🏠 persistent vol | 🟢 all read-only | **med-low (🟡)** | read-only ref + persistent config |
| **`dkagent -e [agent]`** | 🧊 ephemeral | 🔴 has writable | **medium (🟡)** | throwaway coding task |
| **`dkagent -e -m ... [agent]`** | 🧊 ephemeral | 🔴 has writable | **medium (🟡)** | throwaway sandbox coding |
| **`dkagent [agent]`** | 🏠 persistent vol | 🔴 has writable | **high (🔴)** | daily efficient coding (trust the Agent) |
| **`dkagent -m ... [agent]`** | 🏠 persistent vol | 🔴 has writable | **high (🔴)** | multi-dir coding tasks |
| **`dkagent --docker-socket [agent]`** | 🏠/🧊 | 🐋 docker.sock | **escape (☠️)** | needs docker commands inside the container |

> [!CAUTION]
> **About persistent Home volume safety (🏠)**:
> The persistent Home volume keeps your Oh-My-Zsh config, command history, and Agent session state. If an Agent is taken over by a malicious external actor, it could theoretically plant a backdoor via your persisted `.zshrc`. If you have extreme safety requirements, add the `-e` (ephemeral) flag.

> [!CAUTION]
> **About `--docker-socket` safety (☠️)**:
> `--docker-socket` mounts the host's `/var/run/docker.sock` into the container. **This is equivalent to handing host root to the container** — inside, you can fully control host Docker (including `docker run -v /:/host` to read/write the host root filesystem). Use it only when you fully trust the Agent and genuinely need docker commands inside the container.

---

## UI language

dkagent's interface prompts auto-detect language and default to **Chinese**, with full English support:

- **Auto-detect**: reads `$LANG` / `$LC_ALL` — `zh_*` → Chinese, anything else → English
- **Manual override**: `dkagent --lang en` (or `zh`)
- **Persistent override**: `export DKAGENT_LANG=en`

Priority: `--lang` flag > `DKAGENT_LANG` env var > `$LANG`/`$LC_ALL` auto-detect > default (Chinese).

```bash
dkagent --lang en --help          # English help
LANG=en_US.UTF-8 dkagent --help   # auto-detected English
```

---

## Remote sessions & reconnect after disconnect

When you SSH into a physical machine to run an Agent, you'll often hit the **running session is lost after the terminal disconnects** problem — network blips, closing your laptop, switching networks all drop SSH.

dkagent **wraps with tmux by default** (when the host has tmux installed) to solve this at the root:

- **Running** `dkagent claude`: launches the Agent inside a tmux session named `dkagent-<cwd basename>`. **Every run creates a fresh, independent session** (duplicate names get a `_2`, `_3`… suffix — no cross-talk)
- **SSH drops**: the tmux server runs on the physical machine and is unaffected — the Agent process keeps running
- **Manual reconnect**: `tmux attach -t dkagent-<dirname>` resumes the original session (note: re-running `dkagent` starts a NEW session, it does not attach)

```bash
# First SSH connection
ssh user@host
cd ~/project-a
dkagent claude            # creates tmux session dkagent-project-a, Agent runs inside

# SSH dropped, reconnect
ssh user@host
tmux attach -t dkagent-project-a   # manually resume the original session, Agent still running
# (running `dkagent claude` again here would create a NEW session dkagent-project-a_2)
```

The session name defaults to the working directory (different projects are naturally isolated), and can be customized with `--tmux-name NAME` or the `DKAGENT_TMUX_SESSION` env var.

**Disabling tmux wrapping**:

```bash
dkagent --no-tmux claude            # disable for this run, run docker directly
```

> 💡 **Design trade-off**: tmux wrapping happens at the host layer (not inside the container). The container remains `--rm` one-shot — no long-running service processes, zero extra resource overhead. The session is automatically destroyed when the Agent exits normally.

---

## Command-line usage

### Basic structure

```bash
dkagent [options] [agent] [extra args...]
```

### Common operations

```bash
# Enter an interactive Kali shell (mounts the current dir)
dkagent

# Launch Claude Code inside the container directly
dkagent claude

# Use a temporary Home volume (ephemeral)
dkagent -e claude

# Mount multiple directories (original project + shared libs)
dkagent -m ./my-project -m ./shared-libs claude

# Original project read-only, copy directory writable
dkagent -m ./my-project -r -m ./workspace/my-copy gemini

# Switch to the slim image
dkagent -p slim claude

# Pure mode, mount no host directories
dkagent --no-mount

# Docker commands usable inside the container (⚠️ highest risk, equals host root)
dkagent --docker-socket claude
```

### Options

| Option | Description |
| :--- | :--- |
| `-p, --profile NAME` | 🎚️ Select image profile (default `kali`; `slim` or custom available) |
| `--image NAME` | 🐳 Specify any Docker image name (overrides `--profile`) |
| `-e, --ephemeral` | 🧊 Use a temporary Home dir, leaves no trace on exit |
| `-m, --mount DIR` | 📁 Mount a dir to `/home/kali/workspace/<basename>`; repeatable or space-separated |
| `-r, --readonly` | 🔒 Place right after `-m` to mount that directory read-only |
| `--no-mount` | 🟢 Mount no host directories (safest) |
| `--docker-socket` | 🐋 Mount host docker.sock so the container can run docker (⚠️ **highest risk, equals host root**) |
| `--no-tmux` | 🔌 Disable host tmux wrapping (SSH disconnect loses the process) |
| `--tmux-name NAME` | 🔌 Custom tmux session name (default `dkagent-<cwd basename>`; duplicates get `_2`/`_3` suffix) |
| `--env FILE` | Manually specify the `.env` config file |
| `--lang zh\|en` | 🌐 Set the UI language (default: auto-detect from `$LANG`/`$LC_ALL`) |
| `--dry-run` | 🔍 Print the `docker run` command without actually starting |
| `-h, --help` | Show help |

**Image priority**: `--image` > `--profile` > env var `DKAGENT_PROFILE` > default `kali`

**Agent names**: `claude` / `gemini` / `pi` / `codex` / `opencode`; empty enters an interactive zsh.

---

## Alternative: Docker Compose

If you'd rather not use the `dkagent` CLI, you can launch directly via `docker compose`. All three modes share the same persistent Home volume (fully interoperable with the CLI).

```bash
# 🏠 Debug/shell mode — persistent Home only, no work dir mounted (🟢)
docker compose run --rm agent-shell

# 🧊 Pure/isolated mode — no mounts at all, ephemeral (🟢)
docker compose run --rm agent-isolated

# 📂 Sandbox mode — persistent Home + mount ./workspace (🟡)
docker compose run --rm agent-sandboxed

# Switch image (reuses the same Home volume)
DKAGENT_IMAGE=dkagent-slim docker compose run --rm agent-shell
```

---

## Directory structure

```
.
├── dkagent                  # core bash CLI (arg parsing, mounts, risk printing)
├── Dockerfile               # default profile (kali) build config
├── dockerfiles/
│   └── Dockerfile.slim      # slim profile build config (minimal Debian)
├── docker-compose.yaml      # three alternative compose run modes
├── install.sh               # one-shot install/uninstall script
├── .env.example             # API keys config template
└── workspace/               # work dir for sandbox mode (auto-created by Docker on first compose run)
```

---

## Roadmap

- [x] Multi-directory mount + per-directory read-only control
- [x] 8-tier risk visualization
- [x] Multiple image profiles
- [x] Run Docker inside the container (`--docker-socket`)
- [x] Bilingual UI (Chinese / English) with auto-detection
- [ ] **Network isolation tiers** (`--net off` / `--net strict` — simple and fit for multi-agent scenarios)

---

## License

[MIT](LICENSE)
