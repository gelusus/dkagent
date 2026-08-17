# AGENTS.md

## 项目概述

dkagent — 基于 Docker 的 AI Agent CLI 统一运行入口。核心是一个 bash 脚本（约 1000 行），把 Docker 隔离能力编排成命令行：一行命令拉起容器，内置 Claude/Antigravity（`agy`）/Codex/Pi/OpenCode/DeepSeek Harness（`dsh`），支持逐目录挂载控制、多镜像 profile、tmux 断线重连、多机接力同步（`dkagent sync`）。

## 关键文件

| 文件 | 作用 |
|---|---|
| `dkagent` | 核心脚本（参数解析 + docker run 组装 + sync 子命令），所有改动都在这里 |
| `Dockerfile` | 默认 kali profile 镜像 |
| `dockerfiles/Dockerfile.slim` | slim profile（Debian 精简） |
| `dockerfiles/Dockerfile.sync` | `dkagent-sync` 镜像（alpine + rsync + ssh，跨机同步用） |
| `docker-compose.yaml` | 备用 compose 运行模式 |
| `install.sh` | 安装/卸载（有**独立一套** MSG_ZH/MSG_EN，与主脚本不共享） |
| `README.md` / `README.en.md` | 文档（中文主版 + 英文同步版） |

## 开发命令

```bash
bash -n dkagent          # 语法检查（唯一的"测试"，无测试框架）
bash -n install.sh
dkagent --dry-run        # 打印 docker run 命令不实际启动（功能验证首选）
dkagent sync --help      # sync 子命令帮助
```

## 架构与约定

- **单脚本无框架**：没有 getopts，参数解析是手写 `while + case`。**新子命令（如 `sync`）必须在主参数解析 while 循环之前加前置路由**，否则会被 tmux 块（`exec tmux new-session`）包装或被当作 AGENT_CMD 吞掉。
- **i18n 双表必须同步**：文案加在 `MSG_ZH` 和 `MSG_EN` 两个关联数组（key 完全对齐），调用 `msg <key> [args...]`。install.sh 有独立副本。
- **配置读取模式**：多路径搜索数组（`ENV_SEARCH_PATHS` / `PROFILE_CONF_PATHS` / `SYNC_PEERS_PATHS`）+ 逐行解析函数。新增配置文件仿照 `load_custom_profiles`。**⚠️ 脚本目录回退已移除**（防 repo 被种植 `.env`/`profiles`/`peers` 劫持后续运行）——搜索路径只含 `$HOME/.config/dkagent/` 与 `$DKAGENT_ENV`。
- **sync 子命令设计原则**：完全手动、绝不与 docker run/tmux 耦合；遵循 rsync 哲学（不设默认 exclude/backup）；默认 dry-run 预览 + 用户确认；内置重试循环 + `--partial` 断点续传。
- **容器名/tmux 会话名**：默认 `dkagent-<basename($PWD)>`，重名自动加 `_2` `_3` 后缀；特殊字符替换为 `_`。escape hatch 用环境变量（`DKAGENT_NO_CONTAINER_NAME=1` 等）。
- **安全**：peers 配置含 SSH URL 要 `chmod 600`（运行时会 stat 告警）；peer URL 的 port 必须校验为纯数字，**user/host/远端路径必须过字符白名单**（user/host `[A-Za-z0-9._-]`；路径 `[A-Za-z0-9/._~-]` + 全部非 ASCII 字节 0x80-0xFF，即放行中文等 UTF-8 多字节字符——shell 元字符/控制字符均为 ASCII，放行高字节不扩大注入面，防经 rsync 远端 shell 注入）；`dkagent-sync` 镜像指纹存 `~/.config/dkagent/sync-image.id`，替换即拒（`check_sync_image`）；sync 容器内只挂 `ssh -G` 解析出的身份文件或 SSH agent socket，**勿整目录挂 `~/.ssh`**；环境变量一律经临时 `--env-file`（0600 用后即删）传递，dry-run 默认打码（`DKAGENT_DRY_RUN_SHOW_SECRETS=1` 显明文）。

## 平台约束

- bash 4+（关联数组）；macOS 需 `brew install bash`
- 主要运行环境：Linux / WSL2 + Docker Desktop
- 容器内用户固定 `kali`（uid 1000），持久化卷 `agent_docker_kali-home`

## 已知坑

