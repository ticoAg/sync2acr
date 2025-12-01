#!/bin/bash

# 安装脚本：在当前用户下安装 s2i 命令，用于同步镜像到阿里云 ACR。
# 安装完成后即可通过以下形式使用：
#   s2i pull nginx:1.25
#   s2i push nginx:1.25
#   s2i rename minio/minio:latest minio
#   s2i list --all
#
# 默认安装位置：$HOME/.local/bin/s2i

set -e

INSTALL_DIR="$HOME/.local/bin"
INSTALL_NAME="s2i"
TARGET="$INSTALL_DIR/$INSTALL_NAME"

print_installer_usage() {
    cat <<EOF
Usage: $0 [install|uninstall]

install
  将 s2i 命令安装到: $TARGET

uninstall
  卸载 s2i 命令（删除 $TARGET，如存在）

安装完成后，可以通过以下方式使用：
  s2i pull IMAGE[:TAG]
  s2i push IMAGE[:TAG] [TARGET_NAME]
  s2i rename SRC_IMAGE[:TAG] TARGET_NAME
  s2i list [--acr|--all]

说明：
  - 本安装脚本不会修改你的 shell 配置文件，只负责生成 \$INSTALL_DIR/s2i。
  - 如果 \$INSTALL_DIR 不在 PATH 中，需要你手工把它加到 PATH。
EOF
}

ACTION="${1:-install}"

if [[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
    print_installer_usage
    exit 0
fi

if [[ "$ACTION" == "uninstall" ]]; then
    echo "🧹 正在卸载 $INSTALL_NAME ..."
    if [[ -e "$TARGET" ]]; then
        rm -f "$TARGET"
        echo "✅ 已删除: $TARGET"
    else
        echo "ℹ️ 未找到 $TARGET，无需卸载"
    fi
    exit 0
elif [[ "$ACTION" != "install" ]]; then
    echo "Unknown action: $ACTION"
    print_installer_usage
    exit 1
fi

echo "🔧 正在安装 $INSTALL_NAME 到: $TARGET"

mkdir -p "$INSTALL_DIR"

# 如果目标已经是一个符号链接，为了避免覆盖未知指向，要求用户手工删除。
if [ -L "$TARGET" ]; then
    echo "⚠️  检测到 $TARGET 已存在且为符号链接。"
    echo "    为避免覆盖已有链接，请先手工删除该文件，然后重新运行安装脚本："
    echo "      rm \"$TARGET\""
    exit 1
fi

# 安装逻辑：优先使用当前目录下的 s2i 脚本；如果不存在，则从远端仓库下载
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
SOURCE_SCRIPT_LOCAL="$SCRIPT_DIR/s2i"
REMOTE_BASE_URL="https://ghproxy.cn/https://raw.githubusercontent.com/ticoAg/sync2acr/main"
REMOTE_SCRIPT_URL="$REMOTE_BASE_URL/s2i"

if [[ -r "$SOURCE_SCRIPT_LOCAL" ]]; then
    echo "📄 使用本地脚本: $SOURCE_SCRIPT_LOCAL"
    cp "$SOURCE_SCRIPT_LOCAL" "$TARGET"
else
    echo "ℹ️ 未在本地找到 s2i 源脚本: $SOURCE_SCRIPT_LOCAL"
    echo "   将尝试从远端下载: $REMOTE_SCRIPT_URL"
    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ 未找到 curl 命令，且本地不存在 s2i 源脚本，无法继续安装。"
        exit 1
    fi
    curl -fsSL "$REMOTE_SCRIPT_URL" -o "$TARGET"
fi

chmod +x "$TARGET"

# 检查 PATH 中是否包含安装目录
case ":$PATH:" in
    *":$INSTALL_DIR:"*)
        echo "✅ 已将 $INSTALL_NAME 安装到 $TARGET"
        echo "   现在可以直接使用，例如："
        echo "     $INSTALL_NAME list --all"
        ;;
    *)
        echo "✅ 已将 $INSTALL_NAME 安装到 $TARGET"
        echo "⚠️  当前 PATH 不包含 $INSTALL_DIR"
        echo "   请在你的 shell 配置文件中手工添加，例如："
        echo "     export PATH=\"$INSTALL_DIR:\$PATH\""
        echo "   然后重新打开终端或执行："
        echo "     source ~/.bashrc  # 或对应的 rc 文件"
        ;;
esac

