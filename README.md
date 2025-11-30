# sync2acr / s2i 安装脚本

一个用于在本地快速安装并使用 `s2i` 小工具的脚本，帮助你把任意容器镜像同步到阿里云容器镜像服务（ACR），并提供常用的登录、拉取、重命名（打 tag）、推送、镜像清单复制（multi-arch mirror）及渠道管理能力。

## 主要特性
- 一键安装/卸载：将 `s2i` 安装到 `~/.local/bin`（或自定义目录）。
- ACR 优先支持：默认使用 `registry.cn-beijing.aliyuncs.com` 和你的命名空间。
- 常用子命令：`login` / `pull` / `rename` / `push` / `mirror` / `list` / `channel`，风格类似 `git`。
- 自动打 tag：`push` 会在需要时自动为镜像添加 ACR 前缀与命名空间。
- 多架构同步：`mirror` 使用 `docker buildx imagetools create` 在 registry 之间复制 multi-arch manifest，实现同一 tag 在 AMD64 / ARM64 上都能自动匹配架构。
- 支持渠道管理：默认渠道 `aliyun`；可列出/查看/切换当前渠道，配置写入 `~/.config/s2i/config`。

## 环境依赖
- 已安装并可用的 Docker CLI。
- Bash 4+（大多数 Linux / macOS 默认符合）。
- 拥有可推送至目标 ACR 命名空间的账号权限。

## 快速开始
```bash
# 1) 一行安装 s2i（默认装到 ~/.local/bin）
curl -fsSL https://raw.githubusercontent.com/ticoAg/sync2acr/main/sync2acr.sh | bash

# 或一行卸载
curl -fsSL https://raw.githubusercontent.com/ticoAg/sync2acr/main/sync2acr.sh | bash -s -- uninstall

# 2) 确保安装目录在 PATH 中
export PATH="$HOME/.local/bin:$PATH"

# 3) 登录（示例：默认 aliyun 渠道，输入密码时不回显）
s2i login <your-acr-username>

# 4) 推送镜像到 ACR（自动 pull -> tag -> push）
s2i push nginx:1.25

# 5) 渠道管理示例
s2i channel list        # 支持的渠道
s2i channel current     # 当前渠道（默认 aliyun）
s2i channel set aliyun  # 切换渠道并持久化
```

## 子命令速查
- `s2i login [CHANNEL] USERNAME`：登录 registry。`CHANNEL` 省略时默认 aliyun，可传 `aliyun|acr`、`docker.io` 或任意自定义 registry。
- `s2i pull IMAGE[:TAG]`：拉取镜像，等价于 `docker pull`。
- `s2i rename SRC_IMAGE[:TAG] TARGET_NAME`：仅本地打 tag，不推送；生成的目标为 `$ALIYUN_REGISTRY/$ALIYUN_NAMESPACE/TARGET_NAME:TAG`。
- `s2i push SRC_IMAGE[:TAG] [TARGET_NAME[:TARGET_TAG]]`：不存在就先拉取，再打 ACR tag 并推送。目标名/标签可省略。
- `s2i mirror SRC_IMAGE[:TAG] [TARGET_NAME[:TARGET_TAG]]`：使用 `docker buildx imagetools create` 把上游 multi-arch 镜像（如 Docker Hub）复制成 ACR 上的同名多架构镜像，适合需要一套 tag 同时兼容 AMD64 和 ARM64 的场景。
- `s2i list [--acr|--all]`：列出本地镜像，默认列出所有；`--acr` 只看当前渠道命名空间。
- `s2i version IMAGE[:TAG]`：查看本地镜像的 ID、RepoDigest 以及常见版本标签（如果存在）。
- `s2i channel [list|current|set <CHANNEL>]`：管理渠道并持久化到 `~/.config/s2i/config`。
- `s2i help`：查看内置帮助。

## 可配置项（修改 `s2i` 脚本）
- `ALIYUN_REGISTRY`：默认 `registry.cn-beijing.aliyuncs.com`。
- `ALIYUN_USERNAME`：用于提示的默认用户名。
- `ALIYUN_NAMESPACE`：你的 ACR 命名空间，影响推送目标。
- `DOCKERHUB_NAMESPACE`：使用 dockerhub 渠道时的 namespace，默认沿用 `ALIYUN_NAMESPACE`。
- `S2I_CHANNEL`：运行时可通过环境变量覆盖当前渠道；默认 `aliyun`。
- `S2I_REGISTRY_AUTO_CREATE_REPO`：是否假设 registry 支持按需自动创建仓库，默认 `true`。

## 常见问题
- **安装后无法直接运行 `s2i`？** 确认 `~/.local/bin` 已加入 PATH，或手动执行 `export PATH="$HOME/.local/bin:$PATH"`。
- **推送失败提示未登录？** 先执行 `s2i login <user>`，确保 Docker 配置中已记录该 registry 的登录信息。
- **仓库不存在怎么办？** 若你的 ACR 未开启“按需自动创建仓库”，需要在 ACR 控制台手动创建对应仓库后再推送。

## 许可证
本仓库未显式声明许可证；如需在团队或生产环境使用，请先与仓库维护者确认许可策略。
