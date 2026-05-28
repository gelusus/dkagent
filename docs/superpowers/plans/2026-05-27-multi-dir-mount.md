# dkagent 多目录挂载功能 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 dkagent CLI 添加多目录挂载和只读挂载能力，统一所有挂载模式为子目录映射。

**Architecture:** 改造 `dkagent` bash 脚本的参数解析和挂载构建逻辑。将单字符串 `MOUNT_DIR` 替换为数组 `MOUNT_DIRS`，每个元素包含路径和读写模式。新增 `-r`/`--readonly` 选项。同步更新 `README.md`。

**Tech Stack:** Bash 4+, Docker CLI

---

### Task 1: 改造参数解析 — 引入 MOUNT_DIRS 数组和 -r 选项

**Files:**
- Modify: `dkagent:105-162`（参数解析 section）
- Modify: `dkagent:107-113`（变量声明 section）

- [ ] **Step 1: 替换变量声明**

将 `dkagent:107-113` 的变量声明从：

```bash
USE_PERSISTENT_HOME=true
MOUNT_MODE="PWD" # PWD, CUSTOM, NONE
MOUNT_DIR=""
CUSTOM_ENV=""
DRY_RUN=false
AGENT_CMD=""
EXTRA_ARGS=()
```

替换为：

```bash
USE_PERSISTENT_HOME=true
MOUNT_MODE="PWD" # PWD, CUSTOM, NONE
MOUNT_DIRS=()    # 每个元素: "/path/to/dir:rw" 或 "/path/to/dir:ro"
CUSTOM_ENV=""
DRY_RUN=false
AGENT_CMD=""
EXTRA_ARGS=()
```

- [ ] **Step 2: 替换参数解析逻辑**

将 `dkagent:115-162` 的整个 `while` 循环替换为：

```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -e|--ephemeral)
            USE_PERSISTENT_HOME=false
            shift
            ;;
        -m|--mount)
            if [[ $# -lt 2 ]]; then
                echo "❌ 错误: -m/--mount 选项需要提供目录参数！" >&2
                exit 1
            fi
            MOUNT_MODE="CUSTOM"
            # 按空格拆分，支持 -m "./a ./b" 和 -m ./a 两种形式
            for dir in $2; do
                MOUNT_DIRS+=("$(cd "$dir" 2>/dev/null && pwd || echo "$dir"):rw")
            done
            shift 2
            ;;
        -r|--readonly)
            if [[ ${#MOUNT_DIRS[@]} -eq 0 ]]; then
                echo "❌ 错误: -r/--readonly 必须跟在 -m 之后使用！" >&2
                exit 1
            fi
            # 将最后一个元素的 :rw 改为 :ro
            last_idx=$(( ${#MOUNT_DIRS[@]} - 1 ))
            last_entry="${MOUNT_DIRS[$last_idx]}"
            MOUNT_DIRS[$last_idx]="${last_entry%:rw}:ro"
            shift
            ;;
        --no-mount)
            MOUNT_MODE="NONE"
            MOUNT_DIRS=()
            shift
            ;;
        --env)
            if [[ $# -lt 2 ]]; then
                echo "❌ 错误: --env 选项需要提供文件路径！" >&2
                exit 1
            fi
            CUSTOM_ENV="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "❌ 未知选项: $1" >&2
            echo "请运行 'dkagent --help' 查看可用选项" >&2
            exit 1
            ;;
        *)
            AGENT_CMD="$1"
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
    esac
done
```

- [ ] **Step 3: 用 --dry-run 验证参数解析**

```bash
mkdir -p /tmp/a /tmp/b
dkagent --dry-run -m /tmp/a -m /tmp/b
```

Expected: 输出的 docker run 命令中包含 `-v /tmp/a:/home/kali/workspace/a:rw -v /tmp/b:/home/kali/workspace/b:rw`

- [ ] **Step 4: 用 --dry-run 验证只读选项**

```bash
dkagent --dry-run -m /tmp/a -r -m /tmp/b
```

Expected: 输出中包含 `-v /tmp/a:/home/kali/workspace/a:ro -v /tmp/b:/home/kali/workspace/b:rw`

- [ ] **Step 5: 验证 -r 在没有 -m 时报错**

```bash
dkagent --dry-run -r
```

Expected: `❌ 错误: -r/--readonly 必须跟在 -m 之后使用！`

---

### Task 2: 改造挂载路径构建 — 子目录映射和冲突检测

**Files:**
- Modify: `dkagent:210-230`（挂载工作目录 section）

