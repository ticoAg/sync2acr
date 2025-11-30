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

cat >"$TARGET" <<'EOF'
#!/bin/bash

# s2i: 简单的 ACR 同步小工具
# 支持子命令（类似 git）：login / pull / push / rename / list
#
#   s2i login [acr|REGISTRY] [USERNAME]
#   s2i pull IMAGE[:TAG]
#   s2i rename SRC_IMAGE[:TAG] TARGET_NAME
#   s2i push SRC_IMAGE[:TAG] [TARGET_NAME[:TARGET_TAG]]
#   s2i list [--acr|--all]

# 配置项（请根据实际情况修改）
ALIYUN_REGISTRY="registry.cn-beijing.aliyuncs.com"
ALIYUN_USERNAME="15680605607"
ALIYUN_NAMESPACE="ticoag"  # 你的命名空间

# 渠道 / 仓库策略配置（预留给后续扩展其他渠道，例如 harbor、dockerhub 等）
S2I_CHANNEL="${S2I_CHANNEL:-acr}"  # 当前仅支持 acr 渠道
# 当 Registry 支持“按需自动创建仓库”时设为 true（例如你当前开启的 ACR）
# 如果未来接入不支持自动创建仓库的渠道，可将其设为 false，push 失败时会提示“请先创建仓库”
S2I_REGISTRY_AUTO_CREATE_REPO="${S2I_REGISTRY_AUTO_CREATE_REPO:-true}"

print_usage() {
    cat <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  login [CHANNEL] USERNAME
      登录镜像仓库（渠道 + 用户名 + 密码均由用户输入）：
        login user              默认使用 ACR 渠道（$ALIYUN_REGISTRY），用户名为 user
        login acr user          显式指定 ACR 渠道
        login docker.io user    登录 docker.io（或其他任意 REGISTRY）

  pull IMAGE[:TAG]
      从远端仓库拉取镜像（等价于 docker pull），例：
        $(basename "$0") pull nginx:1.25

  rename SRC_IMAGE[:TAG] TARGET_NAME
      给本地镜像重新“命名”为 ACR 下的名字（只打 tag，不 push）：
        SRC_IMAGE       本地已有镜像，如 minio/minio:latest
        TARGET_NAME     目标仓库名，不带 tag，例如 minio
      生成的目标镜像形如：
        $ALIYUN_REGISTRY/$ALIYUN_NAMESPACE/TARGET_NAME:TAG

  push SRC_IMAGE[:TAG] [TARGET_NAME[:TARGET_TAG]]
      从远端拉取（如果本地不存在），自动打到 ACR 并推送：
        SRC_IMAGE           源镜像，如 nginx:1.25
        TARGET_NAME         目标仓库名（可省略，默认使用镜像名最后一段）
        TARGET_TAG          目标 tag（可省略，默认沿用 SRC_IMAGE 的 tag）
      例：
        $(basename "$0") push nginx:1.25
        $(basename "$0") push minio/minio:latest minio
        $(basename "$0") push postgres:latest postgres:18.1

  list [--acr|--all]
      查看本地镜像：
        --acr (默认)  只列出本地 ACR 命名空间下的镜像
        --all         列出所有本地镜像

  help, -h, --help
      显示本帮助信息
USAGE
}

cmd_login() {
    # 语法：
    #   s2i login USERNAME                # 默认渠道 acr（ALIYUN_REGISTRY）
    #   s2i login acr USERNAME            # 显式指定 acr
    #   s2i login docker.io USERNAME      # 指定任意 registry
    #
    # 渠道 / registry 一律由用户显式给出或使用默认，不再依赖脚本内置用户名。

    local arg1="$1"
    local arg2="$2"

    if [[ -z "$arg1" ]]; then
        echo "Usage: $(basename "$0") login [CHANNEL] USERNAME"
        return 1
    fi

    local registry username

    if [[ -n "$arg2" ]]; then
        # 两个参数：CHANNEL USERNAME
        case "$arg1" in
            acr)
                registry="$ALIYUN_REGISTRY"
                ;;
            dockerhub|docker.io)
                registry="docker.io"
                ;;
            *)
                registry="$arg1"   # 直接当作 registry 地址
                ;;
        esac
        username="$arg2"
    else
        # 一个参数：USERNAME，默认渠道为 acr
        registry="$ALIYUN_REGISTRY"
        username="$arg1"
    fi

    local password
    read -s -p "Enter password for $username@$registry: " password
    echo

    echo "🔍 Logging into registry: $registry ..."
    echo "$password" | docker login --username="$username" --password-stdin "$registry"

    if [ $? -ne 0 ]; then
        echo "❌ Docker login failed!"
        return 1
    fi

    echo "✅ Login succeeded for $username@$registry"
}

# 检查是否已登录 ACR（当前用户配置）
ensure_acr_login() {
    echo "🔍 Checking login status for $ALIYUN_REGISTRY ..."
    local docker_config_dir="${DOCKER_CONFIG:-$HOME/.docker}"
    local docker_config_file="$docker_config_dir/config.json"

    if [ -f "$docker_config_file" ] && grep -q "\"$ALIYUN_REGISTRY\"" "$docker_config_file" 2>/dev/null; then
        echo "✅ Already logged in to $ALIYUN_REGISTRY (found in $docker_config_file)."
        return 0
    fi

    echo "🔑 Not logged in to $ALIYUN_REGISTRY yet."
    echo "   请先执行：$(basename "$0") login USERNAME"
    echo "   （例如：$(basename "$0") login $ALIYUN_USERNAME）"
    return 1
}

