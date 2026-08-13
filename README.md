# dkagent

> 📖 English documentation: [README.en.md](README.en.md)

> 一个 bash 命令，把任意目录变成隔离的 AI Agent 运行环境。

基于 Docker 的 AI Agent CLI 运行沙箱。一行命令拉起容器，内置 Claude Code、Gemini CLI、Codex、Pi、OpenCode 五大 Agent，支持**逐目录只读挂载**、**多镜像 profile** 切换、tmux 断线重连与多机接力同步，并用 🟢🟡🔴 三色让你一眼看清每次给了 Agent 多大权限。

---

## 核心特性

**1. 逐目录读写控制，一行命令搞定**
```bash
# 原始项目只读参考，副本目录可读写
dkagent -m ./original -r -m ./workspace/my-copy claude
```
只读目录靠 Docker bind mount 钉在内核层——"参考 A 项目、改 B 项目"一行成立。

**2. 多 Agent 统一入口**：Claude / Gemini / Codex / Pi / OpenCode 全装进同一个镜像，持久化 Home 卷保留登录凭证与配置，切换无感。

**3. Kali 工具链开箱即用**：默认镜像基于 Kali Linux（nmap、ripgrep、Playwright 等全套）；要轻量就切 `slim` profile（Debian slim，小三分之二）。

**4. 纵深防御（Defense in Depth）**：Agent 自带的容器与安全措施也时有漏洞。dkagent 在**外部再加一层 Docker 隔离**——即使 Agent 内部防线被绕过，也碰不到宿主机文件。

---

## 前置要求

| 依赖 | 用途 | 安装 |
| :--- | :--- | :--- |
| **Docker** | 必需 | Linux: `apt install docker.io` / macOS、Windows: Docker Desktop |
| **git** | 拉取本仓库 | `apt install git` / `brew install git` |
| **bash 4+** | 脚本运行 | macOS 自带 bash 是 3.2，需 `brew install bash` |
| **ssh 客户端** | `dkagent sync` 与远程连接 | Linux: `apt install openssh-client` / macOS 自带 |
| **rsync** | 仅 `dkagent sync` 目录同步需要（卷同步走容器） | `apt install rsync` / `brew install rsync` |
| **tmux** | 可选，装了自动获得断线保护 | `apt install tmux` / `brew install tmux` |

`dkagent sync` 的卷同步还需先构建辅助镜像 `dkagent-sync`（约 14MB）：`docker build -t dkagent-sync -f dockerfiles/Dockerfile.sync .`

---

## 安装与快速开始

推荐先用 **slim 镜像**（构建约 2-3 分钟）跑通，再按需切换 Kali。

```bash
# 1. 安装 CLI（自动创建 ~/.config/dkagent/ 并拷贝 .env 模板）
chmod +x install.sh && ./install.sh
# 2. 填入 API Keys（切勿提交 git）
vi ~/.config/dkagent/.env
# 3. 构建 slim 镜像
docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim .
# 4. 在任意项目目录下一行命令拉起
cd ~/my-project
dkagent -p slim claude --dangerously-skip-permissions
```

> **关于 `--dangerously-skip-permissions`**：真正的安全边界是容器，不是 Agent 的权限确认——容器已隔离，可以放心把"全自动"标志交给 Agent。

**想用 Kali 镜像？**（约 10GB，首次构建 15-30 分钟）：`docker compose build` 后直接 `dkagent claude`（默认 profile 就是 kali）。

**平台支持**：Linux / WSL2 ✅ 原生支持；macOS ⚠️ 需先 `brew install bash`；Windows 原生 ❌ 不支持，请用 WSL2。

---

## 环境变量注入（.env）

dkagent 会自动查找 `.env` 文件，把其中每行 `KEY=value` 以环境变量注入容器（Agent 与脚本都能读到）。查找顺序：`$DKAGENT_ENV` 指定的路径 → `~/.config/dkagent/.env` → 脚本所在目录的 `.env`。

