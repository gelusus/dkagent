# AGENTS.md

## 项目概述

dkagent — 基于 Docker 的 AI Agent CLI 统一运行入口。核心是一个 bash 脚本（约 1000 行），把 Docker 隔离能力编排成命令行：一行命令拉起容器，内置 Claude/Gemini/Codex/Pi/OpenCode，支持逐目录挂载控制、多镜像 profile、tmux 断线重连、多机接力同步（`dkagent sync`）。

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
- **配置读取模式**：多路径搜索数组（`ENV_SEARCH_PATHS` / `PROFILE_CONF_PATHS` / `SYNC_PEERS_PATHS`）+ 逐行解析函数。新增配置文件仿照 `load_custom_profiles`。
- **sync 子命令设计原则**：完全手动、绝不与 docker run/tmux 耦合；遵循 rsync 哲学（不设默认 exclude/backup）；默认 dry-run 预览 + 用户确认；内置重试循环 + `--partial` 断点续传。
- **容器名/tmux 会话名**：默认 `dkagent-<basename($PWD)>`，重名自动加 `_2` `_3` 后缀；特殊字符替换为 `_`。escape hatch 用环境变量（`DKAGENT_NO_CONTAINER_NAME=1` 等）。
- **安全**：peers 配置含 SSH URL 要 `chmod 600`；peer URL 的 port 必须校验为纯数字（防注入）。

## 平台约束

- bash 4+（关联数组）；macOS 需 `brew install bash`
- 主要运行环境：Linux / WSL2 + Docker Desktop
- 容器内用户固定 `kali`（uid 1000），持久化卷 `agent_docker_kali-home`

## 已知坑

- **rsync 3.4**：`--numeric-owner` 已改名 `--numeric-ids`（旧名报 unknown option）
- **WSL2 + Docker Desktop**：`docker build` 可能报 `docker-credential-desktop.exe`，用 `docker --config /tmp/empty-docker-cfg build` 绕过
- **EXTRA_ARGS 字符串拼接**（dkagent 735 行附近）：`${AGENT_CMD} ${EXTRA_ARGS[*]:-}` 会丢参数边界——**新代码不要复用这个模式**，自己维护参数数组
- `dkagent-sync` 镜像 `ENTRYPOINT ["rsync"]`：`docker run dkagent-sync ARG` 等价 `rsync ARG`，参数里不要再写 `rsync`

## 文档规则

- **不要在文档/示例/help 里放真实数据**（真实 peer 名、IP、路径、用户名）——用 `laptop`、`~/projects/myproject` 这类通用占位符
- README 修改必须中英两份同步
- 注释用中文，代码风格跟随现有脚本
