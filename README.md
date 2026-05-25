# AI Agent Docker 运行环境 & `dkagent` CLI 工具

本项目提供了一个高度可定制、安全且隔离的 Docker 环境，专门为运行如 Claude Code, Gemini CLI, Pi, Codex, OpenCode 等 AI Agent CLI 工具而设计。

基于 **Kali Linux** 构建，内置自动补全、Playwright 浏览器等全套 AI 辅助开发依赖。

通过配套的 `dkagent` CLI 工具，你可以**在宿主机的任意目录下一键拉起容器**处理代码，同时自由掌控安全隔离级别。

---

## 🔒 核心安全模型与风险等级

AI Agent 在执行开发任务时拥有强大的文件操作系统权限。为了防止 Agent 在遭遇恶性提示词或误判时删除、清空宿主机上的重要文件（如 `rm -rf` 风险），本项目将运行模式划分为三个明确的安全等级。

```
  安全性 ▲
        │
   🟢 隔离级别 (Isolated) - 使用 --no-mount / docker compose run agent-isolated
        │  Agent 完全运行在 Docker 虚拟沙盒中，绝对无法触碰、感知到任何宿主机文件。零文件风险。
        │
   🟡 沙盒级别 (Sandboxed) - 使用 -m <副本目录> / docker compose run agent-sandboxed
        │  先手动复制你需要处理的代码或文件到指定工作目录（如 ./workspace），再以此路径启动。
        │  Agent 只能折腾副本，原始项目文件绝对安全。
        │
   🔴 映射级别 (Mounted) - 直接运行 (默认挂载 PWD)
        │  最方便的日常编码方式，自动将当前所在的终端路径映射进容器。
        │  ⚠️ 警告: Agent 对当前项目文件具有完整的读、写、删权限。请确保指令绝对受控。
        │
        └────────────────────────────────────────────────────────▶ 便捷性
```

### 完整运行模式安全对比

| 运行方式 | Home 目录类型 | 宿主工作目录挂载 | 数据丢失风险 | 适合使用场景 |
| :--- | :--- | :--- | :--- | :--- |
| **`dkagent <agent>`** | 🏠 持久化卷 | 🔴 **直接挂载当前 PWD** | **高 (🔴)** | 信任的 Agent，日常高效编码 |
| **`dkagent -e <agent>`** | 🧊 用完即焚 | 🔴 **直接挂载当前 PWD** | **高 (🔴)** | 需纯净容器环境的快速编码 |
| **`dkagent -m ./path`** | 🏠 持久化卷 | 🟡 **挂载副本目录** | **中 (🟡)** | 不完全信任的 Agent 调试任务 |
| **`dkagent -e -m ./path`** | 🧊 用完即焚 | 🟡 **挂载副本目录** | **中 (🟡)** | 针对未知安全隐患的 Agent 评估 |
| **`dkagent --no-mount`** | 🏠 持久化卷 | 🟢 **不挂载宿主目录** | **低 (🟢)** | 调试或配置容器内环境（如 Oh-my-zsh） |
| **`dkagent -e --no-mount`** | 🧊 用完即焚 | 🟢 **不挂载宿主目录** | **无 (🟢)** | 纯粹的沙盒命令测试/玩耍 |

> [!CAUTION]
> **关于 Home 卷持久化的安全提示 (🏠)**:
> 持久化 Home 卷（`agent_docker_kali-home`）会保留你的 Oh-My-Zsh 配置、命令历史及 Agent 的会话 Session 等。如果 Agent 被外部恶意控制，理论上可能通过修改你持久化的 `.zshrc` 来埋下后门。若对运行安全性有极端要求，推荐加 `-e` (用完即焚) 选项。

---

## 🚀 快速开始

### 1. 基础配置与镜像构建

首先，在项目根目录下创建一个全局的 `.env` 环境变量配置文件，用来保存你的各种大模型 API Key（注意：`.env` 文件已被 git 忽略，切勿提交！）：

```env
# .env 文件样例
ANTHROPIC_API_KEY=sk-ant-xxx...
GEMINI_API_KEY=AIzaSy...
OPENAI_API_KEY=sk-xxx...
OPENROUTER_API_KEY=sk-or-v1-xxx...
```