```bash
# 每次进入前，把物理机上的 env 文件复制为 .env，dkagent 自动注入
cp ~/projects/secrets.env ~/.config/dkagent/.env
dkagent claude        # 容器内可直接读到 .env 里的所有 KEY
```

宿主机已导出的 `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` / `OPENAI_API_KEY` / `OPENROUTER_API_KEY` 会覆盖 `.env` 同名项直接透传；空行与 `#` 注释自动跳过。

---

## 镜像 Profile（多环境切换）

所有 profile **共享同一个持久化 Home 卷**——切换镜像时 zsh 配置、命令历史、Agent 登录凭证全部保留。

| Profile | 基础镜像 | 适合场景 |
| :--- | :--- | :--- |
| **`kali`** (默认) | Kali Linux | 安全研究、渗透测试、完整工具链 |
| **`slim`** | Debian slim | 日常编码、追求启动速度 |

```bash
dkagent claude                          # 默认 kali
dkagent -p slim claude                  # 切换精简镜像（先 docker build -t dkagent-slim ...）
dkagent --image my-custom-agent claude  # 直接指定任意镜像（escape hatch）
```

**自定义 profile**：在 `~/.config/dkagent/profiles` 追加一行 `node=my-node-agent`，即可 `dkagent -p node claude`。

> **⚠️ 自定义镜像约束**：要让持久化 Home 卷跨镜像复用，镜像必须创建 `kali` 用户并使用 `/home/kali` 作为 home 路径（参考 `dockerfiles/Dockerfile.slim`），否则需用 `-e`（临时 Home）模式。

---

## 安全模型：一眼看懂你给了 Agent 多大权限

AI Agent 在执行任务时拥有强大的文件系统权限。为防止 Agent 遭遇恶性提示词或误判时删除、清空宿主机文件（如 `rm -rf` 风险），dkagent 用 **挂载模式 × Home 持久化** 两个维度组合出清晰的风险等级，每次运行都会打印当前级别。

```
  安全性 ▲
        │
   🟢 隔离级别     --no-mount + -e          完全隔离，用完即焚
        │
   🟢 低风险       --no-mount               隔离宿主文件，持久化 home 有配置被改风险
   🟢 低风险       全只读挂载 + -e           只能读取宿主文件，退出不留痕
        │
   🟡 中低风险     全只读挂载               只能读取，但持久化 home 有配置被改风险
   🟡 中风险       有可写挂载 + -e           可操作挂载目录，退出不留痕
        │
   🔴 高风险       有可写挂载               可操作挂载目录 + 持久化 home 可留后门
        │
   ☠️ 逃逸级别     --docker-socket          docker.sock = 宿主 root，无视上述所有档位
        │
        └────────────────────────────────────────────────▶ 便捷性
```

### 完整运行模式安全对比

| 运行方式 | Home | 挂载模式 | 风险 | 适合场景 |
| :--- | :--- | :--- | :--- | :--- |
| **`dkagent --no-mount -e`** | 🧊 用完即焚 | 🟢 不挂载 | **无 (🟢)** | 纯粹的沙盒测试 |
| **`dkagent --no-mount`** | 🏠 持久化卷 | 🟢 不挂载 | **低 (🟢)** | 配置容器内环境 |
| **`dkagent -e -m ./dir -r ...`** | 🧊 用完即焚 | 🟢 全只读 | **低 (🟢)** | 只读参考多个项目 |
| **`dkagent -m ./dir -r ...`** | 🏠 持久化卷 | 🟢 全只读 | **中低 (🟡)** | 只读参考 + 持久配置 |
| **`dkagent -e [agent]`** | 🧊 用完即焚 | 🔴 有可写 | **中 (🟡)** | 临时编码任务 |
| **`dkagent -e -m ... [agent]`** | 🧊 用完即焚 | 🔴 有可写 | **中 (🟡)** | 临时沙盒编码 |
| **`dkagent [agent]`** | 🏠 持久化卷 | 🔴 有可写 | **高 (🔴)** | 日常高效编码（信任 Agent） |
| **`dkagent -m ... [agent]`** | 🏠 持久化卷 | 🔴 有可写 | **高 (🔴)** | 多目录编码任务 |
| **`dkagent --docker-socket [agent]`** | 🏠/🧊 | 🐋 docker.sock | **逃逸 (☠️)** | 需在容器内运行 docker 命令 |

