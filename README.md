# dkagent

> 一个 bash 命令，把任意目录变成隔离的 AI Agent 运行环境。

基于 Docker 的 AI Agent CLI 运行沙箱。一行命令拉起容器，内置 Claude Code、Gemini CLI、Codex、Pi、OpenCode 五大 Agent，支持**多目录协作**、**逐目录只读挂载**、**多镜像 profile** 切换，并用 🟢🟡🔴 三色让你一眼看清每次给了 Agent 多大权限。

---

## 为什么用 dkagent

部分 AI Agent（如 Claude Code、Codex）开始提供自带沙箱。它们的模型通常是"系统级可读、按需放开可写"，单目录、单 agent 场景很好用。dkagent 解决的是另外几个问题：

**1. 逐目录独立读写控制 —— 自带沙箱做不到这种粒度**
你可以同时挂载多个目录，每个目录独立控制读写权限：
```bash
# 原始项目只读参考（绝对改不了），副本目录可读写
dkagent -m ./original -r -m ./workspace/my-copy claude
```
这让"参考 A 项目代码、改 B 项目"这种真实场景成为可能 —— Agent 能读你的共享库，但绝不会误改它。

**2. 多 Agent 统一入口 —— 一套环境切换五个 Agent**
不用为每个 Agent 单独配环境、装依赖。dkagent 把 Claude / Gemini / Codex / Pi / OpenCode 都装进同一个镜像，持久化 Home 卷保留所有 Agent 的登录凭证和配置，切换无感。

**3. Kali 工具链就绪 —— 安全研究向开箱即用**
默认镜像基于 Kali Linux，内置 Playwright 浏览器、nmap、fd、ripgrep、oh-my-zsh 等全套工具。需要更轻量？切换到 `slim` profile（基于 Debian slim，体积小三分之二）。

---

## 快速开始

推荐先用 **slim 镜像**（基于 Debian slim，体积小、构建快，约 2-3 分钟），跑通后再按需切换 Kali 镜像。

```bash
# 1. 安装 CLI 工具（会自动创建 ~/.config/dkagent/ 并拷贝 .env 模板）
chmod +x install.sh && ./install.sh

# 2. 填入 API Keys（首次安装后在此文件编辑，切勿提交 git）
vi ~/.config/dkagent/.env

# 3. 构建 slim 镜像（快速，约 2-3 分钟）
docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim .

# 4. 在任意目录下，一行命令拉起
cd ~/my-project
dkagent -p slim claude --dangerously-skip-permissions
```

> **关于 `--dangerously-skip-permissions`**：因为 dkagent 已用容器做了隔离，可以放心把这个"全自动"标志交给 Agent，让它在容器内免确认地执行命令——这正是容器化的核心收益。

### 想用 Kali 镜像？（可选）

Kali 镜像内置完整安全研究工具链（nmap、metasploit、Playwright 等），但**体积约 10GB，首次构建需要 15-30 分钟**（取决于网络）：

```bash
docker compose build              # 构建 kali 镜像（my-kali-agent）
dkagent claude                    # 默认就用 kali profile
```

