# RHCSA-10 Podman 容器：镜像、运行、持久存储与 systemd 托管

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Manage containers」（RHEL 9 版考纲；⚠️ 据第三方资料 RHEL 10 版可能已移除，以官方为准） ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[S9 防火墙与 SELinux](09-security-firewalld-selinux.md) · [F5 Docker → Podman → Kubernetes](../00-foundations/05-containers-docker-to-k8s.md) · [F2 systemd 与 journald](../00-foundations/02-systemd-journald.md)
> **后续**：[CKA-01 集群架构与组件](../cka/01-architecture.md)
> **关联**（跨轨道）：[CKA-08 扩展接口：CNI/CSI/CRI](../cka/08-extension-interfaces-crd.md)（K8s 节点上用的是 containerd/CRI-O，`crictl` 的用法和 podman 很像） · [CKA-09 工作负载](../cka/09-workloads.md) · [RHCE-11 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（`containers.podman` collection）

## 1. 这个知识点在网络中的位置

你已经会 Docker，这一节是**最省力的一节**：Podman 的命令行几乎与 Docker 一致（`alias docker=podman` 基本能用）。真正的新东西只有三个：

1. **rootless**（普通用户运行容器，没有守护进程）；
2. **SELinux 卷标签** `:Z` / `:z`；
3. **让容器作为 systemd 服务开机自启**——RHEL 9.x 以后推荐用 **Quadlet**，`podman generate systemd` 已被标记为弃用。

不管 RHEL 10 版 EX200 是否还考容器，这一节都是你从 Docker 走向 [CKA](../cka/README.md) 的桥：Pod、镜像仓库、卷、端口映射这些概念在 K8s 里一一对应。

## 2. 核心概念

| Docker | Podman | 说明 |
|---|---|---|
| `dockerd` 守护进程 | **无守护进程**（fork/exec） | 每个容器是普通进程，可被 systemd 直接管理 |
| 需要 root 或 docker 组 | **rootless** 默认可用 | 普通用户的镜像在 `~/.local/share/containers/` |
| `docker compose` | `podman compose`（需额外组件）/ Quadlet | 考试用 Quadlet 或 podman 命令 |
| Docker Hub 默认 | `/etc/containers/registries.conf` 的 `unqualified-search-registries` | 建议总写完整镜像名 `registry.access.redhat.com/ubi10/ubi` |
| Dockerfile | **Containerfile**（Dockerfile 也认） | 语法相同 |
| — | `skopeo` | 不拉取镜像就能查看/复制远程镜像 |
| — | Pod（`podman pod`） | 和 K8s Pod 同概念：共享网络命名空间的一组容器 |

SELinux 卷标签：`-v /srv/web:/usr/share/nginx/html:Z`——`Z` 把目录重新标记为**本容器私有**（`container_file_t` + 专属 MCS 标签）；`z` 为多容器共享。不加的话容器进程会被 SELinux 拒绝读写。

## 3. 必会操作

```bash
dnf install -y container-tools                # podman、skopeo、buildah 一次装齐

# ---------- 镜像 ----------
podman login registry.redhat.io               # 红帽镜像仓库（需红帽账号）；registry.access.redhat.com 的 UBI 镜像无需登录
podman search httpd
skopeo inspect docker://registry.access.redhat.com/ubi10/ubi | head -30   # 不拉取先看元数据
podman pull registry.access.redhat.com/ubi10/httpd-24                     # 镜像名以实际仓库为准
podman images; podman inspect <镜像> | less
podman image rm <镜像>

# ---------- 构建 ----------
cat > Containerfile <<'EOF'
FROM registry.access.redhat.com/ubi10/ubi
RUN dnf install -y httpd && dnf clean all
COPY index.html /var/www/html/
EXPOSE 80
CMD ["/usr/sbin/httpd", "-DFOREGROUND"]
EOF
echo hello > index.html
podman build -t localhost/myweb:1.0 .

# ---------- 运行与管理 ----------
podman run -d --name web -p 8080:80 localhost/myweb:1.0
podman ps; podman ps -a; podman logs web
podman exec -it web /bin/bash
podman stop web; podman start web; podman rm -f web

# ---------- 持久存储（注意 :Z） ----------
mkdir -p ~/webdata && echo persistent > ~/webdata/index.html
podman run -d --name web -p 8080:80 -v ~/webdata:/var/www/html:Z localhost/myweb:1.0
curl localhost:8080

# ---------- 作为 systemd 服务开机自启：Quadlet（rootless 用户级） ----------
# 前提：以该用户**真正登录**（ssh user@localhost），不要用 su，否则 systemctl --user 连不上用户总线
loginctl enable-linger $USER                  # 让用户服务在未登录时也运行、开机启动（root 执行时写用户名）
mkdir -p ~/.config/containers/systemd
cat > ~/.config/containers/systemd/web.container <<'EOF'
[Unit]
Description=My web container

[Container]
Image=localhost/myweb:1.0
ContainerName=web
PublishPort=8080:80
Volume=%h/webdata:/var/www/html:Z

[Install]
WantedBy=default.target
EOF
podman rm -f web 2>/dev/null                  # 删掉同名的手动容器
systemctl --user daemon-reload                # Quadlet 生成 web.service
systemctl --user start web.service
systemctl --user status web.service
# 开机自启由 [Install] 段 + linger 保证；Quadlet 生成的单元不需要（也不能）再 systemctl enable

# ---------- 旧方法（RHEL 9 早期教材常见，已弃用但仍可用） ----------
# podman generate systemd --name web --files --new
# mv container-web.service ~/.config/systemd/user/ && systemctl --user daemon-reload
# systemctl --user enable --now container-web.service

# ---------- root 级（系统服务）----------
# Quadlet 文件放 /etc/containers/systemd/，用 systemctl（不带 --user）管理
```

## 4. 考试坑点

- **`su - user` 后 `systemctl --user` 报 "Failed to connect to bus"**：要用 `ssh user@localhost` 登录。
- **忘记 `loginctl enable-linger`** → 用户注销或重启后容器服务不运行。
- **卷没加 `:Z`** → 容器内 "Permission denied"；`ls -Z` 可以看到标签差异。
- rootless 容器**不能绑定 1024 以下端口**（默认），题目一般会给高端口。
- 题目要求「以用户 X 运行」时，镜像也要以用户 X 拉取/构建（root 和普通用户的镜像存储是分开的）。
- Quadlet 文件扩展名必须是 `.container`，改了文件要 `systemctl --user daemon-reload`。
- 报名前确认你考的 EX200 版本是否包含容器目标；包含的话以上全部要练。

## 5. 动手练习

- [练习题集 · S10 Podman 容器](../../labs/rhcsa/practice-set-1.md#s10)
- 进阶：同样的 Web 服务用 K8s Deployment + Service 再做一遍，见 [CKA-09 工作负载](../cka/09-workloads.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 10《Building, running, and managing containers》：<https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/building_running_and_managing_containers/index>
- 离线 PDF：运行 [`scripts/fetch-rhel-docs.sh`](../../scripts/fetch-rhel-docs.sh)
- **考场查法**：
  - `man podman-run`（`/--volume` 里有 `:Z` 的解释）、`man podman-build`
  - `man podman-systemd.unit`：**Quadlet 的全部字段和示例**（`Image=`、`PublishPort=`、`Volume=`）
  - `man skopeo-inspect`、`man containers-registries.conf`
  - `man loginctl` → `/enable-linger`
  - `podman <子命令> --help`

## 7. 自测清单

- [ ] 能用 skopeo 查看远程镜像的标签/架构而不拉取
- [ ] 能用 Containerfile 构建镜像并运行，映射端口
- [ ] 能挂载宿主目录作为持久存储，并解释 `:Z` 与 `:z` 的区别
- [ ] 能以普通用户身份把容器配置为开机自启的 systemd 用户服务（Quadlet + linger），重启后验证
- [ ] 能把 `docker run` / `docker compose` 的一个服务改写成 Podman 命令或 Quadlet 文件
- [ ] 能说出 Podman Pod 与 Kubernetes Pod 的对应关系
