#!/usr/bin/env bash
#
# install.sh - dkagent 命令行工具安装/卸载脚本
#
# 用法:
#   ./install.sh          # 安装 dkagent
#   ./install.sh remove   # 卸载 dkagent
#

set -euo pipefail

# ─── 配置 ───────────────────────────────────────────────
BIN_PATH="/usr/local/bin/dkagent"
CONFIG_DIR="$HOME/.config/dkagent"
CONFIG_FILE="${CONFIG_DIR}/.env"
DOCKER_IMAGE="${DKAGENT_IMAGE:-my-kali-agent}"

# ─── 国际化（i18n）─────────────────────────────────────────
# 语言检测优先级: DKAGENT_LANG 环境变量 > $LANG/$LC_ALL 自动判断 > 默认中文
detect_language() {
    local lang="${DKAGENT_LANG:-}"
    if [[ -z "$lang" ]]; then
        if [[ "${LC_ALL:-}" == zh* || "${LANG:-}" == zh* ]]; then
            lang="zh"
        elif [[ -z "${LC_ALL:-}${LANG:-}" || "${LC_ALL:-}" == "C"* || "${LANG:-}" == "C"* ]]; then
            lang="zh"
        else
            lang="en"
        fi
    fi
    echo "$lang"
}
CURRENT_LANG="$(detect_language)"

declare -A MSG_ZH=(
    [help_usage]="dkagent 安装工具"
    [help_install]="  ./install.sh          - 安装 dkagent 命令行工具"
    [help_remove]="  ./install.sh remove   - 卸载 dkagent 命令行工具"
    [install_start]="🚀 开始安装 dkagent..."
    [no_docker]="❌ 错误: 未检测到 docker 命令行工具，请先安装 Docker！"
    [chmod]="🔑 正在设置 dkagent 执行权限..."
    [symlink_creating]="🔗 正在创建符号链接到 %s (需要 sudo 权限)..."
    [symlink_ok]="✅ 符号链接创建成功！"
    [symlink_fail]="❌ 错误: 创建符号链接失败，请确认是否正确输入 sudo 密码！"
    [config_dir_init]="📂 初始化全局配置文件目录 %s..."
    [env_copy_from_cwd]="📋 发现当前目录的 .env 文件，正在复制到 %s..."
    [env_init_ok]="✅ 配置文件初始化成功！"
    [env_exists_skip]="ℹ️  %s 已存在，跳过复制以保留现有秘钥。"
    [env_from_template]="📋 当前目录无 .env，从模板 %s 创建 %s..."
    [env_template_ok]="✅ 配置模板已创建，请编辑填入你的 API Keys: vi %s"
    [env_missing]="⚠️  注意: 未找到 .env 或 .env.example。容器可能因为没有 API Keys 无法正常工作。"
    [env_missing_hint]="提示: 手动创建 %s 并填入 API Keys。"
    [image_missing]="\n⚠️  警告: 本地未检测到 Docker 镜像 '%s' (默认 profile: kali)。"
    [image_build_slim_first]="👉 推荐先构建精简镜像（快，约 2-3 分钟）:"
    [image_build_cmd]="   docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim ."
    [image_build_then]="   然后用: dkagent -p slim claude"
    [image_build_kali]="   或构建完整 Kali 镜像（约 15-30 分钟）: docker compose build"
    [install_done]="\n🎉 dkagent 安装成功！"
    [install_hint_line1]="你可以现在在任意目录下直接运行以下命令使用 AI Agent:"
    [install_hint_default]="  dkagent             - 默认模式进入交互式 zsh"
    [install_hint_claude]="  dkagent claude      - 一键拉起 Claude Code"
    [install_hint_help]="  dkagent --help      - 查看详细参数及安全隔离指南"
    [remove_start]="🗑️  开始卸载 dkagent..."
    [remove_symlink]="🔗 正在移除符号链接 %s (需要 sudo 权限)..."
    [remove_symlink_ok]="✅ 符号链接移除成功！"
    [remove_symlink_fail]="❌ 错误: 移除符号链接失败！"
    [remove_symlink_none]="ℹ️  未找到 %s，跳过移除。"
    [remove_config_found]="\n📂 发现全局配置文件夹 %s (包含 .env 秘钥文件)。"
    [remove_config_prompt]="是否删除该配置文件夹以彻底清理？(y/N): "
    [remove_config_deleting]="🧹 正在删除 %s..."
    [remove_config_ok]="✅ 配置文件清理成功！"
    [remove_config_keep]="ℹ️  已保留配置文件 %s。"
    [remove_done]="\n🎉 dkagent 卸载完成！"
    [unknown_action]="❌ 未知参数: %s"
)