- [ ] **Step 1: 替换挂载构建逻辑**

将 `dkagent` 中 "# 2. 挂载工作目录及工作目录设定" section（约第 210-230 行）替换为：

```bash
# 2. 挂载工作目录及工作目录设定
if [[ "$MOUNT_MODE" == "PWD" ]]; then
    MOUNT_DIRS=("$(pwd):rw")
elif [[ "$MOUNT_MODE" == "NONE" ]]; then
    MOUNT_DIRS=()
fi

# basename 冲突检测
declare -A SEEN_BASENAMES=()
for entry in "${MOUNT_DIRS[@]}"; do
    dir_path="${entry%:*}"
    base_name="$(basename "$dir_path")"
    if [[ -n "${SEEN_BASENAMES[$base_name]:-}" ]]; then
        echo "❌ 错误: 目录名冲突！多个路径的 basename 均为 '${base_name}':" >&2
        echo "  - ${SEEN_BASENAMES[$base_name]}" >&2
        echo "  - ${dir_path}" >&2
        exit 1
    fi
    SEEN_BASENAMES["$base_name"]="$dir_path"
done

# 目录存在性检查 + 挂载构建
if [[ ${#MOUNT_DIRS[@]} -gt 0 ]]; then
    DOCKER_ARGS+=("-w" "${CONTAINER_WORKSPACE}")
    for entry in "${MOUNT_DIRS[@]}"; do
        dir_path="${entry%:*}"
        access="${entry##*:}"
        base_name="$(basename "$dir_path")"
        if [[ ! -d "$dir_path" ]]; then
            echo "❌ 错误: 指定的挂载目录不存在: $dir_path" >&2
            exit 1
        fi
        abs_path="$(cd "$dir_path" 2>/dev/null && pwd)"
        DOCKER_ARGS+=("-v" "${abs_path}:${CONTAINER_WORKSPACE}/${base_name}:${access}")
    done
else
    DOCKER_ARGS+=("-w" "/home/kali")
fi
```

- [ ] **Step 2: 用 --dry-run 验证 PWD 子目录映射**

```bash
cd /tmp && dkagent --dry-run
```

Expected: 输出中包含 `-v /tmp:/home/kali/workspace/tmp:rw -w /home/kali/workspace`

- [ ] **Step 3: 用 --dry-run 验证 basename 冲突检测**

```bash
mkdir -p /tmp/x/project /tmp/y/project
dkagent --dry-run -m /tmp/x/project -m /tmp/y/project
```

Expected: `❌ 错误: 目录名冲突！多个路径的 basename 均为 'project':`

- [ ] **Step 4: 验证 --no-mount 模式**

```bash
dkagent --dry-run --no-mount
```

Expected: 输出中无 `-v` 挂载参数，`-w /home/kali`

---

### Task 3: 改造输出信息 — 动态安全风险标签

**Files:**
- Modify: `dkagent`（挂载构建逻辑后，紧跟输出信息）

- [ ] **Step 1: 在挂载构建逻辑之后添加安全风险输出**

在 Task 2 的挂载构建代码块末尾（`else DOCKER_ARGS+=("-w" "/home/kali") fi` 之后）添加：

```bash
# 3. 打印安全风险信息
HAS_WRITABLE=false
HAS_READONLY=false
for entry in "${MOUNT_DIRS[@]}"; do
    access="${entry##*:}"
    if [[ "$access" == "rw" ]]; then
        HAS_WRITABLE=true
    else
        HAS_READONLY=true
    fi
done

if [[ ${#MOUNT_DIRS[@]} -eq 0 ]]; then
    if [[ "$USE_PERSISTENT_HOME" == true ]]; then
        echo "🟢 安全风险: 隔离级别 (未挂载任何宿主机目录，持久化 home 有配置被改风险)"
    else
        echo "🟢 安全风险: 隔离级别 (完全隔离，用完即焚)"
    fi
elif [[ "$HAS_WRITABLE" == false ]]; then
    echo "🟡 安全风险: 只读挂载 (${#MOUNT_DIRS[@]} 个目录以只读方式挂载到 ${CONTAINER_WORKSPACE}/)"
    for entry in "${MOUNT_DIRS[@]}"; do
        dir_path="${entry%:*}"
        abs_path="$(cd "$dir_path" 2>/dev/null && pwd)"
        echo "  → ${abs_path} (只读)"
    done
else
    echo "🔴 安全风险: 映射级别 (${#MOUNT_DIRS[@]} 个目录挂载到 ${CONTAINER_WORKSPACE}/)"
    for entry in "${MOUNT_DIRS[@]}"; do
        dir_path="${entry%:*}"
        access="${entry##*:}"
        abs_path="$(cd "$dir_path" 2>/dev/null && pwd)"
        if [[ "$access" == "ro" ]]; then
            echo "  → ${abs_path} (只读)"
        else
            echo "  → ${abs_path} (可读写)"
        fi
    done
fi
```

