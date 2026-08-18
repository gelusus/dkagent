# dkagent

> 📖 English documentation: [README.en.md](README.en.md)

> 一个 bash 命令，把任意目录变成隔离的 AI Agent 运行环境。

基于 Docker 的 AI Agent CLI 运行沙箱。一行命令拉起容器，内置 Claude Code、Antigravity（`agy`）、Codex、Pi、OpenCode、DeepSeek Harness（`dsh`）六大 Agent，支持**逐目录只读挂载**、**多镜像 profile** 切换、tmux 断线重连与多机接力同步，并用 🟢🟡🔴 三色让你一眼看清每次给了 Agent 多大权限。

---

## 核心特性

**1. 逐目录读写控制，一行命令搞定**
```bash
# 原始项目只读参考，副本目录可读写
dkagent -m ./original -r -m ./workspace/my-copy claude
```
只读目录靠 Docker bind mount 钉在内核层——"参考 A 项目、改 B 项目"一行成立。

**2. 多 Agent 统一入口**：Claude / Antigravity（`agy`）/ Codex / Pi / OpenCode / DeepSeek Harness（`dsh`）全装进同一个镜像，持久化 Home 卷保留登录凭证与配置，切换无感。

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

dkagent 会自动查找 `.env` 文件，把其中每行 `KEY=value` 注入容器（Agent 与脚本都能读到）。查找顺序：`$DKAGENT_ENV` 指定的路径 → `~/.config/dkagent/.env`。

```bash
# 每次进入前，把物理机上的 env 文件复制为 .env，dkagent 自动注入
cp ~/projects/secrets.env ~/.config/dkagent/.env
dkagent claude        # 容器内可直接读到 .env 里的所有 KEY
```

宿主机已导出的 `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` / `OPENAI_API_KEY` / `OPENROUTER_API_KEY` / `DEEPSEEK_API_KEY` 会覆盖 `.env` 同名项直接透传；空行与 `#` 注释自动跳过。

**安全传递**：环境变量经**临时 `--env-file`**（0600、运行结束即删）传给 docker——不出现在宿主进程列表（`ps`）与命令行回显中；`--dry-run` 输出里环境变量默认打码为 `KEY=***`，设 `DKAGENT_DRY_RUN_SHOW_SECRETS=1` 才显示明文。旧版回退读取“脚本所在目录 `.env`”的行为已移除（防止 repo 目录被种入 `.env` 劫持后续运行）。注意：Agent 命令以 `zsh -f` 启动，**zsh 启动文件（`.zshenv` 等）里的变量不会传给 Agent**——需要注入请用 `.env`。

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
> 持久化 Home 卷会保留你的 Oh-My-Zsh 配置、命令历史及 Agent 的会话 Session。如果 Agent 被外部恶意控制，理论上可能通过修改持久化 Home 的 zsh 启动文件（`.zshenv` / `.zprofile`）来埋后门。为此 **Agent 命令一律以 `zsh -f` 启动（不读任何启动文件）**，但 `dkagent` 交互 shell 模式仍会 source `.zshrc`（保留用户配置，属已知权衡）——交互模式下请勿运行不可信内容。对安全性有极端要求时，推荐加 `-e`（用完即焚）选项。

> [!CAUTION]
> **关于 `--docker-socket` 的安全提示 (☠️)**:
> `--docker-socket` 会挂载宿主机的 `/var/run/docker.sock` 到容器内。**这等同于把宿主机 root 权限交给容器**——容器内可任意控制宿主 Docker（包括 `docker run -v /:/host` 读写宿主根文件系统）。仅在你完全信任 Agent 且确实需要在容器内运行 docker 命令时使用。

> [!CAUTION]
> **关于 `--net host` 的安全提示 (🌐)**:
> `--net host` 共享宿主网络命名空间——**容器与宿主网络完全互通、无隔离**：容器内端口即宿主端口（双向可达），容器内任何网络监听（包括 RCE 级 API 如 `dsh web`）都会直接暴露到宿主网络。与 `--docker-socket` 同级对待，**启动时脚本会打印风险提示**；仅在你完全信任容器内程序时使用。常规端口暴露请用 `--port`（保持 bridge 隔离）。

> [!WARNING]
> **Docker Desktop 的宿主回环通道（实测）**: Docker Desktop（Windows / macOS / WSL2 后端）默认向容器注入 `host.docker.internal`（指向 Docker 虚拟机网关，如 `192.168.65.254`）。**实测：bridge 容器经它可以触达宿主机/物理机只绑 `127.0.0.1` 的服务**（Windows 与 WSL2 发行版的 loopback-only 监听均被触达）——bridge 隔离并不保护宿主机的 loopback 端口，宿主机上敏感的本机服务（本地 API、开发服务器等）对容器是可见的。原生 Linux Docker 无此默认注入（需手动 `--add-host`）。要彻底阻断容器→宿主的网络通道，用 `--net off`（实测连解析都不通）。