declare -A MSG_EN=(
    [help_usage]="dkagent installer"
    [help_install]="  ./install.sh          - Install the dkagent CLI tool"
    [help_remove]="  ./install.sh remove   - Uninstall the dkagent CLI tool"
    [install_start]="🚀 Installing dkagent..."
    [no_docker]="❌ Error: docker not found. Please install Docker first!"
    [chmod]="🔑 Setting executable permission on dkagent..."
    [symlink_creating]="🔗 Creating symlink at %s (sudo required)..."
    [symlink_ok]="✅ Symlink created!"
    [symlink_fail]="❌ Error: Failed to create symlink. Did you enter the sudo password correctly?"
    [config_dir_init]="📂 Initializing global config dir %s..."
    [env_copy_from_cwd]="📋 Found .env in current dir, copying to %s..."
    [env_init_ok]="✅ Config initialized!"
    [env_exists_skip]="ℹ️  %s already exists, skipping copy to preserve your keys."
    [env_from_template]="📋 No .env in current dir, creating %s from template %s..."
    [env_template_ok]="✅ Config template created. Edit it and fill in your API keys: vi %s"
    [env_missing]="⚠️  Note: No .env or .env.example found. The container may not work without API keys."
    [env_missing_hint]="Hint: Manually create %s and fill in your API keys."
    [image_missing]="\n⚠️  Warning: Docker image '%s' not found locally (default profile: kali)."
    [image_build_slim_first]="👉 Recommended: build the slim image first (fast, ~2-3 min):"
    [image_build_cmd]="   docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim ."
    [image_build_then]="   Then run: dkagent -p slim claude"
    [image_build_kali]="   Or build the full Kali image (~15-30 min): docker compose build"
    [install_done]="\n🎉 dkagent installed successfully!"
    [install_hint_line1]="You can now run these commands from any directory:"
    [install_hint_default]="  dkagent             - default mode, enter interactive zsh"
    [install_hint_claude]="  dkagent claude      - launch Claude Code in one line"
    [install_hint_help]="  dkagent --help      - show options and the safety guide"
    [remove_start]="🗑️  Uninstalling dkagent..."
    [remove_symlink]="🔗 Removing symlink %s (sudo required)..."
    [remove_symlink_ok]="✅ Symlink removed!"
    [remove_symlink_fail]="❌ Error: Failed to remove symlink!"
    [remove_symlink_none]="ℹ️  %s not found, skipping."
    [remove_config_found]="\n📂 Found global config dir %s (contains the .env key file)."
    [remove_config_prompt]="Delete this config dir to fully clean up? (y/N): "
    [remove_config_deleting]="🧹 Deleting %s..."
    [remove_config_ok]="✅ Config cleaned up!"
    [remove_config_keep]="ℹ️  Kept config dir %s."
    [remove_done]="\n🎉 dkagent uninstalled!"
    [unknown_action]="❌ Unknown argument: %s"
)

