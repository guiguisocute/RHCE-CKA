# CKA-14 存储：PV / PVC / StorageClass

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Storage (10%)」——StorageClass 与动态供给、卷类型/访问模式/回收策略、PV 与 PVC ｜ **建议用时**：5 h ｜ **难度**：★★☆
>
> **前置**：[CKA-09 工作负载](09-workloads.md) · [RHCSA-04 本地存储与 LVM](../rhcsa/04-local-storage-lvm.md)
> **后续**：[CKA-15 排错](15-troubleshooting.md)
> **关联**（跨轨道）：[RHCSA-05 文件系统 / NFS / autofs](../rhcsa/05-file-systems-nfs-autofs.md)（NFS 作 PV 后端） · [RHCE-11 用 Ansible 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md) · [CKA-08 扩展接口（CSI）](08-extension-interfaces-crd.md)

## 1. 这个知识点在网络中的位置

容器文件系统是临时的，Pod 重建数据就没了。K8s 把「存储从哪来」和「应用要多少」解耦：

- 管理员/存储系统提供 **PV**（PersistentVolume，集群级资源），或由 **StorageClass** 按需自动创建；
- 应用只写 **PVC**（PersistentVolumeClaim，命名空间级）：「我要 1Gi、RWO、某个 class」。

和 RHCSA 的 LVM 对比着记：LVM 的 PV/VG/LV 是**块设备层**的概念，K8s 的 PV/PVC 是**集群 API 层**的概念——名字撞了但不是一回事；不过 K8s PV 背后常常就是一块 LVM 卷、一个 NFS 导出目录（RHCSA-05）或云盘（通过 CSI，见 K8）。

| docker / compose | Kubernetes |
|---|---|
| 命名卷 `volumes: [data:/var/lib/mysql]` | PVC（+ StorageClass 动态创建 PV） |
| 绑定挂载 `./conf:/etc/app` | `hostPath`（仅限单节点/实验；多节点时 Pod 漂移后数据不跟着走） |
| `tmpfs:` | `emptyDir: {medium: Memory}` |
| 同一卷挂给多个容器 | 同一 Pod 内多容器共享 `emptyDir`；跨 Pod 共享需要 RWX 存储（如 NFS） |

## 2. 核心概念

- **卷类型（Pod 内 `volumes:`）**：`emptyDir`（随 Pod 生灭）、`hostPath`、`configMap`/`secret`/`projected`、`persistentVolumeClaim`、`nfs`、`csi`。大部分云厂商的 in-tree 插件已迁移到 CSI。
- **访问模式 accessModes**（能力由后端决定，不是 K8s 强制的读写锁）：
  | 模式 | 简写 | 含义 |
  |---|---|---|
  | ReadWriteOnce | RWO | 单**节点**读写（同节点多个 Pod 可同时用） |
  | ReadOnlyMany | ROX | 多节点只读 |
  | ReadWriteMany | RWX | 多节点读写（NFS、CephFS 等） |
  | ReadWriteOncePod | RWOP | 单 **Pod** 读写（v1.29 GA，仅 CSI 卷） |
- **回收策略 persistentVolumeReclaimPolicy**：`Retain`（PVC 删除后 PV 变 `Released`，数据保留，需手工处理）、`Delete`（连同后端存储一起删，动态供给的默认值）；`Recycle` 已废弃。
- **PV 生命周期**：`Available` → `Bound` → （PVC 删除）`Released` → 手工清理或删除；`Failed` 表示自动回收失败。
- **绑定规则**：PVC 与 PV 的 `storageClassName` 相同（都为空串也算）、`accessModes` 被 PV 覆盖、PV 容量 ≥ 请求；可用 `selector` 按标签选 PV，或用 `volumeName` 指定。**一对一绑定**，10Gi 的 PV 绑给 1Gi 的 PVC 后剩下的空间也不能给别人。
- **StorageClass**：`provisioner`（如 `rancher.io/local-path`、`nfs.csi.k8s.io`、`ebs.csi.aws.com`；`kubernetes.io/no-provisioner` 表示不自动创建，用于 local PV）、`parameters`、`reclaimPolicy`、`allowVolumeExpansion`、`volumeBindingMode`：
  - `Immediate`：PVC 一创建就绑定/供给；
  - `WaitForFirstConsumer`：等到有 Pod 使用并调度后再按该节点供给（local 存储必须用它，否则 PV 可能建在 Pod 去不了的节点）。
- **默认 StorageClass**：注解 `storageclass.kubernetes.io/is-default-class: "true"`；PVC 不写 `storageClassName` 时使用默认 class。想要「不用任何 class、绑静态 PV」时写 `storageClassName: ""`。
- **扩容**：class 允许 `allowVolumeExpansion: true` 时，直接改 PVC 的 `spec.resources.requests.storage`（只能增大）。

## 3. 必会操作

```bash
kubectl get sc                                     # 看 PROVISIONER / RECLAIMPOLICY / VOLUMEBINDINGMODE / 是否 (default)
kubectl get pv                                     # 集群级，无需 -n
kubectl get pvc -A
kubectl describe pvc data -n app                   # Pending 时看 Events
kubectl patch pv pv-log -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch pv pv-log --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'   # Released → Available（数据仍在）
kubectl get pv -o custom-columns=NAME:.metadata.name,CAP:.spec.capacity.storage,MODES:.spec.accessModes,POLICY:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.name
kubectl get pv --sort-by=.spec.capacity.storage    # 题目常要求按容量排序输出
```