> **macOS 用户**：本脚本用到 bash 4+ 的关联数组，macOS 系统自带 bash 是 3.2（2007），需先 `brew install bash` 装新版。详见下方[平台支持](#平台支持)。

---

## 平台支持

| 平台 | 状态 | 说明 |
| :--- | :--- | :--- |
| **Linux** | ✅ 原生支持 | 已验证 |
| **WSL2** | ✅ 原生支持 | 已验证。Windows 用户推荐用 WSL2 + Docker Desktop |
| **macOS** | ⚠️ 理论可行，未实测 | 脚本用了 bash 4+ 关联数组，macOS 系统 bash 是 3.2，需先 `brew install bash`。欢迎 macOS 用户反馈实际体验 |
| **Windows 原生** | ❌ 不支持 | 无 bash/sudo，请用 WSL2 |

---

## 镜像 Profile（多环境切换）

dkagent 通过 profile 切换不同的运行环境。所有 profile **共享同一个持久化 Home 卷**，切换镜像时你的 zsh 配置、命令历史、Agent 登录凭证全部保留。

| Profile | 基础镜像 | 体积 | 适合场景 |
| :--- | :--- | :--- | :--- |
| **`kali`** (默认) | Kali Linux | 大 | 安全研究、渗透测试、需要完整工具链 |
| **`slim`** | Debian slim | 小 | 日常编码、CI/CD、追求启动速度 |

```bash
# 默认用 kali
dkagent claude

# 切换到精简镜像
docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim .   # 先构建一次
dkagent -p slim claude

# 直接指定任意自定义镜像（escape hatch）
dkagent --image my-custom-agent claude
```

**添加自定义 profile**：在 `~/.config/dkagent/profiles` 文件里追加一行：
```
node=my-node-agent
rust=my-rust-agent
```
之后即可 `dkagent -p node claude`。

> **⚠️ 自定义镜像约束**：要让持久化 Home 卷能跨镜像复用，自定义镜像的 Dockerfile 必须创建 `kali` 用户并使用 `/home/kali` 作为 home 路径（参考 `dockerfiles/Dockerfile.slim`）。否则需用 `-e`（临时 Home）模式运行。

---

## 配置迁移（从宿主机复用登录态）

如果你已在宿主机登录过某个 Agent，可把登录态一次性拷进 dkagent 持久化卷，避免在容器里重新登录。以下命令在**宿主机**执行。

### 各 Agent 配置路径速查

| Agent | 配置目录 | 关键凭证文件 | 备注 |
| :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/` + `~/.claude.json` | `~/.claude/.credentials.json` (0600) | 还需单独拷 `~/.claude.json` 这个文件 |
| Codex | `~/.codex/` | `~/.codex/auth.json` | 文件不存在说明走 keychain，无法迁移 |
| OpenCode | `~/.config/opencode/` + `~/.local/share/opencode/` | `~/.local/share/opencode/auth.json` | 配置和凭证是两个目录，都要拷 |
| Pi | `~/.pi/agent/` | `~/.pi/agent/auth.json` | |

### 以 Claude Code 为例

```bash
# 1. 拷贝 ~/.claude/ 配置目录（含登录凭证）
docker run --rm \
  -v agent_docker_kali-home:/home/kali \
  -v "$HOME/.claude:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/.claude && cp -a /src/. /home/kali/.claude/"

# 2. 拷贝 ~/.claude.json 用户配置文件（注意是文件不是目录）
docker run --rm \
  -v agent_docker_kali-home:/home/kali \
  -v "$HOME/.claude.json:/src:ro" \
  alpine sh -c "cp -a /src /home/kali/.claude.json"
```

### 以 Codex 为例

```bash
# 前置检查：若 ~/.codex/auth.json 不存在，说明凭证在 keychain，无法用文件迁移
ls ~/.codex/auth.json

docker run --rm \
  -v agent_docker_kali-home:/home/kali \
  -v "$HOME/.codex:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/.codex && cp -a /src/. /home/kali/.codex/"
```

> [!WARNING]
> **迁移注意事项**
> - **Gemini 建议容器内重新登录**：默认用系统 keyring 存凭证，加密 key 绑定 hostname + username，迁移到容器后大概率解不开。
> - **覆盖风险**：上述命令会覆盖容器内同名文件。若容器里已有配置，先备份。
> - **跨平台**：macOS 来源的 keychain 凭证无法用文件迁移，需在容器内重新登录。
> - **属主权限**：迁移后若凭证读不到，通常是属主不对，进容器 `sudo chown -R kali:kali ~/.对应目录` 修复。

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

## 命令行使用说明

### 基础命令结构

```bash
dkagent [选项] [agent名称] [附加参数...]
```

### 常用操作

```bash
# 进入交互式 Kali 命令行（挂载当前目录）
dkagent

# 直接唤醒容器内的 Claude Code
dkagent claude

# 使用临时 Home 卷（用完即焚）
dkagent -e claude

# 挂载多个目录（原项目 + 共享库）
dkagent -m ./my-project -m ./shared-libs claude

# 原始项目只读参考，副本目录可读写
dkagent -m ./my-project -r -m ./workspace/my-copy gemini

# 切换精简镜像
dkagent -p slim claude

# 纯净模式，不挂载任何宿主机目录
dkagent --no-mount

# 容器内可用 docker 命令（⚠️ 最高风险，等同宿主 root）
dkagent --docker-socket claude
```

### 可选参数

| 选项 | 说明 |
| :--- | :--- |
| `-p, --profile NAME` | 🎚️ 选择镜像 profile（默认 `kali`，可选 `slim` 或自定义） |
| `--image NAME` | 🐳 直接指定任意 Docker 镜像名（优先级高于 `--profile`） |
| `-e, --ephemeral` | 🧊 使用临时 Home 目录，退出后不留痕迹 |
| `-m, --mount DIR` | 📁 挂载目录到 `/home/kali/workspace/<目录名>`，支持多次指定或空格分隔 |
| `-r, --readonly` | 🔒 紧跟 `-m` 之后，将前一个目录以只读方式挂载 |
| `--no-mount` | 🟢 不挂载任何宿主机目录（最安全） |
| `--docker-socket` | 🐋 挂载宿主 docker.sock，容器内可运行 docker 命令（⚠️ **最高风险，等同宿主 root**） |
| `--env FILE` | 手动指定 `.env` 配置文件 |
| `--dry-run` | 🔍 仅打印将要执行的 `docker run` 命令，不实际启动 |
| `-h, --help` | 显示帮助 |

**镜像优先级**：`--image` > `--profile` > 环境变量 `DKAGENT_PROFILE` > 默认 `kali`

**Agent 名称**：`claude` / `gemini` / `pi` / `codex` / `opencode`，留空则进入交互式 zsh。

---

## 备用运行方式 (Docker Compose)

如果不想用 `dkagent` CLI，也可直接通过 `docker compose` 启动。三种模式均共享同一个持久化 Home 卷（与 CLI 完全互通）。

```bash
# 🏠 调试/Shell 模式 - 仅持久化 Home，不挂载工作目录 (🟢)
docker compose run --rm agent-shell

# 🧊 纯净/隔离模式 - 无任何挂载，用完即焚 (🟢)
docker compose run --rm agent-isolated

# 📂 沙盒模式 - 持久化 Home + 挂载 ./workspace (🟡)
docker compose run --rm agent-sandboxed

# 切换镜像（复用同一个 Home 卷）
DKAGENT_IMAGE=dkagent-slim docker compose run --rm agent-shell
```

---

## 目录结构

```
.
├── dkagent                  # 核心 bash CLI（参数解析、挂载、风险打印）
├── Dockerfile               # 默认 profile (kali) 构建配置
├── dockerfiles/
│   └── Dockerfile.slim      # slim profile 构建配置（精简 Debian）
├── docker-compose.yaml      # 备用的三种 compose 运行模式
├── install.sh               # 一键安装/卸载脚本
├── .env.example             # API Keys 配置模板
└── workspace/               # 沙盒模式预设的工作目录
```

---

## Roadmap

- [x] 多目录挂载 + 逐目录只读控制
- [x] 8 档风险分级可视化
- [x] 多镜像 profile 切换
- [x] 容器内运行 Docker（`--docker-socket`）
- [ ] **网络隔离档位**（`--net off` / `--net strict`，简单易用，契合多 agent 场景）

---

## 许可证

[MIT](LICENSE)
