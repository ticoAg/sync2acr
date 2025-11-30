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

# s2i: 简单的镜像同步小工具
# 支持子命令（类似 git）：login / pull / push / rename / list / version / channel
#
#   s2i login [acr|REGISTRY] [USERNAME]
#   s2i pull IMAGE[:TAG]
#   s2i rename SRC_IMAGE[:TAG] TARGET_NAME
#   s2i push SRC_IMAGE[:TAG] [TARGET_NAME[:TARGET_TAG]]
#   s2i list [--acr|--all]
#   s2i version IMAGE[:TAG]
#   s2i channel [list|current|set <CHANNEL>]

# 配置项（请根据实际情况修改）
ALIYUN_REGISTRY="registry.cn-beijing.aliyuncs.com"
ALIYUN_USERNAME="15680605607"
ALIYUN_NAMESPACE="ticoag"  # 你的命名空间
DOCKERHUB_NAMESPACE="${DOCKERHUB_NAMESPACE:-$ALIYUN_NAMESPACE}"  # docker.io 下的命名空间（可覆盖）

# 渠道 / 仓库策略配置（预留给后续扩展其他渠道）
DEFAULT_CHANNEL="aliyun"
S2I_CHANNEL="${S2I_CHANNEL:-}"  # 优先使用环境变量；否则读取配置文件；再否则用 DEFAULT_CHANNEL
S2I_REGISTRY_AUTO_CREATE_REPO="${S2I_REGISTRY_AUTO_CREATE_REPO:-true}"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/s2i"
CONFIG_FILE="$CONFIG_DIR/config"
SUPPORTED_CHANNELS=("aliyun" "dockerhub")

ensure_config_dir() {
    [ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR"
}

load_config() {
    # 按优先级：环境变量 > 配置文件 > 默认值
    if [[ -n "$S2I_CHANNEL" ]]; then
        CURRENT_CHANNEL="$S2I_CHANNEL"
        return
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi

    CURRENT_CHANNEL="${S2I_CHANNEL:-$DEFAULT_CHANNEL}"
}

save_channel() {
    local channel="$1"
    ensure_config_dir
    cat >"$CONFIG_FILE" <<EOF_CFG
S2I_CHANNEL="$channel"
EOF_CFG
    CURRENT_CHANNEL="$channel"
}

is_supported_channel() {
    local c="$1"
    for ch in "${SUPPORTED_CHANNELS[@]}"; do
        [[ "$ch" == "$c" ]] && return 0
    done
    return 1
}

resolve_channel() {
    # 读取当前渠道对应的 registry / namespace / auto_create
    local channel="$1"
    case "$channel" in
        aliyun|acr)
            CHANNEL_REGISTRY="$ALIYUN_REGISTRY"
            CHANNEL_NAMESPACE="$ALIYUN_NAMESPACE"
            CHANNEL_AUTO_CREATE="$S2I_REGISTRY_AUTO_CREATE_REPO"
            ;;
        dockerhub|docker.io)
            CHANNEL_REGISTRY="docker.io"
            CHANNEL_NAMESPACE="$DOCKERHUB_NAMESPACE"
            CHANNEL_AUTO_CREATE="true"
            ;;
        *)
            echo "Unknown channel: $channel" >&2
            return 1
            ;;
    esac
}

print_usage() {
    cat <<USAGE
Usage: $(basename "$0") <command> [options]

Commands:
  login [CHANNEL] USERNAME
      登录镜像仓库（渠道 + 用户名 + 密码均由用户输入）：
        login user              默认使用 ACR 渠道（$ALIYUN_REGISTRY），用户名为 user
        login acr user          显式指定 ACR 渠道
        login docker.io user    登录 docker.io（或其他任意 REGISTRY）
      预制渠道：${SUPPORTED_CHANNELS[*]}（默认：$DEFAULT_CHANNEL）

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
        --acr         只列出当前渠道命名空间下的镜像
        --all (默认)  列出所有本地镜像

  version IMAGE[:TAG]
      查看本地镜像的详细信息与常见版本标签（如果存在），例如：
        $(basename "$0") version grafana/grafana:latest
  
  channel [list|current|set <CHANNEL>]
      管理 s2i 当前使用的渠道：
        channel list        查看支持的渠道
        channel current     查看当前渠道
        channel set aliyun  切换到指定渠道（会写入配置文件）

  help, -h, --help
      显示本帮助信息
USAGE
}