接着，编译并构建我们的 Agent 基础镜像：

```bash
docker compose build
```

---

### 2. 安装 `dkagent` CLI 工具

本工具提供了自动安装/卸载脚本，可以将 `dkagent` 命令软链接至系统 PATH，并自动整理配置文件：

```bash
# 给予安装脚本执行权限并运行
chmod +x install.sh
./install.sh
```

**安装脚本将自动执行以下操作：**
1. 自动设置 `dkagent` 执行权限。
2. 在 `/usr/local/bin/dkagent` 创建软链接。
3. 创建全局配置目录 `~/.config/dkagent/`，并将你项目下的 `.env` 配置文件备份至该目录下（若存在），便于在宿主机任意路径下都能完美自动加载 API Keys。

> [!TIP]
> **卸载命令**：如需完全清理软链接和配置，直接运行 `./install.sh remove` 即可。

---

## 🛠️ `dkagent` 命令行使用说明

安装完成后，你无需再手动 `cd` 到本项目的目录，直接在宿主机的任何文件夹下，就能直接拉起容器！

### 1. 基础命令结构

```bash
dkagent [选项] [agent名称] [附加参数...]
```

### 2. 常用操作指令

```bash
# 进入交互式 Kali 命令行 (默认挂载当前目录 PWD 到 /home/kali/workspace)
dkagent

# 直接唤醒容器内的 Claude Code 并自动处理当前目录下的文件
dkagent claude

# 使用临时 Home 卷（用完即焚）并唤醒 Claude
dkagent -e claude

# 使用沙盒副本工作流（安全级别：🟡）
# 先将项目复制到指定文件夹
cp -r ./my-project ./workspace/my-project-copy
# 挂载该指定副本夹并拉起 Gemini 
dkagent -m ./workspace/my-project-copy gemini
# 处理完成后从副本文件夹取回修改，并安全清理

# 纯净模式，不挂载任何宿主机物理文件目录，仅进去容器玩耍/配置
dkagent --no-mount
```

### 3. 可选参数列表

* `-e`, `--ephemeral`: 🧊 使用临时 Home 目录，退出后不留痕迹。
* `-m`, `--mount DIR`: 📁 挂载指定的本地目录到容器的 `/home/kali/workspace`（取代当前 PWD）。
* `--no-mount`: 🟢 完全不挂载任何宿主机物理目录（零宿主数据风险）。
* `--env FILE`: 手动指定其他 `.env` 秘钥配置文件。
* `--dry-run`: 🔍 仅打印将要运行的 `docker run` 命令大串，不实际建立并进入容器。
* `-h`, `--help`: 显示内置使用帮助。

---

## 📦 备用运行方式 (Docker Compose)

如果你不想使用 `dkagent` 快捷命令，也可以直接在项目根目录下通过原生的 `docker compose` 工具链启动。

以下是全新的安全命名映射：

### 1. 🏠 调试/Shell 模式 (`agent-shell`)
仅挂载持久化 Home 卷（保留各种 shell 美化及配置），不挂载任何物理文件夹。安全等级：🟢 
```bash
docker compose run --rm agent-shell
```

### 2. 🧊 纯净/隔离模式 (`agent-isolated`)
无任何 Volume 挂载，每次启动都是干净利落的空系统，用完即焚。安全等级：🟢
```bash
docker compose run --rm agent-isolated
```

### 3. 📂 沙盒副本模式 (`agent-sandboxed`)
挂载持久化 Home 卷，并且将本地的 `./workspace` 文件夹挂载到容器内的 `/home/kali/workspace`，直接工作。安全等级：🟡
```bash
docker compose run --rm agent-sandboxed
```

---

## 📁 目录结构

* `Dockerfile`: Kali 基础开发环境构建配置。
* `docker-compose.yaml`: 各类组合模式服务定义。
* `dkagent`: 核心 bash 命令。
* `install.sh`: 一键配置、软链与安装器。
* `workspace/`: 预设的本地沙箱数据隔离缓存带。
