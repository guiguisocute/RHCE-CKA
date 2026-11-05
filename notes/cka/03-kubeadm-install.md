# CKA-03 用 kubeadm 搭建集群

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Prepare underlying infrastructure for installing a Kubernetes cluster」「Create and manage Kubernetes clusters using kubeadm」 ｜ **建议用时**：8 h ｜ **难度**：★★☆
>
> **前置**：[CKA-01 集群架构与组件](01-architecture.md) · [RHCSA-06 软件、计划任务、时间、引导](../rhcsa/06-software-scheduling-boot.md)
> **后续**：[CKA-04 集群生命周期](04-cluster-lifecycle.md) · [CKA-08 扩展接口：CNI/CSI/CRI](08-extension-interfaces-crd.md)
> **关联**（跨轨道）：[RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md) · [RHCSA-04 本地存储与 LVM](../rhcsa/04-local-storage-lvm.md)（swap） · [F2 systemd](../00-foundations/02-systemd-journald.md) · [F6 TLS/PKI](../00-foundations/06-tls-pki-basics.md)

## 1. 这个知识点在网络中的位置

kubeadm 是官方的「集群引导工具」：它生成证书、写好静态 Pod 清单、配置 kubelet，把 K1 里那些组件按正确方式拼起来。
「准备底层基础设施」这条考纲考的是**Linux 系统管理**：软件源、内核模块、sysctl、swap、容器运行时、cgroup 驱动——全部是 RHCSA 的知识换了个场景。
完整的逐步命令（Ubuntu + RHEL 两套）在 [labs/cka/00-lab-setup.md](../../labs/cka/00-lab-setup.md)，这里讲清楚每一步**为什么**。

## 2. 核心概念

### 2.1 安装前提（每个节点都要做）

| 步骤 | 为什么 | 对应 RHCSA 知识 |
|---|---|---|
| 主机名唯一、MAC/`product_uuid` 唯一 | 节点身份 | `hostnamectl` |
| 节点之间网络互通、端口放行 | 6443、10250、2379-2380 等 | firewalld |
| 关闭 swap（或显式配置 kubelet 容忍 swap） | kubelet 默认检测到 swap 就拒绝启动 | `swapoff -a` + 改 `/etc/fstab` |
| 开启 `net.ipv4.ip_forward=1` | Pod 流量需要内核转发 | `/etc/sysctl.d/*.conf` |
| 加载 `overlay`、`br_netfilter`（多数 CNI 需要） | 容器分层文件系统、让 iptables 看到网桥流量 | `/etc/modules-load.d/*.conf` |
| 安装容器运行时（containerd / CRI-O） | kubelet 通过 CRI 调用它 | dnf/apt、systemd |
| **cgroup 驱动统一用 systemd** | kubelet 和运行时驱动不一致会导致不稳定 | cgroups v2 |
| 安装同一小版本的 kubelet / kubeadm / kubectl 并锁定版本 | 升级要走专门流程（K4） | 软件源、`apt-mark hold` / `exclude=` |

### 2.2 软件源：pkgs.k8s.io

旧的 `apt.kubernetes.io` / `yum.kubernetes.io` 已废弃。新仓库**每个小版本一个地址**：
`https://pkgs.k8s.io/core:/stable:/v1.37/deb/`（或 `/rpm/`）。想装/升级到别的小版本，要先改仓库 URL 里的版本号。

### 2.3 `kubeadm init` 做了什么

1. **preflight** 检查（swap、端口、运行时、内核参数……）
2. 生成 CA 和各组件证书 → `/etc/kubernetes/pki/`
3. 生成 kubeconfig → `/etc/kubernetes/{admin,super-admin,kubelet,controller-manager,scheduler}.conf`
4. 写静态 Pod 清单 → `/etc/kubernetes/manifests/`
5. 等控制平面就绪，打标签/污点（`node-role.kubernetes.io/control-plane:NoSchedule`）
6. 生成 bootstrap token，安装 CoreDNS 和 kube-proxy
7. 打印 `kubeadm join ...` 命令

每一步都能用 `kubeadm init phase <阶段>` 单独执行——这也是排错时「只重做某一步」的方法。

### 2.4 常用参数

| 参数 | 作用 |
|---|---|
| `--pod-network-cidr=10.244.0.0/16` | Pod 网段，要和 CNI 配置一致（Flannel 默认 10.244.0.0/16，Calico 常用 192.168.0.0/16） |
| `--apiserver-advertise-address=<本机IP>` | 多网卡时指定 apiserver 监听地址 |
| `--control-plane-endpoint=<LB或DNS>:6443` | 以后要做 HA 必须在 init 时就指定（见 [K5](05-ha-control-plane.md)） |
| `--kubernetes-version=v1.37.x` | 指定版本 |
| `--config kubeadm.yaml` | 用配置文件（`kubeadm config print init-defaults` 生成模板） |
| `--cri-socket` | 节点上有多个运行时时指定 |

## 3. 必会操作