静态 PV（hostPath，实验用）+ PVC + Pod 三件套：

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-log
  labels: {type: log}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath: {path: /mnt/data/log}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: log-claim
  namespace: app
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources:
    requests: {storage: 500Mi}
  selector:
    matchLabels: {type: log}
---
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: app
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /var/log/app/out.log; sleep 5; done"]
    volumeMounts:
    - {name: log, mountPath: /var/log/app}
  volumes:
  - name: log
    persistentVolumeClaim: {claimName: log-claim}
```

StorageClass（动态供给）+ 只写 PVC：

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: rancher.io/local-path        # 以集群里实际安装的 provisioner 为准
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-data
spec:
  storageClassName: fast
  accessModes: [ReadWriteOnce]
  resources:
    requests: {storage: 2Gi}
```

NFS 作为 PV 后端（服务器端配置见 RHCSA-05）：

```yaml
spec:
  capacity: {storage: 5Gi}
  accessModes: [ReadWriteMany]
  nfs: {server: 192.168.122.10, path: /exports/k8s}
```

## 4. 考试坑点

- PVC 一直 `Pending`：`storageClassName` 不匹配（最常见）、没有满足容量/访问模式的 PV、class 是 `WaitForFirstConsumer` 而还没有 Pod 使用它（这时 Pending 是**正常**的）。
- PV 是集群级的，`kubectl get pv -n xxx` 加了 `-n` 也没影响；PVC 一定要放到题目要求的命名空间。
- 题目要求「不使用 StorageClass」：PV 和 PVC 都写 `storageClassName: ""`（或都写同一个自定义名字），否则 PVC 会被默认 class 抢去动态供给。
- `Retain` 的 PV 删除 PVC 后是 `Released`，**不会**自动被新 PVC 绑定——要删掉 `claimRef`。
- 删除正在被 Pod 使用的 PVC 会卡在 `Terminating`（`kubernetes.io/pvc-protection` finalizer），先删 Pod。
- Pod 的 `volumes[].name` 与 `volumeMounts[].name` 必须一致；`mountPath` 是容器内路径。
- hostPath 的数据在**节点**上：验证时到 Pod 所在节点（`kubectl get pod -o wide`）上看目录。
- 只有 class 允许扩容时才能改大 PVC；不能缩小。

## 5. 动手练习

- [CKA 练习题集 · K14 存储](../../labs/cka/practice-set-1.md#k14-存储)（静态 PV/PVC、StorageClass 动态供给、默认 class、回收策略、扩容、Released PV 复用）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 14 题

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [持久卷 PV/PVC](../../references/cka/kubernetes-docs/concepts/storage/persistent-volumes.md)（访问模式、回收策略、绑定规则都在这一页）
  - [StorageClass](../../references/cka/kubernetes-docs/concepts/storage/storage-classes.md) · [动态卷供给](../../references/cka/kubernetes-docs/concepts/storage/dynamic-provisioning.md) · [卷类型](../../references/cka/kubernetes-docs/concepts/storage/volumes.md) · [卷快照](../../references/cka/kubernetes-docs/concepts/storage/volume-snapshots.md)
  - [配置 Pod 使用 PV（教程）](../../references/cka/kubernetes-docs/tutorials/configuration/configure-persistent-volume-storage.md) · [更改 PV 回收策略](../../references/cka/kubernetes-docs/tasks/administer-cluster/change-pv-reclaim-policy.md) · [更改默认 StorageClass](../../references/cka/kubernetes-docs/tasks/administer-cluster/change-default-storage-class.md)
  - 示例 YAML：[`pv-volume.yaml`](../../references/cka/kubernetes-docs/examples/pods/storage/pv-volume.yaml) · [`pv-claim.yaml`](../../references/cka/kubernetes-docs/examples/pods/storage/pv-claim.yaml) · [`pv-pod.yaml`](../../references/cka/kubernetes-docs/examples/pods/storage/pv-pod.yaml)
- 考场（kubernetes.io）：
  - 搜索 "Configure a Pod to Use a PersistentVolume for Storage"（PV + PVC + Pod 三件套模板；本仓库抓取的版本中该页位于 `/docs/tutorials/configuration/` 下，早期版本在 `/docs/tasks/configure-pod-container/`，考场用搜索框最稳）
  - `/docs/concepts/storage/persistent-volumes/`、`/docs/concepts/storage/storage-classes/`
  - 命令行：`kubectl explain pv.spec`、`kubectl explain pvc.spec`、`kubectl explain storageclass`

## 7. 自测清单

- [ ] 能在 5 分钟内写出 PV + PVC + Pod 三件套并验证数据写到了节点目录
- [ ] 能说出 4 种访问模式、2 种有效回收策略、2 种绑定模式的区别
- [ ] 能把 PVC Pending 的原因分成「class 不匹配 / 没有合适 PV / WaitForFirstConsumer」三类并逐一验证
- [ ] 能把一个 StorageClass 设为默认，并让另一个取消默认
- [ ] 能让一个 Released 的 Retain PV 重新被绑定
- [ ] 能解释 LVM 的 PV 和 K8s 的 PV 的区别与联系