- [ ] **Step 2: 删除旧的输出信息**

确认 `dkagent` 中无残留的旧 echo 行（原 `echo "🔴 安全风险..."` 、`echo "🟡 安全风险..."` 、`echo "🟢 安全风险..."` 三行已全部移除）。

- [ ] **Step 3: 验证多目录输出**

```bash
mkdir -p /tmp/project-a /tmp/lib-shared
dkagent --dry-run -m /tmp/project-a -r -m /tmp/lib-shared
```

Expected: 输出包含：
```
🔴 安全风险: 映射级别 (2 个目录挂载到 /home/kali/workspace/)
  → /tmp/project-a (只读)
  → /tmp/lib-shared (可读写)
```

- [ ] **Step 4: 验证全只读输出**

```bash
dkagent --dry-run -m /tmp/project-a -r -m /tmp/lib-shared -r
```

Expected: 输出包含 `🟡 安全风险: 只读挂载`

---

### Task 4: 更新帮助文本

**Files:**
- Modify: `dkagent:30-69`（print_help 函数）

- [ ] **Step 1: 替换 print_help 函数体**

将 `print_help()` 函数中 `cat <<'EOF'` 到 `EOF` 之间的内容替换为：

```
dkagent - AI Agent Docker 统一运行入口

用法:
  dkagent [选项] [agent名称] [附加参数...]

Agent 名称:
  claude        启动 Claude Code
  gemini        启动 Gemini CLI
  pi            启动 Pi Coding Agent
  codex         启动 OpenAI Codex
  opencode      启动 OpenCode
  (留空)         进入交互式 zsh shell

选项:
  -e, --ephemeral        🧊 使用临时 home 目录（不保留任何配置或历史记录，防注入更安全）
  -m, --mount DIR        📁 挂载指定目录到 /home/kali/workspace/<目录名>
                         支持多次指定: -m ./a -m ./b
                         支持空格分隔: -m "./a ./b"
  -r, --readonly         🔒 紧跟 -m 之后使用，将前一个 -m 目录以只读方式挂载
  --no-mount             🟢 不挂载任何工作目录（完全无法触碰宿主机文件，最安全）
  --env FILE             指定特定的 .env 文件路径
  --dry-run              仅打印 docker run 命令而不实际启动容器
  -h, --help             显示此帮助信息及安全警告

安全等级说明 (⚠ 请谨慎选择):
  风险等级由 挂载模式 × Home持久化 组合决定:

  🟢 隔离级别  : --no-mount + -e  (完全隔离，用完即焚)
  🟢 低风险    : --no-mount       (隔离宿主文件，持久化 home 有配置被改风险)
  🟢 低风险    : 全只读挂载 + -e  (只能读取，退出不留痕)
  🟡 中低风险  : 全只读挂载       (只能读取，但持久化 home 有配置被改风险)
  🟡 中风险    : 有可写挂载 + -e  (可操作挂载目录，退出不留痕)
  🔴 高风险    : 有可写挂载       (可操作挂载目录 + 持久化 home 可留后门)

示例:
  dkagent                                    # 挂载当前目录到 workspace/<basename>
  dkagent claude                             # 挂载当前目录，直接启动 Claude
  dkagent -e claude                          # 🧊 临时 home + 挂载当前目录
  dkagent -m ./project-a -m ./project-b      # 挂载多个目录
  dkagent -m ./original -r -m ./copy claude  # 原始目录只读，副本可读写
  dkagent --no-mount                         # 🟢 不挂载任何目录
  dkagent --env ~/custom.env                 # 使用自定义的 .env 配置文件
```

- [ ] **Step 2: 验证帮助输出**

```bash
dkagent --help
```

Expected: 输出包含新的 `-r, --readonly` 选项、多目录用法说明和 6 级风险矩阵

---

### Task 5: 更新 README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 替换安全模型图示**

将 README.md 的第 15-30 行（安全等级图示）替换为：

````
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
        └────────────────────────────────────────────────▶ 便捷性
