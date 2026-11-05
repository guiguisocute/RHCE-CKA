# CKA-01 集群架构与组件

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Cluster Architecture, Installation & Configuration (25%)」+「Troubleshooting (30%)」的基础 ｜ **建议用时**：4 h ｜ **难度**：★☆☆
>
> **前置**：[F5 Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md) · [RHCSA-10 Podman 容器](../rhcsa/10-containers-podman.md)
> **后续**：[CKA-02 kubectl 高效操作](02-kubectl-efficiency.md) · [CKA-03 用 kubeadm 搭建集群](03-kubeadm-install.md)
> **关联**（跨轨道）：[F2 systemd 与 journald](../00-foundations/02-systemd-journald.md) · [F6 TLS/PKI 基础](../00-foundations/06-tls-pki-basics.md) · [CKA-15 排错](15-troubleshooting.md)

## 1. 这个知识点在网络中的位置

这是整个 CKA 轨道的地基：后面装集群（K3）、升级和备份（K4）、高可用（K5）、排错（K15）都是在操作这一页里的某个组件。
用 docker compose 时，你只有一台机器、一个 dockerd；Kubernetes 把「接收指令、存状态、决定放哪、真正启动容器」拆成了多个独立组件，分布在多台机器上。
**排错的本质就是：判断是哪个组件出了问题，再用 Linux 手段（systemd、日志、证书、网络）修好它。**

## 2. 核心概念

### 2.1 控制平面（Control Plane）

| 组件 | 职责 | 在 kubeadm 集群里的形态 |
|---|---|---|
| `kube-apiserver` | 唯一入口：认证 → 鉴权 → 准入控制 → 读写 etcd。所有组件都只和它通信 | 静态 Pod，`/etc/kubernetes/manifests/kube-apiserver.yaml`，端口 6443 |
| `etcd` | 分布式 KV 数据库，保存集群**全部状态**（备份它 = 备份集群） | 静态 Pod，数据目录 `/var/lib/etcd`，端口 2379/2380 |
| `kube-scheduler` | 给还没分配节点的 Pod 选节点（资源、亲和性、污点……） | 静态 Pod，端口 10259 |
| `kube-controller-manager` | 跑各种控制循环：Deployment→ReplicaSet→Pod、Node 状态、ServiceAccount token 等 | 静态 Pod，端口 10257 |
| `cloud-controller-manager` | 对接云厂商（LoadBalancer、云盘）；自建集群一般没有 | — |

### 2.2 工作节点（每个节点都有，包括控制平面节点）

| 组件 | 职责 | 形态 |
|---|---|---|
| `kubelet` | 节点代理：从 apiserver 领 Pod，调 CRI 启动容器，上报状态；还负责启动**静态 Pod** | **systemd 服务**（不是 Pod！），配置 `/var/lib/kubelet/config.yaml` |
| 容器运行时（containerd / CRI-O） | 通过 CRI 接口被 kubelet 调用，真正拉镜像、起容器 | systemd 服务，socket `/run/containerd/containerd.sock` |
| `kube-proxy` | 把 Service 的虚拟 IP 翻译成 iptables/IPVS/nftables 规则 | DaemonSet（有的 CNI 如 Cilium 可以替代它） |

### 2.3 插件（Addons）

- **CNI 网络插件**（Calico/Cilium/Flannel）：给 Pod 分 IP、打通跨节点网络 → [K8](08-extension-interfaces-crd.md)
- **CoreDNS**：集群内 DNS，`<svc>.<ns>.svc.cluster.local` → [K11](11-services-dns.md)
- **metrics-server**：`kubectl top` 的数据来源 → [K15](15-troubleshooting.md)

### 2.4 一次 `kubectl apply` 发生了什么

```text
kubectl ──HTTPS──▶ kube-apiserver ──(认证 → RBAC 鉴权 → 准入)──▶ etcd（写入 Deployment）
                         ▲
controller-manager ──watch──┘  发现新 Deployment → 创建 ReplicaSet → 创建 Pod（nodeName 为空）
scheduler ──watch──▶ 为 Pod 选节点，写回 nodeName
kubelet(该节点) ──watch──▶ 调 CRI(containerd) 拉镜像、起容器 → 调 CNI 分配 IP → 上报 Running
```

关键思想：**声明式 + 控制循环**。你写的是「期望状态」，各控制器不停地把「实际状态」往期望状态拉。这就是 K8s 自愈的来源。

### 2.5 docker compose ↔ Kubernetes 架构对照

| docker / compose | Kubernetes |
|---|---|
| `dockerd` 守护进程（单机） | apiserver + scheduler + controller-manager（集群大脑） |
| compose 项目状态存在本机 | 状态存在 etcd |
| `docker run` 直接起容器 | 你只提交对象，kubelet 才真正起容器 |
| `containerd`（docker 底层也是它） | 同一个 containerd，通过 CRI 被 kubelet 调用 |
| `docker network`（bridge） | CNI 插件提供的扁平 Pod 网络（每个 Pod 一个 IP） |
| `restart: always` | kubelet 重启容器 + 控制器重建 Pod |

### 2.6 静态 Pod（Static Pod）