---

## 配置迁移（从宿主机复用登录态）

已在宿主机登录过 Agent？把登录态一次性拷进持久化卷，避免容器内重新登录。核心思路：**登录态目录 → `docker run` 挂载卷拷贝**（命令在宿主机执行）。

| Agent | 配置目录 | 关键凭证文件 | 备注 |
| :--- | :--- | :--- | :--- |
| Claude Code | `~/.claude/` + `~/.claude.json` | `~/.claude/.credentials.json` (0600) | 还需单独拷 `~/.claude.json` 文件 |
| Codex | `~/.codex/` | `~/.codex/auth.json` | 文件不存在说明走 keychain，无法迁移 |
| OpenCode | `~/.config/opencode/` + `~/.local/share/opencode/` | `~/.local/share/opencode/auth.json` | 两个目录都要拷 |
| Pi | `~/.pi/agent/` | `~/.pi/agent/auth.json` | |
| Antigravity | `~/.antigravitycli/` | 登录态存系统钥匙串 | 无法用文件迁移，容器内重新登录（终端输出授权链接 + 验证码） |
| DeepSeek Harness | `~/.dsh/`（`$DSH_HOME` 默认值） | `~/.dsh/.credentials.yaml` | Web UI 里填的 key 存此文件；更省事是直接配 `.env` 的 `DEEPSEEK_API_KEY`，无需迁移 |

```bash
# 通用模板：把宿主 <src> 拷贝进持久化卷（替换为表中对应路径）
docker run --rm -v agent_docker_kali-home:/home/kali -v "$HOME/<src>:/src:ro" \
  alpine sh -c "mkdir -p /home/kali/<dst> && cp -a /src/. /home/kali/<dst>/"
```

> [!WARNING]
> **注意事项**：Antigravity 建议容器内重新登录（登录态存系统钥匙串，迁移后大概率解不开；终端会输出授权链接 + 验证码流程）；命令会覆盖容器内同名文件，先备份；macOS keychain 凭证无法用文件迁移；迁移后凭证读不到通常是属主不对，进容器 `sudo chown -R kali:kali ~/.对应目录` 修复。

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

Agent 退出时 pane 会先停留片刻（无论报错还是正常结束——报错会显示退出码），避免退出前的输出随 pane 销毁一闪而过。按回车立即关闭，默认 10 秒后自动关闭；`DKAGENT_EXIT_HOLD_SECS` 可调时长，设 `0` 禁用停留。

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

**默认行为**：默认同时同步持久化卷 + 当前项目目录；卷走**容器嵌套** rsync over ssh，目录走**直连** rsync（更快）。默认 flags：`-az --numeric-ids --partial --partial-dir=.rsync-partial`（与 rsync 原生默认一致，**不删**远端独有文件；需镜像一致时显式透传 `-- --delete`），ssh keepalive + 内置 10 次重试（间隔 30 秒）。

> [!NOTE]
> **`--delete` 默认关闭**：与 rsync 原生默认一致，远端独有文件不会被删除。需要镜像一致时显式 `dkagent sync push <peer> -- --delete`，并强烈建议先 `--dry-run` 看会删什么——特别留意 `.env` API keys 与 `.git/` 历史。

**选项速查**：`--remote-path PATH` / `--no-volume` / `--no-project` / `--dry-run` / `-y` / `--retries N` / `-- RSYNC_ARGS`（详见 `dkagent sync --help`）。

**配置文件**：`~/.config/dkagent/peers`（peer 列表）、`~/.config/dkagent/sync-mapping`（项目路径映射，脚本自动管理，也可 vi 编辑）。

**安全约束**：peer 用户名/主机仅允许字母数字及 `. _ -`；远端路径允许字母数字、`. _ - / ~` 及中文等非 ASCII 字符，但仍不支持空格与 shell 元字符（防经 rsync 远端 shell 注入——shell 元字符均为 ASCII，放行非 ASCII 字节不扩大攻击面）；peers 文件权限非 600 时运行会告警；首次卷同步会记录 `dkagent-sync` 镜像指纹（`~/.config/dkagent/sync-image.id`），镜像被替换时**拒绝执行**——确为本人重建镜像时删除该文件即可重新信任；容器内只挂载本机 ssh 实际会用到的身份文件（经 `ssh -G` 解析）或 SSH agent socket，不再整目录挂载 `~/.ssh`。

