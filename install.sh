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

# ─── 帮助 ───────────────────────────────────────────────
print_help() {
    echo "dkagent 安装工具"
    echo "用法:"
    echo "  ./install.sh          - 安装 dkagent 命令行工具"
    echo "  ./install.sh remove   - 卸载 dkagent 命令行工具"
}

# ─── 安装逻辑 ───────────────────────────────────────────
install_agent() {
    echo "🚀 开始安装 dkagent..."

    # 1. 检查 Docker 依赖
    if ! command -v docker &>/dev/null; then
        echo "❌ 错误: 未检测到 docker 命令行工具，请先安装 Docker！" >&2
        exit 1
    fi

    # 2. 赋予脚本执行权限
    echo "🔑 正在设置 dkagent 执行权限..."
    chmod +x dkagent

    # 3. 创建符号链接到 /usr/local/bin
    local script_abs_path
    script_abs_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dkagent"
    
    echo "🔗 正在创建符号链接到 ${BIN_PATH} (需要 sudo 权限)..."
    if sudo ln -sf "${script_abs_path}" "${BIN_PATH}"; then
        echo "✅ 符号链接创建成功！"
    else
        echo "❌ 错误: 创建符号链接失败，请确认是否正确输入 sudo 密码！" >&2
        exit 1
    fi

    # 4. 初始化配置文件目录及 .env 文件
    echo "📂 初始化全局配置文件目录 ${CONFIG_DIR}..."
    mkdir -p "${CONFIG_DIR}"

    if [[ -f ".env" ]]; then
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            echo "📋 发现当前目录的 .env 文件，正在复制到 ${CONFIG_FILE}..."
            cp ".env" "${CONFIG_FILE}"
            chmod 600 "${CONFIG_FILE}" # 保证秘钥安全性
            echo "✅ 配置文件初始化成功！"
        else
            echo "ℹ️  ${CONFIG_FILE} 已存在，跳过复制以保留现有秘钥。"
        fi
    else
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            # 当前目录无 .env，自动用 .env.example 创建模板（若存在）
            local template=""
            [[ -f ".env.example" ]] && template=".env.example"
            [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env.example" ]] && \
                template="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env.example"
            if [[ -n "$template" ]]; then
                echo "📋 当前目录无 .env，从模板 ${template} 创建 ${CONFIG_FILE}..."
                cp "$template" "${CONFIG_FILE}"
                chmod 600 "${CONFIG_FILE}"
                echo "✅ 配置模板已创建，请编辑填入你的 API Keys: vi ${CONFIG_FILE}"
            else
                echo "⚠️  注意: 未找到 .env 或 .env.example。容器可能因为没有 API Keys 无法正常工作。"
                echo "提示: 手动创建 ${CONFIG_FILE} 并填入 API Keys。"
            fi
        fi
    fi

    # 5. 检查镜像是否存在并友好提示
    if ! docker image inspect "${DOCKER_IMAGE}" &>/dev/null; then
        echo -e "\n⚠️  警告: 本地未检测到 Docker 镜像 '${DOCKER_IMAGE}' (默认 profile: kali)。"
        echo "👉 推荐先构建精简镜像（快，约 2-3 分钟）:"
        echo "   docker build -t dkagent-slim -f dockerfiles/Dockerfile.slim ."
        echo "   然后用: dkagent -p slim claude"
        echo "   或构建完整 Kali 镜像（约 15-30 分钟）: docker compose build"
    fi

    # 6. 安装完成提示
    echo -e "\n🎉 dkagent 安装成功！"
    echo "--------------------------------------------------"
    echo "你可以现在在任意目录下直接运行以下命令使用 AI Agent:"
    echo "  dkagent             - 默认模式进入交互式 zsh"
    echo "  dkagent claude      - 一键拉起 Claude Code"
    echo "  dkagent --help      - 查看详细参数及安全隔离指南"
    echo "--------------------------------------------------"
}

# ─── 卸载逻辑 ───────────────────────────────────────────
uninstall_agent() {
    echo "🗑️  开始卸载 dkagent..."

    # 1. 移除符号链接
    if [[ -L "${BIN_PATH}" || -f "${BIN_PATH}" ]]; then
        echo "🔗 正在移除符号链接 ${BIN_PATH} (需要 sudo 权限)..."
        if sudo rm -f "${BIN_PATH}"; then
            echo "✅ 符号链接移除成功！"
        else
            echo "❌ 错误: 移除符号链接失败！" >&2
            exit 1
        fi
    else
        echo "ℹ️  未找到 ${BIN_PATH}，跳过移除。"
    fi

    # 2. 询问是否清理配置文件
    if [[ -d "${CONFIG_DIR}" ]]; then
        echo -e "\n📂 发现全局配置文件夹 ${CONFIG_DIR} (包含 .env 秘钥文件)。"
        read -r -p "是否删除该配置文件夹以彻底清理？(y/N): " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "🧹 正在删除 ${CONFIG_DIR}..."
            rm -rf "${CONFIG_DIR}"
            echo "✅ 配置文件清理成功！"
        else
            echo "ℹ️  已保留配置文件 ${CONFIG_DIR}。"
        fi
    fi

    echo -e "\n🎉 dkagent 卸载完成！"
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
        echo "❌ 未知参数: ${ACTION}" >&2
        print_help
        exit 1
        ;;
esac
