# dkagent 多目录挂载功能设计

## 概述

为 `dkagent` CLI 工具添加多目录挂载和只读挂载能力，统一所有挂载模式为子目录映射，并更新安全风险矩阵。

## 需求

1. `-m` 支持多次指定（`-m ./a -m ./b`）和空格分隔（`-m "./a ./b"`）
2. 所有挂载统一映射为 `/home/kali/workspace/<basename>` 子目录（包括 PWD 默认模式）
3. 新增 `-r`/`--readonly` 选项，以只读方式挂载前一个 `-m` 指定的目录
4. 同名目录冲突检测
5. 更新安全风险矩阵，反映挂载 + Home 持久化的组合风险

## 设计

### 1. 参数解析改造

`MOUNT_DIR`（单字符串）替换为 `MOUNT_DIRS`（数组），每个元素记录目录路径和读写模式。

数据结构：

```
MOUNT_DIRS=()       # 每个元素: "/path/to/dir:rw" 或 "/path/to/dir:ro"
```

解析逻辑：

- `-m` 后的参数按空格拆分，逐个加入 `MOUNT_DIRS`，默认 `:rw`
- `-r`/`--readonly` 将 `MOUNT_DIRS` 最后一个元素的 `:rw` 改为 `:ro`
- 若 `-r` 时 `MOUNT_DIRS` 为空，报错退出
- `--no-mount` 保持不变，清空 `MOUNT_DIRS`
- PWD 模式（无 `-m` 也无 `--no-mount`）将 `$(pwd)` 加入 `MOUNT_DIRS`，默认 `:rw`

### 2. 挂载路径构建

统一规则：宿主路径 `/path/to/my-project` -> 容器路径 `/home/kali/workspace/my-project`

```
for entry in "${MOUNT_DIRS[@]}"; do
  abs_path = 转为绝对路径
  dir_name = basename(abs_path)
  access_mode = ro 或 rw
  DOCKER_ARGS+=("-v" "${abs_path}:${CONTAINER_WORKSPACE}/${dir_name}:${access_mode}")
done
```

工作目录 `-w` 固定设为 `/home/kali/workspace`。

### 3. 只读挂载选项

- `-r`/`--readonly`：紧跟在某个 `-m` 之后使用，将前一个 `-m` 目录设为只读
- Docker 挂载时追加 `:ro` 标志

示例：

```bash
# 原始项目只读参考，副本目录可读写
dkagent -m ./my-project -r -m ./workspace/my-copy

# 容器内：
#   /home/kali/workspace/my-project  (只读)
#   /home/kali/workspace/my-copy     (可读写)
```

### 4. 安全风险矩阵

风险等级由**是否挂载** + **挂载读写模式** + **Home 是否持久化**三个维度共同决定：

| 组合 | 风险 | 说明 |
|:---|:---|:---|
| `--no-mount` + `-e` | 无 (🟢) | 完全隔离，用完即焚 |
| `--no-mount`（默认） | 低 (🟢) | 隔离宿主文件，持久化 home 有配置被改风险 |
| 全部只读挂载 + `-e` | 低 (🟢) | Agent 只能读取，无法修改宿主文件，退出不留痕 |
| 全部只读挂载（默认） | 中低 (🟡) | Agent 只能读取，但持久化 home 有配置被改风险 |
| 有可写挂载 + `-e` | 中 (🟡) | Agent 可操作挂载目录，但退出不留痕 |
| 有可写挂载（默认） | 高 (🔴) | Agent 可操作挂载目录 + 持久化 home 可留后门 |

### 5. 输出信息

根据实际挂载情况动态打印：

- 多目录时逐行列出映射关系及读写模式
- 单目录时一行显示
- 安全风险标签按上述矩阵匹配

示例输出：

```
🔴 安全风险: 映射级别 (2 个目录挂载到 /home/kali/workspace/)
  → /path/to/project-a (可读写)
  → /path/to/lib-shared (只读)
```

### 6. 错误处理

| 场景 | 行为 |
|:---|:---|
| 两个目录同名（basename 冲突） | 报错退出，提示目录名冲突 |
| 目录不存在 | 报错退出（保持现有行为） |
| `-r` 没有 preceding `-m` | 报错退出，提示 `-r/--readonly 必须跟在 -m 之后` |
| `-m` 空参数 | 报错退出，提示缺少目录路径 |

## 改动范围

| 文件 | 改动内容 |
|:---|:---|
| `dkagent` | 参数解析、MOUNT_DIRS 数组、挂载构建、输出信息、帮助文本 |
| `README.md` | 安全矩阵表格、用法示例、选项说明 |

不涉及 `Dockerfile`、`docker-compose.yaml`、`install.sh`。
