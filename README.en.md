# dkagent

> 📖 中文文档: [README.md](README.md)

> One bash command turns any directory into an isolated AI Agent runtime.

A Docker-based sandbox for AI Agent CLIs. Launch a container in one line with Claude Code, Antigravity (`agy`), Codex, Pi, OpenCode, and DeepSeek Harness (`dsh`) pre-installed. Supports **per-directory read-only mounts**, **multiple image profiles**, tmux auto-reconnect and multi-machine handoff sync, and uses 🟢🟡🔴 colors so you can see at a glance how much power you've handed the Agent each run.

---

## Core features

**1. Per-directory read/write control, one command away**
```bash
# Original project read-only, copy directory writable
dkagent -m ./original -r -m ./workspace/my-copy claude
```
Read-only dirs are pinned at the kernel level via Docker bind mounts — the "reference project A, edit project B" scenario works in one line.

**2. Unified entry point for multiple Agents**: Claude / Antigravity (`agy`) / Codex / Pi / OpenCode / DeepSeek Harness (`dsh`) are all bundled into one image. The persistent Home volume keeps every Agent's login credentials and configs — seamless switching.

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

dkagent auto-discovers a `.env` file and injects each `KEY=value` line as an environment variable into the container (visible to Agents and scripts). Search order: path from `$DKAGENT_ENV` → `~/.config/dkagent/.env`.

```bash
# Before entering, copy your host's env file to .env — dkagent injects it automatically
cp ~/projects/secrets.env ~/.config/dkagent/.env
dkagent claude        # every KEY in .env is readable inside the container
```

Host-exported `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` / `OPENAI_API_KEY` / `OPENROUTER_API_KEY` / `DEEPSEEK_API_KEY` override same-named `.env` entries; blank lines and `#` comments are skipped.

**Secure transport**: env vars are passed via a **temporary `--env-file`** (mode 0600, deleted after the run) — they never appear in the host process list (`ps`) or command-line echoes; in `--dry-run` output env vars are masked as `KEY=***` by default, set `DKAGENT_DRY_RUN_SHOW_SECRETS=1` to reveal them. The legacy fallback that read a `.env` next to the script has been removed (a planted `.env` in the repo must no longer be able to hijack later runs). Note: Agent commands start with `zsh -f`, so **variables from zsh startup files (`.zshenv`, etc.) are not passed to Agents** — use `.env` for injection.

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
> The persistent Home volume keeps your Oh-My-Zsh config, command history, and Agent session state. If an Agent is taken over by a malicious external actor, it could theoretically plant a backdoor via the persistent Home's zsh startup files (`.zshenv` / `.zprofile`). To counter this, **Agent commands always start with `zsh -f` (no startup files are read)** — but the `dkagent` interactive shell mode still sources `.zshrc` (keeping user config, a known trade-off), so don't run untrusted content in interactive mode. If you have extreme safety requirements, add the `-e` (ephemeral) flag.

> [!CAUTION]
> **About `--docker-socket` safety (☠️)**:
> `--docker-socket` mounts the host's `/var/run/docker.sock` into the container. **This is equivalent to handing host root to the container** — inside, you can fully control host Docker (including `docker run -v /:/host` to read/write the host root filesystem). Use it only when you fully trust the Agent and genuinely need docker commands inside the container.

> [!CAUTION]
> **About `--net host` safety (🌐)**:
> `--net host` shares the host network namespace — **container and host networks are fully shared with no isolation**: container ports are host ports (reachable from both directions), and any network listener inside (including RCE-grade APIs like `dsh web`) is directly exposed to the host network. Treated like `--docker-socket`: **the script prints a risk warning at startup**; use only when you fully trust what runs inside the container. For regular port exposure prefer `--port` (keeps bridge isolation).