cmd_pull() {
    local image="$1"
    if [[ -z "$image" ]]; then
        echo "Usage: $(basename "$0") pull IMAGE[:TAG]"
        return 1
    fi

    echo "📥 Pulling image: $image"
    docker pull "$image"
}

cmd_rename() {
    local src="$1"
    local target_name="$2"

    if [[ -z "$src" || -z "$target_name" ]]; then
        echo "Usage: $(basename "$0") rename SRC_IMAGE[:TAG] TARGET_NAME"
        return 1
    fi

    local src_with_tag="$src"
    local tag
    if [[ "$src" == *":"* ]]; then
        tag="${src##*:}"
    else
        tag="latest"
        src_with_tag="$src:latest"
    fi

    local target_image="$ALIYUN_REGISTRY/$ALIYUN_NAMESPACE/$target_name:$tag"

    echo "🏷️  Tagging local image: $src_with_tag -> $target_image"
    docker tag "$src_with_tag" "$target_image"
}

cmd_push() {
    local src="$1"
    local target_arg="$2"

    if [[ -z "$src" ]]; then
        echo "Usage: $(basename "$0") push SRC_IMAGE[:TAG] [TARGET_NAME[:TARGET_TAG]]"
        return 1
    fi

    local src_with_tag="$src"
    local src_tag
    if [[ "$src" == *":"* ]]; then
        src_tag="${src##*:}"
    else
        src_tag="latest"
        src_with_tag="$src:latest"
    fi

    # 提取镜像名（不含 tag 和 registry），用来作为默认 TARGET_NAME
    local repo="${src_with_tag%%:*}"        # 去掉 :tag
    local repo_no_registry="$repo"
    if [[ "$repo" == *"/"* ]]; then
        repo_no_registry="${repo##*/}"
    fi

    local target_name
    local target_tag

    if [[ -z "$target_arg" ]]; then
        # 未指定目标，使用镜像名最后一段 + 源 tag
        target_name="$repo_no_registry"
        target_tag="$src_tag"
    else
        # 允许 TARGET_NAME 或 TARGET_NAME:TARGET_TAG 形式
        if [[ "$target_arg" == *":"* ]]; then
            target_name="${target_arg%%:*}"
            target_tag="${target_arg##*:}"
        else
            target_name="$target_arg"
            target_tag="$src_tag"
        fi
    fi

    echo "📥 Ensuring local image exists: $src_with_tag"
    docker pull "$src_with_tag"
    if [ $? -ne 0 ]; then
        echo "❌ Failed to pull $src_with_tag"
        return 1
    fi

    ensure_acr_login || return 1

    local target_image="$ALIYUN_REGISTRY/$ALIYUN_NAMESPACE/$target_name:$target_tag"

    echo "🏷️  Tagging as: $target_image"
    docker tag "$src_with_tag" "$target_image"

    echo "📤 Pushing to Alibaba Cloud: $target_image"
    docker push "$target_image"
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed: $src_with_tag → $target_image"
    else
        echo "❌ Failed to push: $target_image"

        # 根据是否开启“自动创建仓库”给出不同的提示
        if [[ "$S2I_REGISTRY_AUTO_CREATE_REPO" != "true" ]]; then
            echo "💡 当前配置为：Registry 不自动创建仓库。"
            echo "   请先在 $ALIYUN_REGISTRY 控制台手动创建仓库：$ALIYUN_NAMESPACE/$target_name，然后重试。"
        else
            echo "💡 当前配置为：Registry 支持按需自动创建仓库（如已为 ACR 打开该功能）。"
            echo "   如果多次失败，请检查："
            echo "     - 命名空间 $ALIYUN_NAMESPACE 是否存在，账号是否有 push 权限"
            echo "     - ACR 渠道配置是否正确（例如 region、namespace）"
            echo "     - 本机到 $ALIYUN_REGISTRY 的网络连通性"
        fi
        return 1
    fi
}

cmd_list() {
    local scope="acr"

    # 支持两种写法：
    #   s2i list --all
    #   s2i list all
    # 默认是 acr
    if [[ "$1" == "--all" || "$1" == "-a" || "$1" == "all" ]]; then
        scope="all"
    elif [[ "$1" == "--acr" || "$1" == "acr" ]]; then
        scope="acr"
    fi

    case "$scope" in
        acr)
            echo "📋 Local images under ACR namespace $ALIYUN_REGISTRY/$ALIYUN_NAMESPACE:"
            docker images "$ALIYUN_REGISTRY/$ALIYUN_NAMESPACE/*"
            ;;
        all)
            echo "📋 All local images:"
            docker images
            ;;
    esac
}

main() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        login)
            cmd_login "$@"
            ;;
        pull)
            cmd_pull "$@"
            ;;
        rename)
            cmd_rename "$@"
            ;;
        push)
            cmd_push "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        ""|help|-h|--help)
            print_usage
            ;;
        *)
            echo "Unknown command: $cmd"
            print_usage
            return 1
            ;;
    esac
}

main "$@"
EOF

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
