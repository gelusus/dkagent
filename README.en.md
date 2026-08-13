# dkagent

> 📖 中文文档: [README.md](README.md)

> One bash command turns any directory into an isolated AI Agent runtime.

A Docker-based sandbox for AI Agent CLIs. Launch a container in one line with Claude Code, Gemini CLI, Codex, Pi, and OpenCode pre-installed. Supports **per-directory read-only mounts**, **multiple image profiles**, tmux auto-reconnect and multi-machine handoff sync, and uses 🟢🟡🔴 colors so you can see at a glance how much power you've handed the Agent each run.

---

## Core features

**1. Per-directory read/write control, one command away**
```bash
# Original project read-only, copy directory writable
dkagent -m ./original -r -m ./workspace/my-copy claude
```
Read-only dirs are pinned at the kernel level via Docker bind mounts — the "reference project A, edit project B" scenario works in one line.

**2. Unified entry point for multiple Agents**: Claude / Gemini / Codex / Pi / OpenCode are all bundled into one image. The persistent Home volume keeps every Agent's login credentials and configs — seamless switching.

**3. Kali toolchain out of the box**: the default image is based on Kali Linux (nmap, ripgrep, Playwright, full toolkit). Need lighter? Switch to the `slim` profile (Debian slim, roughly two-thirds smaller).

**4. Defense in depth**: Agents' own containers and safety mechanisms have had their share of vulnerabilities. dkagent adds **another layer of Docker isolation on the outside** — even if an Agent's internal defenses are bypassed, it still cannot touch host files.

---

## Prerequisites

| Dependency | Purpose | Install |
| :--- | :--- | :--- |
| **Docker** | required | Linux: `apt install docker.io` / macOS, Windows: Docker Desktop |
| **git** | clone this repo | `apt install git` / `brew install git` |
| **bash 4+** | script runtime | macOS ships bash 3.2 — needs `brew install bash` |
| **ssh client** | `dkagent sync` & remote access | Linux: `apt install openssh-client` / macOS: built-in |
| **rsync** | only `dkagent sync` dir sync (volume sync runs inside a container) | `apt install rsync` / `brew install rsync` |
| **tmux** | optional; enables auto-reconnect | `apt install tmux` / `brew install tmux` |

Volume sync via `dkagent sync` additionally needs the helper image `dkagent-sync` (~14 MB): `docker build -t dkagent-sync -f dockerfiles/Dockerfile.sync .`

---

## Install & quick start

We recommend starting with the **slim image** (~2-3 min build) to get things running, then switching to Kali as needed.

```bash
# 1. Install the CLI (auto-creates ~/.config/dkagent/ and copies the .env template)
chmod +x install.sh && ./install.sh
# 2. Fill in your API keys (never commit to git)
vi ~/.config/dkagent/.env
# 3. Build the slim image
docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim .
# 4. From any project directory, launch in one line
cd ~/my-project
dkagent -p slim claude --dangerously-skip-permissions
```

> **About `--dangerously-skip-permissions`**: the real security boundary is the container, not the Agent's permission prompts — the container already isolates, so you can safely hand this "fully automatic" flag to the Agent.

**Want the Kali image?** (~10 GB, 15-30 min first build): run `docker compose build`, then just `dkagent claude` (kali is the default profile).

**Platform support**: Linux / WSL2 ✅ native; macOS ⚠️ needs `brew install bash` first; Windows native ❌ not supported — use WSL2.

---

## Environment injection (.env)

dkagent auto-discovers a `.env` file and injects each `KEY=value` line as an environment variable into the container (visible to Agents and scripts). Search order: path from `$DKAGENT_ENV` → `~/.config/dkagent/.env` → `.env` next to the script.

```bash
# Before entering, copy your host's env file to .env — dkagent injects it automatically
cp ~/projects/secrets.env ~/.config/dkagent/.env
dkagent claude        # every KEY in .env is readable inside the container
```

Host-exported `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` / `OPENAI_API_KEY` / `OPENROUTER_API_KEY` override same-named `.env` entries; blank lines and `#` comments are skipped.

---

## Image profiles (switching environments)

All profiles **share the same persistent Home volume** — switching images keeps your zsh config, command history, and Agent login credentials.

| Profile | Base image | Use case |
| :--- | :--- | :--- |
| **`kali`** (default) | Kali Linux | security research, pentesting, full toolchain |
| **`slim`** | Debian slim | everyday coding, fast startup |

```bash
dkagent claude                          # default: kali
dkagent -p slim claude                  # switch to slim (build it first: docker build -t dkagent-slim ...)
dkagent --image my-custom-agent claude  # any image directly (escape hatch)
```

**Custom profiles**: append a line like `node=my-node-agent` to `~/.config/dkagent/profiles`, then `dkagent -p node claude`.

