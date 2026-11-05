# F5 Docker → Podman → Kubernetes：迁移你的容器经验

> **轨道**：[公共基础](README.md) ｜ **考纲**：EX200（RHEL 9 版）「Manage containers」；CKA 全部领域的前提 ｜ **建议用时**：4 h ｜ **难度**：★★☆
>
> **前置**：[F2 systemd 与 journald](02-systemd-journald.md) · [F3 网络基础](03-networking-basics.md)
> **后续**：[RHCSA-10 Podman 容器](../rhcsa/10-containers-podman.md) → [CKA-01 集群架构与组件](../cka/01-architecture.md)
> **关联**（跨轨道）：[CKA-08 CNI/CSI/CRI](../cka/08-extension-interfaces-crd.md) · [CKA-09 工作负载](../cka/09-workloads.md) · [CKA-11 Service 与 CoreDNS](../cka/11-services-dns.md) · [CKA-14 存储](../cka/14-storage.md) · [F4 YAML](04-yaml.md)

## 1. 这个知识点在网络中的位置

你已经会 docker / docker compose，这是三门考试里你**最有优势**的部分。这一篇做两次「翻译」：

1. **Docker → Podman**：RHEL 上的容器工具。命令几乎一样，但没有守护进程、默认可以 rootless、和 systemd/SELinux 深度集成。
2. **Docker Compose → Kubernetes**：从「一台机器上编排几个容器」升级到「集群里声明期望状态」。

## 2. 核心概念

### 2.1 容器到底是什么（理解了才能排错）

| 底层机制 | 作用 | 出现在 |
|---|---|---|
| namespace（pid / net / mnt / uts / ipc / user） | 隔离进程能「看到」的东西 | Pod 内多个容器共享 net namespace，所以能用 `localhost` 互访 |
| cgroup（RHEL 9/10 默认 v2） | 限制 CPU/内存等资源 | K8s 的 `resources.limits`；kubelet 与容器运行时都要用 **systemd** cgroup 驱动 |
| 镜像分层 + OCI 标准 | 镜像格式与运行时规范统一 | docker build 出来的镜像，podman / containerd 都能跑 |
| SELinux 标签 | RHEL 上额外的一层隔离 | podman 挂载目录要加 `:Z` / `:z` |

### 2.2 Docker vs Podman

| | Docker | Podman（RHEL） |
|---|---|---|
| 架构 | `dockerd` 守护进程，客户端通过 socket 调用 | **无守护进程**，每个容器是 `conmon` 监管的普通进程 |
| 权限 | 通常要 root 或 docker 组 | 普通用户可直接运行（rootless） |
| 命令 | `docker run/ps/logs/exec/build` | `podman run/ps/logs/exec/build`，参数基本相同；装 `podman-docker` 包后可直接敲 `docker` |
| 开机自启 | `--restart=always` + dockerd 自启 | 交给 **systemd**：Quadlet 文件（推荐），或旧的 `podman generate systemd`（已弃用） |
| 镜像仓库配置 | `/etc/docker/daemon.json` | `/etc/containers/registries.conf`（短名称搜索列表 `unqualified-search-registries`） |
| 镜像存储 | `/var/lib/docker` | root：`/var/lib/containers/storage`；rootless：`~/.local/share/containers/storage` |
| 编排 | docker compose | `podman kube play`（直接跑 K8s YAML！）；podman-compose 非官方支持 |
| 镜像检查 | `docker inspect` | `podman inspect`；远程查看不拉取：`skopeo inspect docker://...` |

### 2.3 Compose → Kubernetes 翻译表

| docker compose | Kubernetes | 详见 |
|---|---|---|
| 一个 `service` | **Deployment**（管理多个 Pod 副本） | [CKA-09](../cka/09-workloads.md) |
| 一个容器实例 | **Pod**（最小调度单位，可含多个容器） | [CKA-01](../cka/01-architecture.md) |
| `ports: "8080:80"` | **Service**（ClusterIP / NodePort / LoadBalancer） | [CKA-11](../cka/11-services-dns.md) |
| 服务名互访 | CoreDNS：`web.default.svc.cluster.local` | [CKA-11](../cka/11-services-dns.md) |
| `volumes:` 命名卷 | **PersistentVolumeClaim** + StorageClass | [CKA-14](../cka/14-storage.md) |
| `environment:` / `env_file:` | **ConfigMap** / **Secret** | [CKA-09](../cka/09-workloads.md) |
| `restart: always` | Deployment 控制器自动重建（自愈） | [CKA-09](../cka/09-workloads.md) |
| `healthcheck:` | liveness / readiness / startup **probe** | [CKA-09](../cka/09-workloads.md) |
| `depends_on:` | 没有直接对应：initContainers + readinessProbe | [CKA-09](../cka/09-workloads.md) |
| `deploy.resources.limits` | `resources.requests/limits` | [CKA-10](../cka/10-scheduling.md) |
| `networks:` 隔离 | **NetworkPolicy** | [CKA-12](../cka/12-network-policy.md) |
| 反向代理容器（nginx/traefik） | **Ingress** / **Gateway API** | [CKA-13](../cka/13-ingress-gateway-api.md) |

### 2.4 Kubernetes 里已经没有 Docker 了

- Kubernetes 通过 **CRI**（Container Runtime Interface）调用容器运行时；v1.24 起移除了 dockershim，常见运行时是 **containerd** 和 **CRI-O**。
- 节点上排查容器用 **`crictl`**（对接 CRI），而不是 `docker`。docker build 出来的镜像依然可以用（OCI 兼容）。

## 3. 必会操作