- **rsync 3.4**：`--numeric-owner` 已改名 `--numeric-ids`（旧名报 unknown option）
- **WSL2 + Docker Desktop**：`docker build` 可能报 `docker-credential-desktop.exe`，用 `docker --config /tmp/empty-docker-cfg build` 绕过
- **WSL2 + Docker Desktop**：`--network host` 挂到 Docker 虚拟机（docker-desktop distro，192.168.65.x）的 netns，容器内 localhost 在用户发行版不可达（实测）；loopback 服务需映射时用 `--port` + 容器内绑 0.0.0.0
- **Docker Desktop 宿主回环通道（实测）**：默认注入 `host.docker.internal`（192.168.65.254 网关），bridge 容器可触达宿主/物理机 **loopback-only** 服务（Windows 127.0.0.1 与 WSL2 发行版 127.0.0.1 监听均被触达；反而 0.0.0.0 绑定的被 Windows 防火墙拦）——bridge 隔离**不保护**宿主 loopback 端口。原生 Linux 无此注入。`--net off`（`--network none`）可彻底阻断（实测解析都不通）
- **`--net` 仅 host/off 两档**：host 与 `--docker-socket` 同级（高风险，组装 docker run 时**必须**打印 `msg warn_net_host_risk`，不能只写文档）；off = `--network none` 完全断网（最安全档）；两档下 `--port` 均无效，需打印对应提示
- **agent 命令用 `zsh -f -c`**（跳过全部用户/全局启动文件，防持久化 Home 卷 `.zshenv` 后门在 `--no-mount` 等模式下执行）；交互 shell（无 agent 参数）仍读 `.zshrc`，属已知权衡
- **sync 镜像重建需重新信任**：升级 `dkagent-sync` 后指纹不匹配会拒绝同步，需删 `~/.config/dkagent/sync-image.id`（README 已写）；sync_volume 的身份文件解析依赖 `ssh -G`（openssh ≥ 7.3）
- **dsh web 默认绑 127.0.0.1 且 CLI 拒绝 `--host 0.0.0.0`**（RCE 级 API 安全限制）；要 `--port` 映射须用户手动建 `~/.dsh/cordis.patch.yml` 绑 0.0.0.0（opt-in）——**勿在镜像里默认预置 0.0.0.0 绑定**。**文档/帮助示例必须写 `--port 127.0.0.1:3080:3080`**：不带 IP 的 `--port 3080:3080` 宿主侧默认绑 0.0.0.0（实测 `docker port` 显示 `0.0.0.0:3080` + `[::]:3080`，Docker Desktop 还放行 Windows 防火墙「Docker Desktop Backend」规则）→ RCE 级 API 对局域网可见；加 `127.0.0.1:` 前缀后只绑 loopback，且 Docker Desktop 仍把 localhost 转发到用户终端（WSL2 实测可用）。`--net host`（仅原生 Linux）保持 dsh 默认 127.0.0.1 监听即可直达、**勿建 cordis patch**（host 模式下容器绑定=宿主绑定，0.0.0.0 会直接把 API 暴露到局域网）
- **EXTRA_ARGS 字符串拼接**（dkagent 735 行附近）：`${AGENT_CMD} ${EXTRA_ARGS[*]:-}` 会丢参数边界——**新代码不要复用这个模式**，自己维护参数数组
- `dkagent-sync` 镜像 `ENTRYPOINT ["rsync"]`：`docker run dkagent-sync ARG` 等价 `rsync ARG`，参数里不要再写 `rsync`

## 安全意识（本项目面向安全场景，写代码与文档必须带安全思维）

- 本工具运行于安全研究场景，任何对外暴露的端口都是攻击面——**示例、文档、默认配置一律采用最安全姿势**。
- 历史教训（本仓库真实发生过）：示例曾把 RCE 级接口（dsh web）用裸 `--port 3080:3080` 发布（宿主侧默认绑 0.0.0.0，实测局域网可见，Docker Desktop 还放行 Windows 防火墙），文档甚至把「局域网机器同理」写成功能卖点；`--net host` 与 cordis 0.0.0.0 patch 混用会让容器内绑定直接变成宿主绑定。此后规则：
  - 端口映射示例必须写 `127.0.0.1:<宿主端口>:<容器端口>`；除非刻意演示暴露给局域网，且必须同时标注风险；
  - 未实测的结论与平台不得写进文档（如 Docker Desktop 的 macOS 行为未实测，就不要断言 macOS）；
  - 文档中的「局域网可见」只能出现在警告语境，不得作为宣传用语；
  - 新增示例前先自问：照这条命令敲下去，攻击面是什么。

## 文档规则

- **不要在文档/示例/help 里放真实数据**（真实 peer 名、IP、路径、用户名）——用 `laptop`、`~/projects/myproject` 这类通用占位符
- README 修改必须中英两份同步
- 注释用中文，代码风格跟随现有脚本
