# CKA-08 扩展接口：CNI / CSI / CRI，CRD 与 Operator

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Understand extension interfaces (CNI, CSI, CRI, etc.)」「Understand CRDs, install and configure operators」 ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[CKA-03 用 kubeadm 搭建集群](03-kubeadm-install.md) · [CKA-01 集群架构与组件](01-architecture.md)
> **后续**：[CKA-11 Service 与 CoreDNS](11-services-dns.md)（CNI 之上的网络） · [CKA-14 存储](14-storage.md)（CSI 之上的存储） · [CKA-13 Ingress 与 Gateway API](13-ingress-gateway-api.md)（Gateway API 本身就是一组 CRD）
> **关联**（跨轨道）：[F5 Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md)（OCI/runc/containerd） · [RHCSA-10 Podman 容器](../rhcsa/10-containers-podman.md) · [CKA-07 Helm 与 Kustomize](07-helm-kustomize.md)（Operator 通常用 Helm 安装）

## 1. 这个知识点在网络中的位置

Kubernetes 核心只定义「接口」，具体实现交给插件：**容器怎么跑（CRI）、网络怎么通（CNI）、存储怎么挂（CSI）**。
再往上，**CRD** 让你给 apiserver 增加新的资源类型，**Operator** = CRD + 一个持续运行的控制器，把运维经验写成代码。
考试不会让你写插件，但会要求：认出集群用的是哪个运行时/CNI/CSI、到哪个目录看配置、用 `crictl` 排查，以及安装 CRD/Operator 并创建对应的自定义资源。

## 2. 核心概念

### 2.1 三大接口

| 接口 | 谁调用谁 | 常见实现 | 节点上的痕迹 |
|---|---|---|---|
| **CRI**（Container Runtime Interface，gRPC） | kubelet → 运行时 | containerd、CRI-O（底层再调 runc 等 OCI 运行时） | `/run/containerd/containerd.sock`、`/etc/containerd/config.toml`；工具 `crictl` |
| **CNI**（Container Network Interface） | 运行时/kubelet 在建 Pod 沙箱时 → CNI 插件可执行文件 | Calico、Cilium、Flannel | 配置 `/etc/cni/net.d/`，二进制 `/opt/cni/bin/`；通常还有一个 DaemonSet |
| **CSI**（Container Storage Interface，gRPC） | kubelet / 外部 provisioner sidecar → CSI 驱动 | 各云盘、Ceph、NFS CSI、local-path 等 | `CSIDriver`/`CSINode` 对象；驱动以 DaemonSet + Deployment 运行 |

其他扩展点：设备插件（GPU）、准入 Webhook、调度器插件、API 聚合层。

### 2.2 docker 世界的对照

| Docker | Kubernetes |
|---|---|
| dockerd → containerd → runc | kubelet →(CRI)→ containerd → runc（**K8s 1.24 起已移除 dockershim**，不再直接用 dockerd） |
| `docker network create` 的 bridge/overlay 驱动 | CNI 插件 |
| `docker volume` 驱动插件 | CSI 驱动 |
| `docker ps` / `docker logs` | `crictl ps` / `crictl logs`（节点级、绕过 apiserver） |

### 2.3 CNI 要点

- K8s 网络模型：**每个 Pod 一个 IP，所有 Pod 之间无需 NAT 直接互通**；CNI 负责实现它。
- `kubeadm init --pod-network-cidr` 要和 CNI 的地址池一致。
- **NetworkPolicy 由 CNI 执行**：Flannel 不执行 NetworkPolicy；Calico、Cilium 支持（练 [K12](12-network-policy.md) 时要选对 CNI）。
- `/etc/cni/net.d/` 中按文件名字典序取第一个配置生效。

### 2.4 CRD 与 Operator

- **CRD**（CustomResourceDefinition，`apiextensions.k8s.io/v1`）：声明新类型的 group、版本、kind、作用域（Namespaced/Cluster）和 OpenAPI schema。创建后即可 `kubectl get <新资源>`。
- **CR**（Custom Resource）：该类型的实例，比如 `Certificate`、`Gateway`、`Prometheus`。
- **Operator**：监听 CR 并把实际状态调成期望状态的控制器（通常是一个 Deployment），常用 Helm 或一份清单安装。
- 只有 CRD 没有控制器 → 能创建 CR，但什么都不会发生。

## 3. 必会操作

```bash
# —— 识别运行时 / CRI ——
kubectl get nodes -o wide                       # CONTAINER-RUNTIME 列，如 containerd://2.x
sudo crictl info | head -20                     # 运行时状态与 CNI 配置是否加载
sudo crictl pods                                # Pod 沙箱
sudo crictl ps -a                               # 包括已退出的容器
sudo crictl logs <容器ID>
sudo crictl inspect <容器ID> | less
sudo crictl images; sudo crictl rmi --prune
cat /etc/crictl.yaml                            # runtime-endpoint 配置（unix:///run/containerd/containerd.sock）
systemctl status containerd; sudo grep -n SystemdCgroup /etc/containerd/config.toml

# —— 识别 CNI ——
ls /etc/cni/net.d/ /opt/cni/bin/
cat /etc/cni/net.d/*.conflist | head -40
kubectl get pods -n kube-system -o wide | grep -Ei 'calico|cilium|flannel'
kubectl get ds -A                               # CNI 一般以 DaemonSet 运行

# —— 识别 CSI ——
kubectl get csidrivers
kubectl get csinodes
kubectl get storageclass                        # PROVISIONER 列就是 CSI 驱动名

# —— CRD ——
kubectl get crd
kubectl get crd | grep -i gateway
kubectl api-resources --api-group=gateway.networking.k8s.io
kubectl explain <kind>.spec                     # CRD 的 schema 同样可以 explain
kubectl get <资源复数名> -A

# —— 安装 Operator（示例：用 Helm，chart 和参数以题目为准）——
helm repo add <repo> <url> && helm repo update
helm install <name> <repo>/<chart> -n <ns> --create-namespace --set crds.enabled=true
kubectl get pods -n <ns>; kubectl get crd | grep <关键字>
kubectl apply -f my-custom-resource.yaml        # 创建 CR，观察 Operator 是否按预期创建下层对象
```