> [!WARNING]
> **Docker Desktop's host loopback channel (verified)**: Docker Desktop (Windows / macOS / WSL2 backend) injects `host.docker.internal` into containers by default (pointing at the Docker VM gateway, e.g. `192.168.65.254`). **Verified: a bridge container can reach the host machine's `127.0.0.1`-only services through it** (loopback-only listeners on both Windows and the WSL2 distro were reached) — bridge isolation does NOT protect the host's loopback ports; sensitive local services (local APIs, dev servers, etc.) on the host are visible to containers. Native Linux Docker has no such default injection (you'd add `--add-host` yourself). To fully cut the container→host network channel, use `--net off` (verified: not even DNS resolution works).

---

## Config migration (reusing host login state)

Already logged into an Agent on the host? Copy the login state into the persistent volume once and skip re-login inside the container. Core idea: **login state dir → `docker run` with the volume mounted** (run on the host).

| Agent | Config dir | Key credential file | Notes |
| :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/` + `~/.claude.json` | `~/.claude/.credentials.json` (0600) | also copy the `~/.claude.json` file separately |
| Codex | `~/.codex/` | `~/.codex/auth.json` | if missing, credentials live in keychain — not migratable |
| OpenCode | `~/.config/opencode/` + `~/.local/share/opencode/` | `~/.local/share/opencode/auth.json` | two dirs, copy both |
| Pi | `~/.pi/agent/` | `~/.pi/agent/auth.json` | |
| Antigravity | `~/.antigravitycli/` | login state lives in the OS keychain | not migratable as files — re-login inside the container (the terminal prints an authorization link + code) |
| DeepSeek Harness | `~/.dsh/` (default `$DSH_HOME`) | `~/.dsh/.credentials.yaml` | keys entered in the Web UI live here; simpler: set `DEEPSEEK_API_KEY` in `.env`, no migration needed |

```bash
# Generic template: copy host <src> into the persistent volume (substitute paths from the table)
docker run --rm -v agent_docker_kali-home:/home/kali -v "$HOME/<src>:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/<dst> && cp -a /src/. /home/kali/<dst>/"
```

> [!WARNING]
> **Notes**: re-login to Antigravity inside the container instead (its login state lives in the OS keychain, likely unreadable after migration; the terminal prints an authorization link + code flow); the commands overwrite same-named files inside the container — back up first; macOS keychain credentials can't be migrated as files; if credentials become unreadable after migration it's usually an ownership issue — fix with `sudo chown -R kali:kali ~/.<dir>` inside the container.

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

**Default behavior**: syncs both the persistent volume and the current project dir by default; the volume uses **container-nested** rsync over ssh, dirs use **direct** rsync (faster). Default flags: `-az --numeric-ids --partial --partial-dir=.rsync-partial` (same as rsync's own default: remote-only files are **not** deleted; pass `-- --delete` explicitly for mirroring), ssh keepalive, and 10 built-in retries (30 s apart).

> [!NOTE]
> **`--delete` is off by default**: consistent with rsync's native default, files only present on the remote are kept. For a true mirror, pass `dkagent sync push <peer> -- --delete` explicitly — and strongly recommend a `--dry-run` first to see what would be deleted, especially `.env` API keys and `.git/` history.

**Options at a glance**: `--remote-path PATH` / `--no-volume` / `--no-project` / `--dry-run` / `-y` / `--retries N` / `-- RSYNC_ARGS` (see `dkagent sync --help`).

**Config files**: `~/.config/dkagent/peers` (peer list), `~/.config/dkagent/sync-mapping` (path mapping; auto-managed by the script, but editable by hand).

**Security constraints**: peer user/host may only contain alphanumerics and `. _ -`; remote paths allow alphanumerics, `. _ - / ~`, and non-ASCII characters such as CJK, but still no spaces or shell metacharacters (prevents injection via the rsync remote shell — shell metacharacters are all ASCII, so allowing non-ASCII bytes does not widen the attack surface); a peers file whose mode is not 600 triggers a warning; the first volume sync records the `dkagent-sync` image fingerprint (`~/.config/dkagent/sync-image.id`) and **refuses to run** if the image is ever replaced — delete that file to re-trust after a deliberate rebuild; the container only mounts the identity files your local ssh would actually use (resolved via `ssh -G`) or the SSH agent socket — the whole `~/.ssh` directory is no longer mounted.

---

## Command-line reference

```bash
dkagent [options] [agent] [extra args...]    # agent: claude/agy/pi/codex/opencode/dsh; empty → interactive zsh
```

```bash
dkagent                                # interactive Kali shell (mounts cwd)
dkagent claude                         # wake up Claude Code inside the container
dkagent -m ./a -r -m ./b agy            # multi-dir mounts, a read-only, b writable
dkagent -p slim claude                 # switch profile
dkagent --docker-socket claude         # docker inside the container (⚠️ equals host root)
dkagent --port 127.0.0.1:3080:3080 dsh web   # 🌐 dsh Web UI via port mapping (host side bound to 127.0.0.1 only — no LAN exposure; one-time cordis patch binding 0.0.0.0 needed first, see "Port-mapping in action" below)
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
| `--net MODE` | network mode (default: bridge): `off` = no network at all (`--network none`; no network interfaces, internet and host ports unreachable — safest); `host` = share the host network (`--network host`), ⚠️ no isolation, risk warning printed at startup; `--port` has no effect in either mode |
| `--no-tmux` / `--tmux-name NAME` | disable / customize the tmux wrapper |
| `--env FILE` | specify a `.env` file |
| `--lang zh\|en` | UI language (auto-detected from `$LANG`/`$LC_ALL`; `export DKAGENT_LANG=en` persists) |
| `--dry-run` | print the `docker run` command only, don't launch (env vars masked; `DKAGENT_DRY_RUN_SHOW_SECRETS=1` reveals them) |
| `-h, --help` | show help |