---

## 命令行使用说明

```bash
dkagent [选项] [agent名称] [附加参数...]    # agent: claude/agy/pi/codex/opencode/dsh，留空进 zsh
```

```bash
dkagent                                # 交互式 Kali shell（挂载当前目录）
dkagent claude                         # 唤醒容器内 Claude Code
dkagent -m ./a -r -m ./b agy            # 多目录挂载，a 只读 b 可写
dkagent -p slim claude                 # 切换 profile
dkagent --docker-socket claude         # 容器内可用 docker（⚠️ 等同宿主 root）
dkagent --port 127.0.0.1:3080:3080 dsh web   # 🌐 dsh Web UI 端口映射（宿主侧只绑 127.0.0.1，不暴露局域网；首次需先建 cordis patch 绑 0.0.0.0，见下文「端口映射实战」）
dkagent --dry-run                      # 只打印 docker run 命令不执行
```

| 选项 | 说明 |
| :--- | :--- |
| `-p, --profile NAME` | 选择镜像 profile（默认 `kali`） |
| `--image NAME` | 直接指定任意 Docker 镜像（优先级最高） |
| `-e, --ephemeral` | 临时 Home 目录，退出不留痕 |
| `-m, --mount DIR` / `-r` | 挂载目录（可多次）；紧跟的 `-r` 将其设为只读 |
| `--no-mount` | 不挂载任何宿主机目录，持久化 home 卷保留（配 `-e` 才完全隔离） |
| `--docker-socket` | 挂载宿主 docker.sock（⚠️ **最高风险，等同宿主 root**） |
| `--port HOST:CONTAINER` | 端口映射（可重复，等价 `docker run -p`），如 `8080:8080`、`127.0.0.1:3000:3000`、`9000:9000/udp` |
| `--net MODE` | 网络模式（默认 bridge）：`off` 完全断网（`--network none`，无任何网络接口，外网/宿主端口全不可达，最安全）；`host` 共享宿主网络（`--network host`），⚠️ 无网络隔离、启动时打印风险提示；两种模式 `--port` 均无效 |
| `--no-tmux` / `--tmux-name NAME` | 关闭 / 自定义 tmux 包装 |
| `--env FILE` | 指定 `.env` 配置文件 |
| `--lang zh\|en` | 界面语言（默认按 `$LANG`/`$LC_ALL` 自动识别；`export DKAGENT_LANG=en` 持久覆盖） |
| `--dry-run` | 仅打印 `docker run` 命令，不实际启动（环境变量打码，`DKAGENT_DRY_RUN_SHOW_SECRETS=1` 显明文） |
| `-h, --help` | 显示帮助 |

**镜像优先级**：`--image` > `--profile` > 环境变量 `DKAGENT_PROFILE` > 默认 `kali`。

---

## 端口映射实战：DeepSeek Harness 开 Web 界面

DeepSeek Harness（命令 `dsh`）既有终端 CLI，也自带 Web UI。**默认安全姿势**：`dsh web` 只绑 `127.0.0.1`（官方安全默认——Web API 可执行 bash，属 RCE 级接口），仅容器内可达；不想开 Web 就直接用 CLI 形式（见要点）。要把它暴露到宿主，两种方式：

**方式一：`--port` 端口映射（✅ 推荐：保持 bridge 隔离，暴露面只有你映射的那个端口）**

```bash
# 第一次：进容器建配置（opt-in——绑 0.0.0.0 后 Web 才对容器外可见）
dkagent
mkdir -p ~/.dsh && cat > ~/.dsh/cordis.patch.yml <<'EOF'
- id: webserver
  config:
    host: 0.0.0.0
    port: 3080
EOF
# 之后每次：
dkagent --port 127.0.0.1:3080:3080 dsh web
# 浏览器打开 http://localhost:3080 即可使用；宿主侧只绑 127.0.0.1，局域网机器不可达
```

> ⚠️ **安全提示**：docker 的 `-p`/`-P` 端口映射把流量转发到**容器 eth0 的 IP**，容器内只监听 `127.0.0.1` 的服务收不到包（实测 5/5 全拒），且当前版本 dsh 的 CLI **故意拒绝 `--host 0.0.0.0`**——所以容器内的绑定必须经配置层放开。**对外暴露的边界是宿主侧的绑定地址**：写成 `--port 3080:3080`（不带 IP）时 docker 默认绑宿主的 `0.0.0.0`（实测 `docker port` 显示 `0.0.0.0:3080`，Docker Desktop 还会放行 Windows 防火墙），RCE 级 Web API 就对局域网可见；**务必写成 `--port 127.0.0.1:3080:3080`**——只有本机 loopback 可达，且 Docker Desktop（WSL2 实测）仍会把 localhost 转发到你的终端。容器内的 0.0.0.0 只是让服务在 bridge 网段内可被转发，不是对外暴露。用完建议关掉容器，或删除 patch 恢复 loopback。