### 最小 CRD 示例（理解结构用）

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.lab.example.com        # 必须是 <plural>.<group>
spec:
  group: lab.example.com
  scope: Namespaced
  names: {plural: backups, singular: backup, kind: Backup, shortNames: [bk]}
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              schedule: {type: string}
              retention: {type: integer}
```

## 4. 考试坑点

- `crictl` 报连不上运行时 → 检查 `/etc/crictl.yaml` 的 `runtime-endpoint`，或命令里加 `--runtime-endpoint unix:///run/containerd/containerd.sock`。
- 节点 `NotReady` + `network plugin not ready` → CNI 配置缺失/错误或 CNI DaemonSet 没起来；看 `/etc/cni/net.d/` 和 kube-system 里的 CNI Pod 日志。
- CRD 名字必须是 `<plural>.<group>`；先装 CRD 再建 CR，否则报 `no matches for kind`。
- 很多 chart 需要显式开启 CRD 安装（参数名各不相同，用 `helm show values` 查 `crd` 关键字）。
- 「哪个是 CSI 驱动」看 StorageClass 的 `provisioner`；`kubernetes.io/no-provisioner` 表示不能动态供给（见 [K14](14-storage.md)）。

## 5. 动手练习

- 在 kubeadm 集群里分别确认：运行时及版本、CNI 名称及配置文件、Pod CIDR（`kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'`）。
- 停掉某个 worker 上的 containerd，观察节点状态和 kubelet 日志，再恢复。
- 应用上面的 `Backup` CRD，创建一个 `bk`，用 `kubectl get bk`、`kubectl explain backup.spec` 验证。
- 用 Helm 安装一个带 CRD 的 Operator（如 cert-manager），创建它的自定义资源并观察 Operator 行为。
- [labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md) 中扩展接口/CRD 题。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| CRI | [concepts/containers/cri.md](../../references/cka/kubernetes-docs/concepts/containers/cri.md) | kubernetes.io/docs/concepts/containers/cri/ |
| 容器运行时安装与配置 | [setup/production-environment/container-runtimes.md](../../references/cka/kubernetes-docs/setup/production-environment/container-runtimes.md) | kubernetes.io/docs/setup/production-environment/container-runtimes/ |
| crictl 调试节点 | [tasks/debug/debug-cluster/crictl.md](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/crictl.md) | kubernetes.io/docs/tasks/debug/debug-cluster/crictl/ |
| **CNI 网络插件** | [concepts/extend-kubernetes/compute-storage-net/network-plugins.md](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/compute-storage-net/network-plugins.md) | kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/ |
| 集群网络模型 | [concepts/cluster-administration/networking.md](../../references/cka/kubernetes-docs/concepts/cluster-administration/networking.md) | kubernetes.io/docs/concepts/cluster-administration/networking/ |
| 插件（CNI 列表等） | [concepts/cluster-administration/addons.md](../../references/cka/kubernetes-docs/concepts/cluster-administration/addons.md) | kubernetes.io/docs/concepts/cluster-administration/addons/ |
| CSI 卷 | [concepts/storage/volumes.md](../../references/cka/kubernetes-docs/concepts/storage/volumes.md)（csi 一节） | kubernetes.io/docs/concepts/storage/volumes/#csi |
| 设备插件 | [concepts/extend-kubernetes/compute-storage-net/device-plugins.md](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/compute-storage-net/device-plugins.md) | kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/ |
| 扩展 K8s 总览 | [concepts/extend-kubernetes/_index.md](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/_index.md) | kubernetes.io/docs/concepts/extend-kubernetes/ |
| **自定义资源** | [concepts/extend-kubernetes/api-extension/custom-resources.md](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/api-extension/custom-resources.md) | kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/ |
| **创建 CRD（完整示例）** | [tasks/extend-kubernetes/custom-resources/custom-resource-definitions.md](../../references/cka/kubernetes-docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions.md) | kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/ |
| **Operator 模式** | [concepts/extend-kubernetes/operator.md](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/operator.md) | kubernetes.io/docs/concepts/extend-kubernetes/operator/ |

## 7. 自测清单

- [ ] 能说出 CRI、CNI、CSI 各自由谁调用、常见实现、在节点上的配置位置
- [ ] 能用 `crictl` 在 apiserver 不可用时查看容器和日志
- [ ] 能判断集群用的是哪个 CNI，并说明它是否支持 NetworkPolicy
- [ ] 能写出一个最小 CRD 并创建对应的 CR
- [ ] 能解释 CRD 与 Operator 的关系，以及「只有 CRD 没有控制器」会怎样