**Image priority**: `--image` > `--profile` > env `DKAGENT_PROFILE` > default `kali`.

---

## Port-mapping in action: DeepSeek Harness Web UI

DeepSeek Harness (command `dsh`) has both a terminal CLI and a built-in Web UI. **The safe default**: `dsh web` binds `127.0.0.1` only (an official safety default — the Web API can execute bash, i.e. RCE-grade), reachable only inside the container; no Web needed? Use the CLI form (see key points). Two ways to expose it to the host:

**Option 1: `--port` port mapping (✅ recommended: keeps bridge isolation; the only exposure is the port you publish)**

```bash
# First time: enter the container and create the config (opt-in — the Web becomes
# visible outside the container only after binding 0.0.0.0)
dkagent
mkdir -p ~/.dsh && cat > ~/.dsh/cordis.patch.yml <<'EOF'
- id: webserver
  config:
    host: 0.0.0.0
    port: 3080
EOF
# From then on:
dkagent --port 127.0.0.1:3080:3080 dsh web
# open http://localhost:3080 in your browser; the host side is bound to 127.0.0.1 only, so LAN machines cannot reach it
```

> ⚠️ **Security note**: Docker's `-p`/`-P` port mapping forwards traffic to the **container's eth0 IP**, so a service listening only on `127.0.0.1` inside never sees it (verified: 5/5 connection failures), and the current dsh CLI **deliberately rejects `--host 0.0.0.0`** — hence the config-layer opt-in for the in-container bind. **The exposure boundary is the host-side bind address**: `--port 3080:3080` (no IP) makes docker bind the host's `0.0.0.0` (verified: `docker port` shows `0.0.0.0:3080`, and Docker Desktop punches the Windows firewall), so the RCE-grade Web API becomes visible to the LAN. **Always write `--port 127.0.0.1:3080:3080`** — loopback-only, and Docker Desktop still forwards localhost to your terminal (verified on WSL2). Binding 0.0.0.0 inside the container merely makes the service reachable for the bridge forward; it is not itself the exposure. When done, close the container or delete the patch to restore loopback.

**Option 2: `--net host` (works on native Linux; ⚠️ no network isolation)**