> **⚠️ Custom image constraint**: to reuse the persistent Home volume across images, the image must create a `kali` user with home at `/home/kali` (see `dockerfiles/Dockerfile.slim`), otherwise run with `-e` (ephemeral Home).

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

## Config migration (reusing host login state)

Already logged into an Agent on the host? Copy the login state into the persistent volume once and skip re-login inside the container. Core idea: **login state dir → `docker run` with the volume mounted** (run on the host).

| Agent | Config dir | Key credential file | Notes |
| :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/` + `~/.claude.json` | `~/.claude/.credentials.json` (0600) | also copy the `~/.claude.json` file separately |
| Codex | `~/.codex/` | `~/.codex/auth.json` | if missing, credentials live in keychain — not migratable |
| OpenCode | `~/.config/opencode/` + `~/.local/share/opencode/` | `~/.local/share/opencode/auth.json` | two dirs, copy both |
| Pi | `~/.pi/agent/` | `~/.pi/agent/auth.json` | |

```bash
# Generic template: copy host <src> into the persistent volume (substitute paths from the table)
docker run --rm -v agent_docker_kali-home:/home/kali -v "$HOME/<src>:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/<dst> && cp -a /src/. /home/kali/<dst>/"
```

> [!WARNING]
> **Notes**: re-login to Gemini inside the container instead (its credentials are encrypted and bound to hostname + username, likely unreadable after migration); the commands overwrite same-named files inside the container — back up first; macOS keychain credentials can't be migrated as files; if credentials become unreadable after migration it's usually an ownership issue — fix with `sudo chown -R kali:kali ~/.<dir>` inside the container.

---

## Remote sessions & reconnect

When running Agents over SSH, a dropped terminal kills the session. dkagent **wraps everything in tmux by default** (when tmux is installed on the host) — the session lives in the host's tmux, so the Agent keeps running when SSH drops:

```bash
ssh user@host
cd ~/project-a
dkagent claude                  # creates tmux session dkagent-project-a; the Agent runs inside
# SSH dropped; after reconnecting:
tmux attach -t dkagent-project-a   # resume the session (running dkagent again creates _2, not attach)
```

Each run creates a fresh independent session (auto-suffixed `_2`, `_3` on name collisions); containers are named `dkagent-<dirname>` for easy `docker ps` identification. Customize with `--tmux-name NAME`, disable with `--no-tmux`; `DKAGENT_NO_CONTAINER_NAME=1` falls back to Docker random names.

---

## Out and about: reaching your home computer remotely

Your home computer has no public IP, so SSH from outside won't connect — use **NAT traversal** (intranet penetration / reverse tunnel). Two choices:

**Option 1: self-hosted tunnel (FRP)**: run `frps` on a cheap server with a public IP; your home computer runs `frpc` mapping SSH 22 to a server port; connect straight to the server from anywhere: `ssh -p 6000 user@server.example.com`. Similar: ngrok, Tailscale / ZeroTier mesh networks.

**Option 2: third-party port-mapping service (NetEase UU Remote)**: free, zero servers. Install the [UU Remote](https://uuyc.163.com/) client on both the home and outside computers and sign in with the same account; on the home computer, create a mapping under "Devices → More → Port mapping": local access port (e.g. 13022) → target `127.0.0.1:22`, keep the rule enabled; connect to your local port from outside (TCP): `ssh -p 13022 user@127.0.0.1`. Similar: Oray Peanut Hull (花生壳), etc.

**Phone**: just install the [UU Remote](https://uuyc.163.com/) app to remote-control the home computer (mobile doesn't support port mapping — no SSH tunnel needed); for pure command-line coding, use Termux + `pkg install openssh` with Option 1.

> **Safety note**: turn temporary mappings off when done; use SSH keys, never passwords.

---

## Multi-machine handoff sync

Continue work across machines: `dkagent sync` syncs the persistent volume (tool config / command history / Agent credentials) and project dirs to the peer. **Fully manual — `dkagent claude` and friends will never auto-sync.**

**Prep** (once on each side): install Docker + dkagent → set up passwordless SSH → build the `dkagent-sync` image (see [Prerequisites](#prerequisites)) → edit `~/.config/dkagent/peers`:
```
# one line per: alias=ssh://user@host:port (use the mapped address with a tunnel, e.g. ssh://user@127.0.0.1:13022)
laptop=ssh://user@laptop.local:22
```
> This file contains SSH URLs — `chmod 600 ~/.config/dkagent/peers` is recommended.

**Basic usage**:
```bash
dkagent sync list                            # list peers + current dir mapping
cd ~/my-project
dkagent sync push laptop --remote-path ~/my-project   # first time (--remote-path required, stored as mapping)
dkagent sync push laptop                     # later runs reuse the stored mapping
dkagent sync pull laptop                     # reverse direction (peer → local)
dkagent sync push laptop --dry-run           # preview only, no changes
dkagent sync push laptop -- --exclude=.git/ --exclude=.env   # pass through rsync args
```

**Default behavior**: syncs both the persistent volume and the current project dir by default; the volume uses **container-nested** rsync over ssh, dirs use **direct** rsync (faster). Default flags: `-az --delete --numeric-ids --partial --partial-dir=.rsync-partial`, ssh keepalive, and 10 built-in retries (30 s apart).

> [!CAUTION]
> **`--delete` is on by default**: files only present on the remote are deleted to keep a mirror. Strongly recommend `--dry-run` before the first sync to see what would be deleted — watch out for `.env` API keys and `.git/` history.

**Options at a glance**: `--remote-path PATH` / `--no-volume` / `--no-project` / `--dry-run` / `-y` / `--retries N` / `-- RSYNC_ARGS` (see `dkagent sync --help`).

**Config files**: `~/.config/dkagent/peers` (peer list), `~/.config/dkagent/sync-mapping` (path mapping; auto-managed by the script, but editable by hand).

---

## Command-line reference

```bash
dkagent [options] [agent] [extra args...]    # agent: claude/gemini/pi/codex/opencode; empty → interactive zsh
```

```bash
dkagent                                # interactive Kali shell (mounts cwd)
dkagent claude                         # wake up Claude Code inside the container
dkagent -m ./a -r -m ./b gemini        # multi-dir mounts, a read-only, b writable
dkagent -p slim claude                 # switch profile
dkagent --docker-socket claude         # docker inside the container (⚠️ equals host root)
dkagent --dry-run                      # print the docker run command, don't execute
```

| Option | Description |
| :--- | :--- |
| `-p, --profile NAME` | image profile (default `kali`) |
| `--image NAME` | any Docker image directly (highest priority) |
| `-e, --ephemeral` | ephemeral Home, no trace on exit |
| `-m, --mount DIR` / `-r` | mount a dir (repeatable); a trailing `-r` makes it read-only |
| `--no-mount` | mount nothing from the host (safest) |
| `--docker-socket` | mount host docker.sock (⚠️ **highest risk, equals host root**) |
| `--port HOST:CONTAINER` | port mapping (repeatable, same as `docker run -p`), e.g. `8080:8080`, `127.0.0.1:3000:3000`, `9000:9000/udp` |
| `--no-tmux` / `--tmux-name NAME` | disable / customize the tmux wrapper |
| `--env FILE` | specify a `.env` file |
| `--lang zh\|en` | UI language (auto-detected from `$LANG`/`$LC_ALL`; `export DKAGENT_LANG=en` persists) |
| `--dry-run` | print the `docker run` command only, don't launch |
| `-h, --help` | show help |

**Image priority**: `--image` > `--profile` > env `DKAGENT_PROFILE` > default `kali`.

---

## Alternative: Docker Compose

Prefer not to use the CLI? `docker compose run --rm` works too — all three modes share the same persistent Home volume (fully interchangeable with the CLI): `agent-shell` (Home only, 🟢) / `agent-isolated` (no mounts, ephemeral, 🟢) / `agent-sandboxed` (Home + `./workspace` mount, 🟡). Switch images: `DKAGENT_IMAGE=dkagent-slim docker compose run --rm agent-shell`.

---

## Desktop Agent connections

Desktop Agents (e.g. Zhipu's ZCode) can use this environment too. ZCode can connect **directly to a running container** (no exposed ports needed): the container name is `dkagent-<project dirname>` (e.g. `dkagent-my-project`), and the user inside is `kali`. For Agents that only support SSH, use `--port` at startup to map a container service port to the host and connect directly (e.g. `dkagent --port 2222:22 claude`, given a service is listening on that port inside) — no tunnel needed.

---

## Project structure

```
├── dkagent                  # core bash CLI (mounts, risk tiers, sync subcommand)
├── Dockerfile               # default profile (kali)
├── dockerfiles/
│   ├── Dockerfile.slim      # slim profile (minimal Debian)
│   └── Dockerfile.sync      # dkagent-sync image (rsync + ssh, for cross-machine sync)
├── docker-compose.yaml      # alternative compose run modes
├── install.sh               # one-click install/uninstall
├── .env.example             # API keys config template
└── workspace/               # sandbox working dir
```

---

## Roadmap

- [x] Multi-dir mounts + per-directory read-only | [x] 8-tier risk visualization | [x] Multiple image profiles
- [x] Docker inside the container (`--docker-socket`) | [x] Bilingual UI (auto-detected)
- [x] Containers named after the cwd (`_2` `_3` suffix) | [x] Multi-machine handoff sync (`dkagent sync push/pull`, fully manual)
- [ ] **Network isolation tiers** (`--net off` / `--net strict`)
- [x] **Container port mapping** (`--port`; expose any container port to the host for external / desktop Agents)

---

## License

[MIT](LICENSE)