```
````

- [ ] **Step 2: 替换安全对比表格**

将 README.md 的第 34-41 行（运行模式安全对比表格）替换为：

```markdown
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
```

- [ ] **Step 3: 更新常用操作指令示例**

将 README.md 的第 103-122 行（常用操作指令代码块）替换为：

```bash
# 进入交互式 Kali 命令行 (挂载当前目录到 /home/kali/workspace/<basename>)
dkagent

# 直接唤醒容器内的 Claude Code 并自动处理当前目录下的文件
dkagent claude

# 使用临时 Home 卷（用完即焚）并唤醒 Claude
dkagent -e claude

# 挂载多个目录（原项目 + 共享库）
dkagent -m ./my-project -m ./shared-libs claude

# 原始项目只读参考，副本目录可读写
dkagent -m ./my-project -r -m ./workspace/my-copy gemini

# 纯净模式，不挂载任何宿主机物理文件目录，仅进去容器玩耍/配置
dkagent --no-mount
```

- [ ] **Step 4: 更新可选参数列表**

将 README.md 的第 126-131 行（可选参数列表）替换为：

```markdown
* `-e`, `--ephemeral`: 🧊 使用临时 Home 目录，退出后不留痕迹。
* `-m`, `--mount DIR`: 📁 挂载指定目录到 `/home/kali/workspace/<目录名>`。支持多次指定（`-m ./a -m ./b`）和空格分隔（`-m "./a ./b"`）。
* `-r`, `--readonly`: 🔒 紧跟 `-m` 之后使用，将前一个 `-m` 目录以只读方式挂载。
* `--no-mount`: 🟢 完全不挂载任何宿主机物理目录（零宿主数据风险）。
* `--env FILE`: 手动指定其他 `.env` 秘钥配置文件。
* `--dry-run`: 🔍 仅打印将要运行的 `docker run` 命令大串，不实际建立并进入容器。
* `-h`, `--help`: 显示内置使用帮助。
```

---

### Task 6: 集成测试 — dry-run 端到端验证

- [ ] **Step 1: 测试默认 PWD 模式**

```bash
cd /tmp && dkagent --dry-run
```

Expected: docker run 命令包含 `-v /tmp:/home/kali/workspace/tmp:rw -w /home/kali/workspace`

- [ ] **Step 2: 测试多目录挂载**

```bash
mkdir -p /tmp/dkagent-test/a /tmp/dkagent-test/b
dkagent --dry-run -m /tmp/dkagent-test/a -m /tmp/dkagent-test/b
```

Expected: 包含 `-v .../a:/home/kali/workspace/a:rw -v .../b:/home/kali/workspace/b:rw -w /home/kali/workspace`

- [ ] **Step 3: 测试混合只读/可写**

```bash
dkagent --dry-run -m /tmp/dkagent-test/a -r -m /tmp/dkagent-test/b
```

Expected: `a:ro` 和 `b:rw`

- [ ] **Step 4: 测试空格分隔多目录**

```bash
dkagent --dry-run -m "/tmp/dkagent-test/a /tmp/dkagent-test/b"
```

Expected: 与 Step 2 相同的挂载参数

- [ ] **Step 5: 测试 --no-mount**

```bash
dkagent --dry-run --no-mount
```

Expected: 无 `-v` 挂载，`-w /home/kali`

- [ ] **Step 6: 测试 basename 冲突报错**

```bash
mkdir -p /tmp/dkagent-test/x/conflict /tmp/dkagent-test/y/conflict
dkagent --dry-run -m /tmp/dkagent-test/x/conflict -m /tmp/dkagent-test/y/conflict 2>&1
```

Expected: `❌ 错误: 目录名冲突！`

- [ ] **Step 7: 测试 -r 无 -m 报错**

```bash
dkagent --dry-run -r 2>&1
```

Expected: `❌ 错误: -r/--readonly 必须跟在 -m 之后使用！`

- [ ] **Step 8: 测试目录不存在报错**

```bash
dkagent --dry-run -m /nonexistent/path 2>&1
```

Expected: `❌ 错误: 指定的挂载目录不存在`

---

### Task 7: 提交

- [ ] **Step 1: 暂存并提交所有改动**

```bash
git add dkagent README.md docs/superpowers/
git commit -m "feat: multi-dir mount and readonly support for dkagent

- Support multiple -m flags and space-separated paths
- Add -r/--readonly for read-only mounts
- Unify all mounts to /home/kali/workspace/<basename>
- Add basename conflict detection
- Update risk matrix: mount-mode x home-persistence"
```