msg() {
    local key="$1"; shift
    local template
    if [[ "$CURRENT_LANG" == "en" ]]; then
        template="${MSG_EN[$key]:-}"
    else
        template="${MSG_ZH[$key]:-}"
    fi
    if [[ $# -gt 0 ]]; then
        # shellcheck disable=SC2059
        printf "$template\n" "$@"
    else
        # shellcheck disable=SC2059
        printf "$template\n"
    fi
}

# ─── 帮助 ───────────────────────────────────────────────
print_help() {
    msg help_usage
    echo "Usage:"
    msg help_install
    msg help_remove
}

# ─── 安装逻辑 ───────────────────────────────────────────
install_agent() {
    msg install_start

    # 1. 检查 Docker 依赖
    if ! command -v docker &>/dev/null; then
        msg no_docker >&2
        exit 1
    fi

    # 2. 赋予脚本执行权限
    msg chmod
    chmod +x dkagent

    # 3. 创建符号链接到 /usr/local/bin
    local script_abs_path
    script_abs_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkagent"

    msg symlink_creating "$BIN_PATH"
    if sudo ln -sf "${script_abs_path}" "${BIN_PATH}"; then
        msg symlink_ok
    else
        msg symlink_fail >&2
        exit 1
    fi

    # 4. 初始化配置文件目录及 .env 文件
    msg config_dir_init "$CONFIG_DIR"
    mkdir -p "${CONFIG_DIR}"

    if [[ -f ".env" ]]; then
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            msg env_copy_from_cwd "$CONFIG_FILE"
            cp ".env" "${CONFIG_FILE}"
            chmod 600 "${CONFIG_FILE}" # 保证秘钥安全性
            msg env_init_ok
        else
            msg env_exists_skip "$CONFIG_FILE"
        fi
    else
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            # 当前目录无 .env，自动用 .env.example 创建模板（若存在）
            local template=""
            [[ -f ".env.example" ]] && template=".env.example"
            [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env.example" ]] && \
                template="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env.example"
            if [[ -n "$template" ]]; then
                msg env_from_template "$template" "$CONFIG_FILE"
                cp "$template" "${CONFIG_FILE}"
                chmod 600 "${CONFIG_FILE}"
                msg env_template_ok "$CONFIG_FILE"
            else
                msg env_missing >&2
                msg env_missing_hint "$CONFIG_FILE" >&2
            fi
        fi
    fi

    # 5. 检查镜像是否存在并友好提示
    if ! docker image inspect "${DOCKER_IMAGE}" &>/dev/null; then
        msg image_missing "$DOCKER_IMAGE" >&2
        msg image_build_slim_first >&2
        msg image_build_cmd >&2
        msg image_build_then >&2
        msg image_build_kali >&2
    fi

    # 6. 安装完成提示
    msg install_done
    echo "--------------------------------------------------"
    msg install_hint_line1
    msg install_hint_default
    msg install_hint_claude
    msg install_hint_help
    echo "--------------------------------------------------"
}

# ─── 卸载逻辑 ───────────────────────────────────────────
uninstall_agent() {
    msg remove_start

    # 1. 移除符号链接
    if [[ -L "${BIN_PATH}" || -f "${BIN_PATH}" ]]; then
        msg remove_symlink "$BIN_PATH"
        if sudo rm -f "${BIN_PATH}"; then
            msg remove_symlink_ok
        else
            msg remove_symlink_fail >&2
            exit 1
        fi
    else
        msg remove_symlink_none "$BIN_PATH"
    fi

    # 2. 询问是否清理配置文件
    if [[ -d "${CONFIG_DIR}" ]]; then
        msg remove_config_found "$CONFIG_DIR"
        read -r -p "$(msg remove_config_prompt)" response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            msg remove_config_deleting "$CONFIG_DIR"
            rm -rf "${CONFIG_DIR}"
            msg remove_config_ok
        else
            msg remove_config_keep "$CONFIG_DIR"
        fi
    fi

    msg remove_done
}

# ─── 路由逻辑 ───────────────────────────────────────────
ACTION="${1:-install}"

case "${ACTION}" in
    install)
        install_agent
        ;;
    remove|uninstall)
        uninstall_agent
        ;;
    -h|--help)
        print_help
        ;;
    *)
        msg unknown_action "${ACTION}" >&2
        print_help
        exit 1
        ;;
esac