print_login_usage() {
    echo "Usage: $(basename "$0") login [CHANNEL] USERNAME"
    echo "预制渠道: ${SUPPORTED_CHANNELS[*]} (默认: $DEFAULT_CHANNEL)"
    echo "示例: $(basename "$0") login $DEFAULT_CHANNEL user"
    echo "      $(basename "$0") login docker.io user"
}

cmd_login() {
    # 语法：
    #   s2i login USERNAME                # 默认渠道 aliyun（ALIYUN_REGISTRY）
    #   s2i login acr USERNAME            # 显式指定 aliyun/acr
    #   s2i login docker.io USERNAME      # 指定任意 registry
    #
    # 渠道 / registry 一律由用户显式给出或使用默认，不再依赖脚本内置用户名。

    local arg1="$1"
    local arg2="$2"

    if [[ -z "$arg1" ]]; then
        print_login_usage
        return 1
    fi

    if [[ "$arg1" == "--help" || "$arg1" == "-h" || "$arg1" == "help" ]]; then
        print_login_usage
        return 0
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

ensure_registry_login() {
    local registry="$1"
    echo "🔍 Checking login status for $registry ..."
    local docker_config_dir="${DOCKER_CONFIG:-$HOME/.docker}"
    local docker_config_file="$docker_config_dir/config.json"

    if [ -f "$docker_config_file" ] && grep -q "\"$registry\"" "$docker_config_file" 2>/dev/null; then
        echo "✅ Already logged in to $registry (found in $docker_config_file)."
        return 0
    fi

    echo "🔑 Not logged in to $registry yet."
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

    load_config
    resolve_channel "$CURRENT_CHANNEL" || return 1

    local target_image="$CHANNEL_REGISTRY/$CHANNEL_NAMESPACE/$target_name:$tag"

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

    # 判断是否是 image ID / digest（例如 sha256:... 或 12+ 位十六进制 ID）
    local is_image_id="false"
    if [[ "$src" == sha256:* ]]; then
        is_image_id="true"
    elif [[ ${#src} -ge 12 && "$src" =~ ^[0-9a-fA-F]+$ ]]; then
        is_image_id="true"
    fi

    local src_with_tag="$src"
    local src_tag=""
    if [[ "$is_image_id" != "true" ]]; then
        if [[ "$src" == *":"* ]]; then
            src_tag="${src##*:}"
        else
            src_tag="latest"
            src_with_tag="$src:latest"
        fi
    fi

    # 提取镜像名（不含 tag 和 registry），用来作为默认 TARGET_NAME（仅针对非 image ID 场景）
    local repo="${src_with_tag%%:*}"        # 去掉 :tag
    local repo_no_registry="$repo"
    if [[ "$repo" == *"/"* ]]; then
        repo_no_registry="${repo##*/}"
    fi

    local target_name
    local target_tag

    if [[ -z "$target_arg" ]]; then
        if [[ "$is_image_id" == "true" ]]; then
            echo "❌ 使用 image ID 推送时需要显式指定目标名称，例如："
            echo "   $(basename "$0") push <IMAGE_ID> myrepo/myimage:tag"
            return 1
        fi
        # 未指定目标（且不是 image ID），使用镜像名最后一段 + 源 tag
        target_name="$repo_no_registry"
        target_tag="$src_tag"
    else
        # 允许 TARGET_NAME 或 TARGET_NAME:TARGET_TAG 形式
        if [[ "$target_arg" == *":"* ]]; then
            target_name="${target_arg%%:*}"
            target_tag="${target_arg##*:}"
        else
            # TARGET_NAME 不带 tag；如果包含路径（如 grafana/grafana），仅使用最后一段作为仓库名
            target_name="$target_arg"
            if [[ "$target_name" == *"/"* ]]; then
                target_name="${target_name##*/}"
            fi
            if [[ "$is_image_id" == "true" ]]; then
                # image ID + 仅目标仓库名：稍后通过 RepoTags 或标签推断 tag
                target_tag=""
            else
                target_tag="$src_tag"
            fi
        fi
    fi

    echo "📥 Ensuring local image exists: $src_with_tag"
    if docker image inspect "$src_with_tag" >/dev/null 2>&1; then
        echo "✅ Found local image: $src_with_tag"
    else
        echo "ℹ️ Local image not found, pulling from registry..."
        if ! docker pull "$src_with_tag"; then
            echo "❌ Failed to pull $src_with_tag and no local image is available."
            echo "   请先在本地构建或拉取该镜像后再重试。"
            return 1
        fi
    fi

    # 如果使用 image ID 且未显式指定目标 tag，则尝试从本地 RepoTags 推断一个默认 tag
    if [[ "$is_image_id" == "true" && -n "$target_name" && -z "$target_tag" ]]; then
        local repo_tags first_repo_tag inferred_tag
        repo_tags=$(docker image inspect "$src_with_tag" --format '{{range .RepoTags}}{{println .}}{{end}}' 2>/dev/null || true)
        first_repo_tag=$(echo "$repo_tags" | head -n1)
        if [[ -n "$first_repo_tag" && "$first_repo_tag" == *":"* ]]; then
            inferred_tag="${first_repo_tag##*:}"
            target_tag="$inferred_tag"
            echo "🏷️  Using tag from first RepoTag of image ($first_repo_tag) -> $target_tag"
        else
            target_tag="latest"
            echo "ℹ️ 无法从 image ID 关联的 RepoTags 推断 tag，默认使用: $target_tag"
        fi
    fi

    # 如果源是 name:latest 且用户只给了目标仓库名（不带 tag），尝试从镜像中推断真实版本号并作为目标 tag
    if [[ "$is_image_id" != "true" && "$src_tag" == "latest" && -n "$target_arg" && "$target_arg" != *":"* ]]; then
        local detected_version
        detected_version=$(detect_image_version "$src_with_tag" 2>/dev/null || true)
        if [[ -n "$detected_version" ]]; then
            echo "🏷️  Detected version: $detected_version"
            echo "    将使用该版本作为目标 tag（原本为: $target_tag）"
            target_tag="$detected_version"
        fi
    fi

    load_config
    resolve_channel "$CURRENT_CHANNEL" || return 1

    ensure_registry_login "$CHANNEL_REGISTRY" || return 1

    local target_image="$CHANNEL_REGISTRY/$CHANNEL_NAMESPACE/$target_name:$target_tag"

    echo "🏷️  Tagging as: $target_image"
    docker tag "$src_with_tag" "$target_image"

    echo "📤 Pushing to $CHANNEL_REGISTRY: $target_image"
    docker push "$target_image"
    if [ $? -eq 0 ]; then
        echo "✅ Successfully pushed: $src_with_tag → $target_image"
    else
        echo "❌ Failed to push: $target_image"

        # 根据是否开启“自动创建仓库”给出不同的提示
        if [[ "$CHANNEL_AUTO_CREATE" != "true" ]]; then
            echo "💡 当前配置为：Registry 不自动创建仓库。"
            echo "   请先在 $CHANNEL_REGISTRY 控制台手动创建仓库：$CHANNEL_NAMESPACE/$target_name，然后重试。"
        else
            echo "💡 当前配置为：Registry 支持按需自动创建仓库。"
            echo "   如果多次失败，请检查："
            echo "     - 命名空间 $CHANNEL_NAMESPACE 是否存在，账号是否有 push 权限"
            echo "     - 渠道配置是否正确（例如 region、namespace）"
            echo "     - 本机到 $CHANNEL_REGISTRY 的网络连通性"
        fi
        return 1
    fi
}

cmd_list() {
    local scope="all"

    # 支持两种写法：
    #   s2i list --all
    #   s2i list all
    # 默认是 acr
    if [[ "$1" == "--acr" || "$1" == "acr" ]]; then
        scope="acr"
    elif [[ "$1" == "--all" || "$1" == "-a" || "$1" == "all" ]]; then
        scope="all"
    fi

    load_config
    resolve_channel "$CURRENT_CHANNEL" || return 1

    case "$scope" in
        acr)
            echo "📋 Local images under channel '$CURRENT_CHANNEL': $CHANNEL_REGISTRY/$CHANNEL_NAMESPACE"
            docker images "$CHANNEL_REGISTRY/$CHANNEL_NAMESPACE/*"
            ;;
        all)
            echo "📋 All local images:"
            docker images
            ;;
    esac
}

detect_image_version_label() {
    # 从镜像标签中尝试提取常见的版本号字段，成功则回显版本号
    # $1: image reference（例如 grafana/grafana:latest）
    local image_ref="$1"
    local label_lines version_label

    label_lines=$(docker image inspect "$image_ref" --format '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}' 2>/dev/null || true)
    if [[ -z "$label_lines" ]]; then
        return 1
    fi

    version_label=$(echo "$label_lines" | awk -F= '
        $1=="org.opencontainers.image.version"{print $2; exit}
        $1=="org.opencontainers.image.revision"{print $2; exit}
        $1=="version"{print $2; exit}
        $1=="app.version"{print $2; exit}
        $1=="app_version"{print $2; exit}
    ')

    if [[ -n "$version_label" ]]; then
        echo "$version_label"
        return 0
    fi

    return 1
}

detect_image_version_by_run() {
    # 通过在容器内执行 --version 命令来尝试提取版本号
    # 适用于 grafana/grafana 等支持 `<binary> --version` 的镜像
    local image_ref="$1"
    local output version

    # 尝试运行容器并抓取输出（避免影响用户终端，重定向 stderr）
    if ! output=$(docker run --rm "$image_ref" --version 2>/dev/null); then
        return 1
    fi

    # 从输出中提取类似 12.3.0 这样的版本号（取第一个）
    version=$(echo "$output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    return 1
}

detect_image_version() {
    # 综合版本探测：优先从镜像标签读取，其次尝试 docker run --version
    local image_ref="$1"
    local v

    v=$(detect_image_version_label "$image_ref" 2>/dev/null || true)
    if [[ -n "$v" ]]; then
        echo "$v"
        return 0
    fi

    v=$(detect_image_version_by_run "$image_ref" 2>/dev/null || true)
    if [[ -n "$v" ]]; then
        echo "$v"
        return 0
    fi

    return 1
}

cmd_version() {
    local image="$1"

    if [[ -z "$image" ]]; then
        echo "Usage: $(basename "$0") version IMAGE[:TAG]"
        return 1
    fi

    local image_with_tag="$image"
    if [[ "$image" != *":"* ]]; then
        image_with_tag="$image:latest"
    fi

    echo "🔍 Inspecting local image: $image_with_tag"

    if ! docker image inspect "$image_with_tag" >/dev/null 2>&1; then
        echo "❌ Local image not found: $image_with_tag"
        echo "   请先在本地构建或拉取该镜像，例如："
        echo "     docker pull $image_with_tag"
        echo "   或使用："
        echo "     $(basename \"$0\") pull $image_with_tag"
        return 1
    fi

    local image_id repo_digests version_label

    image_id=$(docker image inspect "$image_with_tag" --format '{{.Id}}' 2>/dev/null || true)
    repo_digests=$(docker image inspect "$image_with_tag" --format '{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null || true)
    version_label=$(detect_image_version "$image_with_tag" 2>/dev/null || true)

    echo "📦 Image: $image_with_tag"
    if [[ -n "$image_id" ]]; then
        echo "🆔 ID: $image_id"
    fi

    if [[ -n "$repo_digests" ]]; then
        echo "🔖 RepoDigests:"
        echo "$repo_digests" | sed 's/^/  - /'
    fi

    if [[ -n "$version_label" ]]; then
        echo "🏷️  Detected app version: $version_label"
    else
        echo "ℹ️ 未在镜像标签中发现常见的版本信息字段。"
        echo "   你可以尝试在镜像内部执行版本命令，例如："
        echo "     docker run --rm $image_with_tag --version"
        echo "   或参考该镜像的官方文档。"
    fi
}

cmd_channel() {
    local subcmd="$1"
    local arg="$2"

    load_config

    case "$subcmd" in
        list|ls)
            echo "✅ Supported channels: ${SUPPORTED_CHANNELS[*]}"
            ;;
        current|cur|"" )
            echo "✅ Current channel: $CURRENT_CHANNEL"
            ;;
        set|use)
            if [[ -z "$arg" ]]; then
                echo "Usage: $(basename "$0") channel set <CHANNEL>"
                return 1
            fi
            if ! is_supported_channel "$arg"; then
                echo "❌ Unsupported channel: $arg"
                echo "   Supported: ${SUPPORTED_CHANNELS[*]}"
                return 1
            fi
            save_channel "$arg"
            echo "✅ Channel switched to: $arg"
            ;;
        *)
            echo "Usage: $(basename "$0") channel [list|current|set <CHANNEL>]"
            return 1
            ;;
    esac
}

main() {
    local cmd="$1"
    shift || true

    load_config

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
        version)
            cmd_version "$@"
            ;;
        channel|ch)
            cmd_channel "$@"
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
