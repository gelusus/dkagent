# AI Agent Docker 运行环境

本项目提供了一个高度可定制、安全且隔离的 Docker 环境，专为运行如 Claude Code, Gemini CLI, Pi, Codex 等 AI Agent 设计。基于 Kali Linux 构建，支持持久化、用完即焚、安全执行三种运行模式。

## 目录结构说明

- `Dockerfile`: 构建基础镜像的指令。
- `docker compose.yaml`: 服务定义，用于一键启动不同场景的容器。
- `.env`: (请手动创建) 存放你的 API Keys 环境变量。**切勿将此文件提交到版本控制系统。**

## 快速开始

1.  **设置环境变量**: 在根目录下创建一个 `.env` 文件，并填入你的 API Keys：
    ```env
    ANTHROPIC_API_KEY=sk-ant-...
    GEMINI_API_KEY=AIzaSy...
    OPENAI_API_KEY=sk-...
    ```

2.  **构建镜像**:
    ```bash
    docker compose build
    ```

3.  **启动容器**:
    ```bash
    # 持久化模式 (日常使用)
    docker compose run --rm agent-persistent

    # 用完即焚模式
    docker compose run --rm agent-ephemeral
    ```

## 使用场景指南

### 场景 1: 持久化模式 (日常推荐)

使用 Docker named volume 挂载 `/home/kali`。首次启动时自动从镜像复制完整的 home 目录内容（oh-my-zsh、Claude、Playwright 等）到 volume 中，之后所有配置更改都会持久保留。

```bash
docker compose run --rm agent-persistent
```

**重置持久化数据**（恢复到镜像出厂状态）：
```bash
docker volume rm agent_docker_kali-home
```

### 场景 2: 用完即焚模式

不挂载任何 volume，每次启动都是镜像内的干净环境。退出后容器自动销毁。

```bash
docker compose run --rm agent-ephemeral
```

### 场景 3: 安全执行模式 (不信任 Agent 时使用)

只挂载 `workspace` 目录，Agent 无法触碰持久化的 home 配置。Agent 在 workspace 中的修改会实时同步到宿主机，请**务必先将需要处理的文件复制到 `workspace` 目录**，避免 agent 直接操作原始代码。

```bash
# 1. 先将要处理的文件复制到 workspace (保留原始代码安全)
cp -r ./my-project ./workspace/my-project

# 2. 启动安全模式容器
docker compose run --rm agent-safe

# 3. 退出后，从 workspace 取回结果
cp -r ./workspace/my-project ./my-project-result

# 4. 清理 workspace
rm -rf ./workspace/my-project
```

## 持久化 Volume 备份与恢复

### 备份

```bash
docker run --rm \
  -v agent_docker_kali-home:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/kali-home-backup.tar.gz -C /data .
```

### 恢复

```bash
# 删除旧 volume 并重新创建
docker volume rm agent_docker_kali-home
docker volume create agent_docker_kali-home

# 从备份恢复
docker run --rm \
  -v agent_docker_kali-home:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/kali-home-backup.tar.gz -C /data
```

## 自定义镜像默认配置

如果需要修改镜像内的默认配置（如预装插件、skills、自定义 .zshrc 等）：

1.  修改 `Dockerfile`，或在构建后进入容器修改配置
2.  如果想从镜像中提取配置到宿主机备份：
    ```bash
    docker create --name tmp-config my-kali-agent
    docker cp tmp-config:/home/kali/. ./backup/
    docker rm tmp-config
    ```
3.  修改完后将文件放回构建上下文，重新 `docker compose build`