kubelet 会直接运行 `staticPodPath`（kubeadm 默认 `/etc/kubernetes/manifests/`）里的 YAML，不需要 apiserver。
控制平面组件就是这样「先有鸡」的。改这些文件 → kubelet 自动重建对应 Pod。**排错时最常改的就是这几个文件。**
在 apiserver 里看到的 `kube-apiserver-<节点名>` 只是「镜像 Pod」，用 `kubectl delete` 删不掉它。

## 3. 必会操作

```bash
kubectl cluster-info                                   # apiserver 和 CoreDNS 地址
kubectl get nodes -o wide                              # 节点状态、内部 IP、OS、内核、容器运行时版本
kubectl get pods -n kube-system -o wide                # 控制平面静态 Pod、CoreDNS、kube-proxy、CNI
kubectl get --raw='/readyz?verbose'                    # apiserver 自检（各项 ok/failed）
kubectl api-resources | head -30                       # 所有资源类型、缩写、是否带命名空间、apiGroup
kubectl explain pod.spec.containers --recursive | less # 查字段（考场里比翻文档快）
kubectl describe node <node>                           # Conditions、Capacity/Allocatable、Taints、事件

# 在节点上（ssh 进去）
sudo ls /etc/kubernetes/manifests/                     # etcd / kube-apiserver / kube-controller-manager / kube-scheduler
sudo cat /var/lib/kubelet/config.yaml | grep -i staticPodPath
systemctl status kubelet containerd                    # 两个 systemd 服务
sudo journalctl -u kubelet -f                          # kubelet 日志（节点 NotReady 先看这里）
sudo crictl ps                                         # 不经过 apiserver，直接看容器（apiserver 挂了也能用）
sudo crictl logs <容器ID>                               # apiserver 挂掉时查它自己的日志
sudo ls /etc/kubernetes/pki/                           # 集群证书（CA、apiserver、etcd……）
```

## 4. 考试坑点

- **kubelet 不是 Pod**：`kubectl get pods -A` 里找不到 kubelet，它挂了要去节点上 `systemctl`/`journalctl`。
- apiserver 挂了，`kubectl` 全部报 `connection refused`，这时只能 `crictl` + 看静态 Pod 清单 + `/var/log/pods/`、`/var/log/containers/`。
- 改静态 Pod 清单时先 `cp` 一份到别处备份；**不要**把备份放在 `/etc/kubernetes/manifests/` 里（kubelet 会把它也当成 Pod 启动）。
- 改完清单要等几十秒 kubelet 才会重建；用 `watch crictl ps` 观察。
- 端口要背：6443（apiserver）、2379/2380（etcd）、10250（kubelet）、10257/10259（controller-manager/scheduler）、30000-32767（NodePort）。

## 5. 动手练习

- 搭环境：[labs/cka/00-lab-setup.md](../../labs/cka/00-lab-setup.md)（先用 kind 快速体验，再用 kubeadm 正式搭）
- 练习：[labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md) 中「集群架构」相关题
- 自己做个小实验：在控制平面节点上 `sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/`，创建一个 Pod 看它一直 Pending，再移回来观察恢复。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| 组件总览 | [concepts/overview/components.md](../../references/cka/kubernetes-docs/concepts/overview/components.md) | kubernetes.io/docs/concepts/overview/components/ |
| 集群架构 | [concepts/architecture/_index.md](../../references/cka/kubernetes-docs/concepts/architecture/_index.md) | kubernetes.io/docs/concepts/architecture/ |
| 节点 | [concepts/architecture/nodes.md](../../references/cka/kubernetes-docs/concepts/architecture/nodes.md) | kubernetes.io/docs/concepts/architecture/nodes/ |
| 控制器模式 | [concepts/architecture/controller.md](../../references/cka/kubernetes-docs/concepts/architecture/controller.md) | kubernetes.io/docs/concepts/architecture/controller/ |
| 控制平面与节点通信 | [concepts/architecture/control-plane-node-communication.md](../../references/cka/kubernetes-docs/concepts/architecture/control-plane-node-communication.md) | kubernetes.io/docs/concepts/architecture/control-plane-node-communication/ |
| 静态 Pod | [tasks/configure-pod-container/static-pod.md](../../references/cka/kubernetes-docs/tasks/configure-pod-container/static-pod.md) | kubernetes.io/docs/tasks/configure-pod-container/static-pod/ |
| 端口与协议 | [reference/networking/ports-and-protocols.md](../../references/cka/kubernetes-docs/reference/networking/ports-and-protocols.md) | kubernetes.io/docs/reference/networking/ports-and-protocols/ |
| crictl 调试节点 | [tasks/debug/debug-cluster/crictl.md](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/crictl.md) | kubernetes.io/docs/tasks/debug/debug-cluster/crictl/ |

考场技巧：在 kubernetes.io 搜索框输入 `static pod`、`ports and protocols` 直接能定位；`kubectl explain` 不需要浏览器。

## 7. 自测清单

- [ ] 能画出控制平面 4 个组件 + 节点 3 个组件，并说出各自端口和形态（静态 Pod / systemd / DaemonSet）
- [ ] 能讲清楚一次 `kubectl apply -f deploy.yaml` 依次经过哪些组件
- [ ] 知道静态 Pod 清单目录在哪、怎么从 kubelet 配置里确认它
- [ ] apiserver 挂了的情况下，能用 `crictl` 找到它的容器并查看日志
- [ ] 能说出 docker compose 的 5 个概念各自对应 K8s 里的什么