```bash
dkagent --net host dsh web
# open http://localhost:3080 (no --port needed; keep dsh's default 127.0.0.1 bind, do NOT create the cordis patch)
```

With `--network host` the container shares the host's network namespace, so the container's `127.0.0.1` IS the host's `127.0.0.1` — **keep dsh's default loopback bind** and the Web UI is local-only: no patch, no LAN exposure. ⚠️ **Never combine this with Option 1's cordis patch (0.0.0.0)**: in host mode the container's bind IS the host's bind, so 0.0.0.0 would expose the RCE-grade API to the entire LAN directly — delete `~/.dsh/cordis.patch.yml` first. Host mode itself still has no network isolation: the container can reach ALL host ports and services, and can bind host ports directly. High risk; the script prints a risk warning at startup (see the [safety model](#safety-model-see-how-much-power-you-gave-the-agent-at-a-glance)).

**Safest tier: fully offline CLI (`--net off`)**

```bash
dkagent --net off dsh --profile headless "run the tests"
```

With `--network none` the container has no network interfaces at all — the internet and all host ports (including Docker Desktop's `host.docker.internal` loopback channel) are unreachable; it works purely through mounted directories. Use this tier for any task that needs no Web UI and no network.

> ⚠️ **Platform note (verified)**: on WSL2 + Docker Desktop, `--network host` attaches to the **Docker VM's namespace** (docker-desktop distro, 192.168.65.x), NOT your WSL2 distro — the container's `127.0.0.1` is unreachable from your terminal (verified: all curls refused, even when the container binds 127.0.0.1 only). On native Linux Docker it shares the host netns as expected. On Docker Desktop, use Option 1 (`--port 127.0.0.1:...`).

Key points:
- **API key**: after startup, enter it in the browser under Settings → Models (stored in `~/.dsh/.credentials.yaml`, persisted in the Home volume), or simply put `DEEPSEEK_API_KEY=sk-...` in `~/.config/dkagent/.env` (dkagent injects it into the container automatically)
- **Change the port**: edit the `port` in `~/.dsh/cordis.patch.yml`, and update the `--port 127.0.0.1:...` mapping (Option 1) accordingly
- **CLI form**: `dkagent dsh --profile headless "run the tests"` (one-shot task, exposes no port at all); interactive TUI via `dsh --profile tui`
- Adding `-e` (ephemeral) for the Web UI works fine too — close the container and no state remains (the ephemeral Home doesn't keep the patch; recreate it each time)

---

## Alternative: Docker Compose

Prefer not to use the CLI? `docker compose run --rm` works too — all three modes share the same persistent Home volume (fully interchangeable with the CLI): `agent-shell` (Home only, 🟢) / `agent-isolated` (no mounts, ephemeral, 🟢) / `agent-sandboxed` (Home + `./workspace` mount, 🟡). Switch images: `DKAGENT_IMAGE=dkagent-slim docker compose run --rm agent-shell`.

---

## Desktop Agent connections

Desktop Agents (e.g. Zhipu's ZCode) can use this environment too. ZCode can connect **directly to a running container** (no exposed ports needed): the container name is `dkagent-<project dirname>` (e.g. `dkagent-my-project`), and the user inside is `kali`. For Agents that only support SSH, use `--port` at startup to map a container service port to the host and connect directly (e.g. `dkagent --port 127.0.0.1:2222:22 claude` — the `127.0.0.1:` prefix keeps it local-only; without it the port is visible on the LAN; a service must be listening on that port inside) — no tunnel needed.

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
- [x] Offline tier (`--net off`, `--network none` — fully offline; verified to block Docker Desktop's `host.docker.internal` loopback channel) | [ ] Egress-restriction tier (`--net strict`: default-deny + allowlist; note: a "block internet, allow LAN" policy still leaves the Docker Desktop gateway address able to reach the host loopback — must be handled explicitly)
- [x] **Container port mapping** (`--port`; expose any container port to the host for external / desktop Agents)

---

## License

[MIT](LICENSE)