**方式二：`--net host` 共享宿主网络（原生 Linux 可用；⚠️ 无网络隔离）**

```bash
dkagent --net host dsh web
# 浏览器打开 http://localhost:3080（无需 --port；保持 dsh 默认 127.0.0.1 监听，勿建 cordis patch）
```

`--network host` 下容器与宿主共享网络命名空间，容器内 `127.0.0.1` 就是宿主的 `127.0.0.1`——**保持 dsh 默认的 loopback 绑定即可**，Web UI 仅本机可达、不暴露局域网，无需任何 patch。⚠️ **勿与方式一的 cordis patch（0.0.0.0）混用**：host 模式下容器绑定即宿主绑定，0.0.0.0 会把 RCE 级 API 直接暴露到整个局域网——先删除 `~/.dsh/cordis.patch.yml` 再开。另外 host 模式本身无网络隔离：容器可访问宿主机全部端口与服务、还能直接绑定宿主端口，属高风险操作，启动时脚本会打印风险提示（见[安全模型](#安全模型一眼看懂你给了-agent-多大权限)）。

**最安全档：完全断网跑 CLI（`--net off`）**

```bash
dkagent --net off dsh --profile headless "跑一下测试"
```

`--network none` 下容器无任何网络接口——外网、宿主端口（包括 Docker Desktop 的 `host.docker.internal` 回环通道）全部不可达，只靠挂载目录干活。不开 Web、不联网的任务建议都用这档。

> ⚠️ **平台注意（实测）**：WSL2 + Docker Desktop 下 `--network host` 挂到的是 **Docker 虚拟机（docker-desktop distro，192.168.65.x）的命名空间**，不是你的 WSL2 发行版——容器内的 `127.0.0.1` 在你的终端不可达（实测 curl 全拒，即使容器只绑 127.0.0.1 也一样）。原生 Linux Docker 上则正常共享宿主 netns。Docker Desktop 环境请用方式一 `--port 127.0.0.1:...`。

要点：
- **API Key**：启动后浏览器里 Settings → Models 填入（存 `~/.dsh/.credentials.yaml`，随 Home 卷持久化），或直接写进 `~/.config/dkagent/.env`（`DEEPSEEK_API_KEY=sk-...`，dkagent 自动注入容器）
- **换端口**：改 `~/.dsh/cordis.patch.yml` 里的 `port`，与 `--port 127.0.0.1:...` 映射（方式一）一起改
- **CLI 形式**：`dkagent dsh --profile headless "跑一下测试"`（一次性任务，完全不暴露端口）；交互 TUI 用 `dsh --profile tui`
- 加 `-e`（用完即焚）跑 Web UI 也完全没问题，关掉容器不留任何状态（临时 Home 不保留 patch，需每次重建）

---

## 备用运行方式 (Docker Compose)

不用 CLI 也可 `docker compose run --rm` 直接启动，三种模式共享同一个持久化 Home 卷（与 CLI 完全互通）：`agent-shell`（仅 Home，🟢）/ `agent-isolated`（无挂载用完即焚，🟢）/ `agent-sandboxed`（Home + 挂载 workspace，🟡）。切换镜像：`DKAGENT_IMAGE=dkagent-slim docker compose run --rm agent-shell`。

---

## 桌面端 Agent 连接

桌面端 Agent（如智谱 ZCode）同样可以用这个环境。ZCode 支持**直连运行中的容器**（无需开放端口）：容器名即 `dkagent-<项目目录名>`（如 `dkagent-my-project`），容器内用户 `kali`。仅支持 SSH 的 Agent，可在启动时用 `--port` 把容器内服务端口映射到宿主机后直接连接（如 `dkagent --port 127.0.0.1:2222:22 claude`——加 `127.0.0.1:` 前缀只本机可达，不带 IP 则局域网可见；容器内需有对应服务在监听），无需隧道。

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
- [x] 断网档位（`--net off`，`--network none` 完全断网，实测可阻断 Docker Desktop 的 `host.docker.internal` 回环通道） ｜ [ ] 出站限制档位（`--net strict`：默认拒绝 + 白名单；注意若策略是"只断外网、放行内网"，Docker Desktop 网关地址仍可达宿主回环，须显式处理）
- [x] **容器端口映射**（`--port`，映射容器内任意端口到宿主机，供外部 / 桌面 Agent 通信）

---

## 许可证

[MIT](LICENSE)