```bash
# —— Podman：和 docker 一模一样的部分 ——
podman search nginx                       # 按 registries.conf 中的仓库搜索
podman pull registry.access.redhat.com/ubi9/ubi   # 完整名称拉取（考试推荐写全名）
podman images
podman run -d --name web -p 8080:80 docker.io/library/nginx:latest
podman ps -a
podman logs -f web
podman exec -it web /bin/sh
podman stop web && podman rm web

# —— Podman：RHEL 特色 ——
skopeo inspect docker://registry.access.redhat.com/ubi9/ubi   # 不拉镜像就看元数据
podman run -d --name web -p 8080:80 \
  -v /srv/web:/usr/share/nginx/html:Z docker.io/library/nginx  # :Z 自动打 SELinux 标签
podman kube generate web > web-pod.yaml    # 从运行中的容器生成 K8s YAML（通往 CKA 的桥）
podman kube play web-pod.yaml              # 用 K8s YAML 在单机上跑

# —— rootless 容器开机自启（Quadlet，RHEL 9.2+/10）——
mkdir -p ~/.config/containers/systemd
cat > ~/.config/containers/systemd/web.container <<'EOF'
[Container]
Image=docker.io/library/nginx:latest
PublishPort=8080:80
Volume=%h/web:/usr/share/nginx/html:Z
# %h 是 systemd 说明符，展开为当前用户的家目录

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload             # Quadlet 生成 web.service
systemctl --user start web.service
loginctl enable-linger $USER               # 用户未登录时也能在开机后运行

# —— Kubernetes 节点上：crictl 代替 docker ——
sudo crictl ps                             # 运行中的容器
sudo crictl pods                           # Pod 沙箱
sudo crictl logs <容器ID>                  # apiserver 挂了、kubectl 用不了时看控制面日志
sudo crictl images
```

## 4. 考试坑点

- **镜像短名称的歧义**：`podman pull nginx` 可能会交互式询问选哪个仓库，脚本/考试中会卡住。写全名 `docker.io/library/nginx`，或按题目给的仓库地址写。
- **rootless 容器重启后没了**：必须 `loginctl enable-linger <用户>`，并且用 `systemctl --user` 管理（不要 `sudo systemctl`）。
- **以 `su - user` 切换用户后 `systemctl --user` 报错**：`su` 不会建立用户的 systemd 会话。用 `ssh user@localhost` 登录或用 `machinectl shell user@` 再操作（以官方文档为准）。
- **挂载目录忘了 `:Z`**：SELinux 拒绝访问，容器内 Permission denied。
- **CKA 上用 `docker` 排查节点**：节点上大概率没有 docker，用 `crictl`。
- **把 Pod 当容器**：Pod 删了就没了，要自愈就得用 Deployment/StatefulSet/DaemonSet 管理。
- RHEL 10 版 RHCSA 考纲据报道已移除容器章节（以 [EX200 官方页面](https://www.redhat.com/en/services/training/ex200-red-hat-certified-system-administrator-rhcsa-exam)为准），但这部分仍是学 CKA 的最佳跳板。

## 5. 动手练习

- [`labs/rhcsa/practice-set-1.md`](../../labs/rhcsa/practice-set-1.md)：rootless 容器 + Quadlet 自启题
- [`labs/cka/00-lab-setup.md`](../../labs/cka/00-lab-setup.md)：搭集群时体会 containerd / crictl
- 自测：把你实验室里一个真实的 compose 项目，先用 `podman kube play` 跑起来，再部署到 K8s 集群。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：[`references/cka/kubernetes-docs/reference/kubectl/docker-cli-to-kubectl.md`](../../references/cka/kubernetes-docs/reference/kubectl/docker-cli-to-kubectl.md)（docker 命令 → kubectl 命令对照，官方出品）
- 离线：[`references/cka/kubernetes-docs/tasks/configure-pod-container/translate-compose-kubernetes.md`](../../references/cka/kubernetes-docs/tasks/configure-pod-container/translate-compose-kubernetes.md)（用 kompose 把 compose 转成 K8s 资源）
- 离线：[`references/cka/kubernetes-docs/concepts/workloads/pods/_index.md`](../../references/cka/kubernetes-docs/concepts/workloads/pods/_index.md)（Pod 概念）
- 离线：[`references/cka/kubernetes-docs/concepts/containers/cri.md`](../../references/cka/kubernetes-docs/concepts/containers/cri.md)（CRI）
- 离线：[`references/cka/kubernetes-docs/setup/production-environment/container-runtimes.md`](../../references/cka/kubernetes-docs/setup/production-environment/container-runtimes.md)（containerd / CRI-O 安装与 cgroup 驱动）
- 离线：[`references/cka/kubernetes-docs/tasks/debug/debug-cluster/crictl.md`](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/crictl.md)（crictl 用法）
- RHEL 在线：[Building, running, and managing containers](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/building_running_and_managing_containers/index)

考场查法：

```bash
man podman-run              # 每个子命令都有独立 man 页：podman-<子命令>
man podman-systemd.unit     # Quadlet 文件的全部字段（[Container] 段）
man containers-registries.conf
man skopeo-inspect
crictl --help
```

## 7. 自测清单

- [ ] 能说出 Podman 与 Docker 的 3 个关键区别（守护进程、rootless、systemd 集成）
- [ ] 能用 Quadlet 让一个 rootless 容器开机自启，并在重启后验证
- [ ] 能把 compose 的 `ports` / `volumes` / `environment` / `restart` 分别对应到 K8s 对象
- [ ] 能解释为什么 K8s 节点上用 `crictl` 而不是 `docker`
- [ ] 能用 `podman kube generate` 从容器生成一份 K8s YAML，并读懂它