> [!CAUTION]
> **关于 Home 卷持久化的安全提示 (🏠)**:
> 持久化 Home 卷会保留你的 Oh-My-Zsh 配置、命令历史及 Agent 的会话 Session。如果 Agent 被外部恶意控制，理论上可能通过修改你持久化的 `.zshrc` 来埋下后门。若对运行安全性有极端要求，推荐加 `-e`（用完即焚）选项。

> [!CAUTION]
> **关于 `--docker-socket` 的安全提示 (☠️)**:
> `--docker-socket` 会挂载宿主机的 `/var/run/docker.sock` 到容器内。**这等同于把宿主机 root 权限交给容器**——容器内可任意控制宿主 Docker（包括 `docker run -v /:/host` 读写宿主根文件系统）。仅在你完全信任 Agent 且确实需要在容器内运行 docker 命令时使用。

---

## 配置迁移（从宿主机复用登录态）

已在宿主机登录过 Agent？把登录态一次性拷进持久化卷，避免容器内重新登录。核心思路：**登录态目录 → `docker run` 挂载卷拷贝**（命令在宿主机执行）。

| Agent | 配置目录 | 关键凭证文件 | 备注 |
| :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/` + `~/.claude.json` | `~/.claude/.credentials.json` (0600) | 还需单独拷 `~/.claude.json` 文件 |
| Codex | `~/.codex/` | `~/.codex/auth.json` | 文件不存在说明走 keychain，无法迁移 |
| OpenCode | `~/.config/opencode/` + `~/.local/share/opencode/` | `~/.local/share/opencode/auth.json` | 两个目录都要拷 |
| Pi | `~/.pi/agent/` | `~/.pi/agent/auth.json` | |

```bash
# 通用模板：把宿主 <src> 拷贝进持久化卷（替换为表中对应路径）
docker run --rm -v agent_docker_kali-home:/home/kali -v "$HOME/<src>:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/<dst> && cp -a /src/. /home/kali/<dst>/"
```

> [!WARNING]
> **注意事项**：Gemini 建议容器内重新登录（凭证加密绑定 hostname + username，迁移后大概率解不开）；命令会覆盖容器内同名文件，先备份；macOS keychain 凭证无法用文件迁移；迁移后凭证读不到通常是属主不对，进容器 `sudo chown -R kali:kali ~/.对应目录` 修复。

---

## 远程会话与断线重连

SSH 连物理机跑 Agent 时，终端一断会话就丢。dkagent **默认自动用 tmux 包装**（宿主机装了 tmux 时）——会话跑在物理机的 tmux 里，SSH 断了 Agent 继续跑：

```bash
ssh user@host
cd ~/project-a
dkagent claude                  # 创建 tmux 会话 dkagent-project-a，Agent 在其中运行
# SSH 断了重新连上后：
tmux attach -t dkagent-project-a   # 接回原会话（再跑 dkagent 会新建 _2 会话而非 attach）
```

每次运行新建独立 session（重名自动加 `_2`、`_3` 后缀）；容器默认命名 `dkagent-<目录名>`，方便 `docker ps` 识别。可用 `--tmux-name NAME` 自定义会话名、`--no-tmux` 关闭包装；`DKAGENT_NO_CONTAINER_NAME=1` 禁用容器命名（回到 Docker 随机名）。

---

## 出门在外：远程连家里电脑

家里电脑没有公网 IP，外面 SSH 连不上——用**内网穿透**（NAT 穿透 / 反向隧道）打通，两种选择：

**选择一：自建隧道（以 FRP 为例）**：一台有公网 IP 的轻量服务器跑 `frps`，家里电脑跑 `frpc` 把 SSH 22 映射到服务器端口，外面直接连服务器：`ssh -p 6000 user@server.example.com`。同类：ngrok、Tailscale / ZeroTier 组网。

**选择二：第三方端口映射服务（以网易 UU 远程为例）**：免费、零服务器。家里与外面的电脑都装 [UU 远程](https://uuyc.163.com/) 客户端并登录同一账号；家里电脑在「设备列表 → 更多 → 端口映射」新建映射：本地访问端口（如 13022）→ 目标 `127.0.0.1:22`，保持规则启用；外面连本机端口即可（TCP）：`ssh -p 13022 user@127.0.0.1`。同类：花生壳等。

**手机**：直接装 [UU 远程](https://uuyc.163.com/) 客户端远程控制家里电脑即可（手机端不支持端口映射，无需 SSH 隧道）；要纯命令行编程，用 Termux + `pkg install openssh` 配合选择一。

> **安全提示**：临时映射用完即关；SSH 一律用密钥而非密码。

---

## 多机接力同步

多台电脑接力工作：`dkagent sync` 把持久化卷（工具配置 / 命令历史 / Agent 凭证）和项目目录同步到对端。**完全手动触发，`dkagent claude` 等命令绝不会自动同步**。

**准备工作**（两端各一次）：装 Docker + dkagent → 配好 SSH 免密 → 构建 `dkagent-sync` 镜像（见[前置要求](#前置要求)）→ 编辑 `~/.config/dkagent/peers`：
```
# 每行: alias=ssh://user@host:port（配合隧道时填映射地址，如 ssh://user@127.0.0.1:13022）
laptop=ssh://user@laptop.local:22
```
> 该文件含 SSH URL，建议 `chmod 600 ~/.config/dkagent/peers`。

**基本用法**：
```bash
dkagent sync list                          # 看 peers + 当前目录映射
cd ~/my-project
dkagent sync push laptop --remote-path ~/my-project   # 首次（--remote-path 必填，自动存映射）
dkagent sync push laptop                   # 后续自动用已存映射
dkagent sync pull laptop                   # 反向同步（peer → 本地）
dkagent sync push laptop --dry-run         # 仅预览不实跑
dkagent sync push laptop -- --exclude=.git/ --exclude=.env   # 透传 rsync 参数
```

**默认行为**：默认同时同步持久化卷 + 当前项目目录；卷走**容器嵌套** rsync over ssh，目录走**直连** rsync（更快）。默认 flags：`-az --delete --numeric-ids --partial --partial-dir=.rsync-partial`，ssh keepalive + 内置 10 次重试（间隔 30 秒）。

> [!CAUTION]
> **`--delete` 默认开启**：远端独有的文件会被删除以维持镜像一致。首次同步前强烈建议 `--dry-run` 看会删什么——特别留意 `.env` API keys 与 `.git/` 历史。

**选项速查**：`--remote-path PATH` / `--no-volume` / `--no-project` / `--dry-run` / `-y` / `--retries N` / `-- RSYNC_ARGS`（详见 `dkagent sync --help`）。

**配置文件**：`~/.config/dkagent/peers`（peer 列表）、`~/.config/dkagent/sync-mapping`（项目路径映射，脚本自动管理，也可 vi 编辑）。

---

## 命令行使用说明

```bash
dkagent [选项] [agent名称] [附加参数...]    # agent: claude/gemini/pi/codex/opencode，留空进 zsh
```

```bash
dkagent                                # 交互式 Kali shell（挂载当前目录）
dkagent claude                         # 唤醒容器内 Claude Code
dkagent -m ./a -r -m ./b gemini        # 多目录挂载，a 只读 b 可写
dkagent -p slim claude                 # 切换 profile
dkagent --docker-socket claude         # 容器内可用 docker（⚠️ 等同宿主 root）
dkagent --dry-run                      # 只打印 docker run 命令不执行
```

| 选项 | 说明 |
| :--- | :--- |
| `-p, --profile NAME` | 选择镜像 profile（默认 `kali`） |
| `--image NAME` | 直接指定任意 Docker 镜像（优先级最高） |
| `-e, --ephemeral` | 临时 Home 目录，退出不留痕 |
| `-m, --mount DIR` / `-r` | 挂载目录（可多次）；紧跟的 `-r` 将其设为只读 |
| `--no-mount` | 不挂载任何宿主机目录（最安全） |
| `--docker-socket` | 挂载宿主 docker.sock（⚠️ **最高风险，等同宿主 root**） |
| `--port HOST:CONTAINER` | 端口映射（可重复，等价 `docker run -p`），如 `8080:8080`、`127.0.0.1:3000:3000`、`9000:9000/udp` |
| `--no-tmux` / `--tmux-name NAME` | 关闭 / 自定义 tmux 包装 |
| `--env FILE` | 指定 `.env` 配置文件 |
| `--lang zh\|en` | 界面语言（默认按 `$LANG`/`$LC_ALL` 自动识别；`export DKAGENT_LANG=en` 持久覆盖） |
| `--dry-run` | 仅打印 `docker run` 命令，不实际启动 |
| `-h, --help` | 显示帮助 |

**镜像优先级**：`--image` > `--profile` > 环境变量 `DKAGENT_PROFILE` > 默认 `kali`。

---

## 备用运行方式 (Docker Compose)

不用 CLI 也可 `docker compose run --rm` 直接启动，三种模式共享同一个持久化 Home 卷（与 CLI 完全互通）：`agent-shell`（仅 Home，🟢）/ `agent-isolated`（无挂载用完即焚，🟢）/ `agent-sandboxed`（Home + 挂载 workspace，🟡）。切换镜像：`DKAGENT_IMAGE=dkagent-slim docker compose run --rm agent-shell`。

---

## 桌面端 Agent 连接

桌面端 Agent（如智谱 ZCode）同样可以用这个环境。ZCode 支持**直连运行中的容器**（无需开放端口）：容器名即 `dkagent-<项目目录名>`（如 `dkagent-my-project`），容器内用户 `kali`。仅支持 SSH 的 Agent，可在启动时用 `--port` 把容器内服务端口映射到宿主机后直接连接（如 `dkagent --port 2222:22 claude`，容器内需有对应服务在监听），无需隧道。

---

## 目录结构

```
├── dkagent                  # 核心 bash CLI（挂载、风险分级、sync 子命令）
├── Dockerfile               # 默认 profile (kali)
├── dockerfiles/
│   ├── Dockerfile.slim      # slim profile（精简 Debian）
│   └── Dockerfile.sync      # dkagent-sync 镜像（rsync + ssh，跨机同步用）
├── docker-compose.yaml      # 备用 compose 运行模式
├── install.sh               # 一键安装/卸载
├── .env.example             # API Keys 配置模板
└── workspace/               # 沙盒模式工作目录
```

---

## Roadmap

- [x] 多目录挂载 + 逐目录只读控制 ｜ [x] 8 档风险分级可视化 ｜ [x] 多镜像 profile 切换
- [x] 容器内运行 Docker（`--docker-socket`） ｜ [x] 中英文双语界面（自动识别）
- [x] 容器命名按当前目录（重名 `_2` `_3` 后缀） ｜ [x] 多机接力同步（`dkagent sync push/pull`，纯手动）
- [ ] **网络隔离档位**（`--net off` / `--net strict`）
- [x] **容器端口映射**（`--port`，映射容器内任意端口到宿主机，供外部 / 桌面 Agent 通信）

---

## 许可证

[MIT](LICENSE)