```bash
# —— 控制平面节点 ——
sudo kubeadm config images pull                         # 预拉镜像（可选）
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.56.10
mkdir -p $HOME/.kube && sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl get nodes                                       # 此时 NotReady：还没装 CNI
kubectl apply -f <CNI 清单>                              # 装 CNI 后变 Ready（见 lab）

# —— 生成 join 命令（token 默认 24h 过期）——
kubeadm token list
kubeadm token create --print-join-command

# —— 工作节点 ——
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# —— 验证 ——
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl run t --image=nginx && kubectl get pod t -o wide   # 能调度到 worker、拿到 Pod IP

# —— 推倒重来（实验用）——
sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d $HOME/.kube   # reset 不会清理 CNI 配置和 iptables
```

`kubeadm join` 失败常见原因：token 过期、时间不同步、6443 被防火墙拦、worker 上 kubelet/运行时没装好、swap 没关。

## 4. 考试坑点

- 考试里的「装集群/加节点」题通常给你**已有的机器**，要求补齐某些步骤（装包、改 sysctl、join）。题目里给了版本号就严格用那个版本。
- sysctl、内核模块、swap 都要**持久化**（写入 `/etc/sysctl.d/`、`/etc/modules-load.d/`、注释 `/etc/fstab` 中的 swap 行），不只是临时生效。
- `kubeadm init` 之后忘记复制 `admin.conf` → `kubectl` 报 `localhost:8080 refused`。
- 节点 `NotReady` 且 kubelet 日志里说 `cni plugin not initialized` → 还没装 CNI 或 `/etc/cni/net.d` 为空。
- containerd 包自带的 `config.toml` 可能禁用了 CRI 插件（`disabled_plugins = ["cri"]`），要用 `containerd config default` 重新生成并设置 `SystemdCgroup = true`，然后重启 containerd。
- RHEL 系：官方文档要求把 SELinux 设为 permissive；DNF5 环境下 `--disableexcludes=kubernetes` 要换成 `--setopt=disable_excludes=kubernetes`（以官方文档为准）。

## 5. 动手练习

- **必做**：按 [labs/cka/00-lab-setup.md](../../labs/cka/00-lab-setup.md) 方案 B 从零搭建 1 控制平面 + 2 worker，至少完整做两遍（一遍 Ubuntu、一遍 RHEL 系）。
- `kubeadm reset` 掉一个 worker，再用新 token 重新加入。
- 故意不关 swap 执行 `kubeadm init`，读懂 preflight 报错。
- [labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md) 中「集群安装」相关题。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| **安装 kubeadm（含软件源命令）** | [setup/.../kubeadm/install-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/install-kubeadm.md) | kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/ |
| **用 kubeadm 创建集群** | [setup/.../kubeadm/create-cluster-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm.md) | kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/ |
| **容器运行时（sysctl、cgroup 驱动、containerd）** | [setup/production-environment/container-runtimes.md](../../references/cka/kubernetes-docs/setup/production-environment/container-runtimes.md) | kubernetes.io/docs/setup/production-environment/container-runtimes/ |
| kubeadm 排错 | [setup/.../kubeadm/troubleshooting-kubeadm.md](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm.md) | kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/ |
| kubeadm init 参考 | [reference/setup-tools/kubeadm/kubeadm-init.md](../../references/cka/kubernetes-docs/reference/setup-tools/kubeadm/kubeadm-init.md) | kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/ |
| kubeadm join 参考 | [reference/setup-tools/kubeadm/kubeadm-join.md](../../references/cka/kubernetes-docs/reference/setup-tools/kubeadm/kubeadm-join.md) | kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/ |
| kubeadm token | [reference/setup-tools/kubeadm/kubeadm-token.md](../../references/cka/kubernetes-docs/reference/setup-tools/kubeadm/kubeadm-token.md) | kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/ |
| 添加 Linux 节点 | [tasks/administer-cluster/kubeadm/adding-linux-nodes.md](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/adding-linux-nodes.md) | kubernetes.io/docs/tasks/administer-cluster/kubeadm/adding-linux-nodes/ |
| 端口 | [reference/networking/ports-and-protocols.md](../../references/cka/kubernetes-docs/reference/networking/ports-and-protocols.md) | kubernetes.io/docs/reference/networking/ports-and-protocols/ |

考场技巧：搜索 `install kubeadm` 和 `container runtimes` 两页，sysctl/模块/containerd 配置都能直接复制。

## 7. 自测清单

- [ ] 不看文档说出安装前的 6 项准备，并说出各自如何持久化
- [ ] 能解释为什么 kubelet 和 containerd 都要用 systemd cgroup 驱动
- [ ] 能写出 pkgs.k8s.io 的仓库地址格式，知道换小版本要改哪里
- [ ] 能在 30 分钟内从干净的 3 台 VM 搭好可用集群
- [ ] token 过期后能重新生成 join 命令
- [ ] 能说出 `kubeadm init` 的主要阶段，以及证书、kubeconfig、静态 Pod 清单各放在哪
