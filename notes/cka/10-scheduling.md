# CKA-10 调度：资源、亲和性、污点

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Workloads and Scheduling (15%)」——Configure Pod admission and scheduling (limits, node affinity, etc.) ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[CKA-09 工作负载](09-workloads.md) · [CKA-01 集群架构与组件](01-architecture.md)
> **后续**：[CKA-15 排错](15-troubleshooting.md) · [CKA-05 高可用控制平面](05-ha-control-plane.md)
> **关联**（跨轨道）：[RHCSA-03 运行中的系统](../rhcsa/03-operate-running-systems.md)（nice/tuned ↔ requests/limits） · [F5 Docker → Podman → K8s](../00-foundations/05-containers-docker-to-k8s.md)（cgroups）

## 1. 这个知识点在网络中的位置

调度回答两个问题：**Pod 能不能被放进集群**（准入：ResourceQuota、LimitRange）和**放到哪个节点**（kube-scheduler：资源、nodeSelector、亲和性、污点）。
在排错（K15）里，`Pending` 的 Pod 十有八九是调度问题，所以这一篇是排错的前置。
Docker 里你用过 `--cpus` / `--memory`（`deploy.resources.limits`），它们底层都是 cgroups；K8s 的 `limits` 是同一个东西，但多了一个 `requests` 用来**调度**。

## 2. 核心概念

| 概念 | 作用 | 记忆点 |
|---|---|---|
| `resources.requests` | 调度依据：节点「可分配 − 已请求」≥ requests 才能放 | 没有 requests 的 Pod 在调度器眼里几乎不占资源 |
| `resources.limits` | 运行时上限：CPU 超限被**限流**，内存超限被 **OOMKilled** | 只写 limits 时 requests 默认等于 limits |
| QoS 等级 | Guaranteed（requests=limits 且都设了）> Burstable > BestEffort（都没设） | 节点内存压力时 BestEffort 最先被驱逐 |
| LimitRange | 命名空间内**单个容器/Pod** 的默认值、最小/最大值 | 新建 Pod 时由准入控制器注入默认值，对已存在的 Pod 不生效 |
| ResourceQuota | 命名空间**总量**上限（cpu/memory/pods/services/pvc 数…） | 设了 cpu/memory 配额后，Pod **必须**写 requests/limits（否则被拒），常和 LimitRange 配合 |
| `nodeName` | 直接指定节点，**绕过调度器** | 静态 Pod 和排错时会遇到 |
| `nodeSelector` | 节点标签精确匹配 | 最简单，够用就用它 |
| nodeAffinity | `requiredDuringSchedulingIgnoredDuringExecution`（硬）/ `preferred...`（软，带 weight） | 支持 `In/NotIn/Exists/DoesNotExist/Gt/Lt` |
| podAffinity / podAntiAffinity | 根据**其他 Pod** 的位置决定，`topologyKey` 定义「同一位置」 | 反亲和 + `kubernetes.io/hostname` = 每节点最多一个 |
| taints / tolerations | 节点「排斥」Pod；Pod 声明「容忍」 | 容忍 ≠ 吸引，要固定到某节点还需 nodeSelector/亲和性 |
| `topologySpreadConstraints` | 让 Pod 在 zone/节点间均匀分布 | `maxSkew`、`whenUnsatisfiable` |
| PriorityClass | 高优先级 Pod 可抢占低优先级 Pod | `kubectl create priorityclass` |

污点三种效果：`NoSchedule`（不调度新 Pod）、`PreferNoSchedule`（尽量不）、`NoExecute`（还会**驱逐**已运行且不容忍的 Pod）。
控制平面节点默认带 `node-role.kubernetes.io/control-plane:NoSchedule`。

> 版本提示：v1.35 起「原地调整 Pod 资源」（In-place Pod Resize，`kubectl patch ... --subresource resize`）为 GA，考纲没有点名，了解即可。

## 3. 必会操作

```bash
# 节点标签
kubectl label node node01 disktype=ssd
kubectl label node node01 disktype-            # 删除标签
kubectl get nodes --show-labels
kubectl get nodes -L disktype                  # 以列显示某标签

# 污点
kubectl taint node node01 dedicated=gpu:NoSchedule
kubectl taint node node01 dedicated=gpu:NoSchedule-     # 删除（末尾减号）
kubectl describe node node01 | grep -i -A3 taints

# 资源与配额
kubectl set resources deployment web --requests=cpu=100m,memory=128Mi --limits=memory=256Mi
kubectl create quota team-a --hard=pods=10,requests.cpu=2,requests.memory=4Gi,limits.memory=8Gi -n team-a
kubectl describe quota -n team-a
kubectl describe limitrange -n team-a
kubectl describe node node01 | grep -A8 "Allocated resources"   # 节点已分配多少

# 看 Pod 为什么 Pending
kubectl describe pod <pod> | sed -n '/Events/,$p'
kubectl get events --sort-by=.lastTimestamp -A | tail -20
```

nodeAffinity + toleration 组合（「只能」跑在带 `dedicated=gpu` 污点且标签 `gpu=true` 的节点上）：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: trainer
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - {key: gpu, operator: In, values: ["true"]}
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 50
        preference:
          matchExpressions:
          - {key: zone, operator: In, values: ["zone-a"]}
  tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: NoSchedule
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 250m, memory: 64Mi}
      limits:   {cpu: 500m, memory: 128Mi}
```

LimitRange（给命名空间里没写资源的容器注入默认值）：

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: team-a
spec:
  limits:
  - type: Container
    default:        {cpu: 500m, memory: 256Mi}   # 默认 limits
    defaultRequest: {cpu: 100m, memory: 128Mi}   # 默认 requests
    max:            {cpu: "1",  memory: 512Mi}
```

podAntiAffinity（同一 Deployment 的副本分散到不同节点）片段：

```yaml
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels: {app: web}
            topologyKey: kubernetes.io/hostname
```

## 4. 考试坑点

- requiredDuringScheduling**IgnoredDuringExecution**：改节点标签不会把已运行的 Pod 赶走。
- `nodeSelectorTerms` 之间是 **OR**，同一个 term 里的多个 `matchExpressions` 是 **AND**。
- toleration 写 `operator: Exists` 时不要写 `value`；只写 `key` + `Exists` 可以容忍该 key 的所有值。
- 资源单位：`100m` = 0.1 核；内存 `Mi`（2^20）和 `M`（10^6）不同，题目写什么就用什么。
- Deployment 的亲和性/容忍写在 `spec.template.spec` 下，别写到 Deployment 的 `spec` 顶层。
- 设置 ResourceQuota 后老 Deployment 的新 Pod 起不来：看 ReplicaSet 的 events（`kubectl describe rs`），不是 Pod 的。
- 不能改运行中 Pod 的大部分 spec（如 nodeSelector、tolerations 只能增加）——`kubectl get pod x -o yaml > x.yaml`，改完 `kubectl replace --force -f x.yaml`。

## 5. 动手练习

- [CKA 练习题集 · K10 调度](../../labs/cka/practice-set-1.md#k10-调度)（nodeSelector、亲和性、污点、LimitRange、ResourceQuota、PriorityClass）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 8 题

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [将 Pod 指派到节点（nodeSelector / 亲和性）](../../references/cka/kubernetes-docs/concepts/scheduling-eviction/assign-pod-node.md) · [用节点亲和性分配 Pod（任务）](../../references/cka/kubernetes-docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity.md)
  - [污点和容忍度](../../references/cka/kubernetes-docs/concepts/scheduling-eviction/taint-and-toleration.md) · [Pod 优先级与抢占](../../references/cka/kubernetes-docs/concepts/scheduling-eviction/pod-priority-preemption.md) · [节点压力驱逐](../../references/cka/kubernetes-docs/concepts/scheduling-eviction/node-pressure-eviction.md)
  - [容器资源管理](../../references/cka/kubernetes-docs/concepts/configuration/manage-resources-containers.md) · [Pod QoS](../../references/cka/kubernetes-docs/concepts/workloads/pods/pod-qos.md) · [分配 CPU](../../references/cka/kubernetes-docs/tasks/configure-pod-container/assign-cpu-resource.md) · [分配内存](../../references/cka/kubernetes-docs/tasks/configure-pod-container/assign-memory-resource.md)
  - [LimitRange](../../references/cka/kubernetes-docs/concepts/policy/limit-range.md) · [ResourceQuota](../../references/cka/kubernetes-docs/concepts/policy/resource-quotas.md) · [命名空间资源管理任务合集](../../references/cka/kubernetes-docs/tasks/administer-cluster/manage-resources/)
- 考场（kubernetes.io）：
  - `/docs/concepts/scheduling-eviction/assign-pod-node/`（nodeAffinity YAML 直接复制）
  - `/docs/concepts/scheduling-eviction/taint-and-toleration/`
  - `/docs/concepts/policy/limit-range/`、`/docs/concepts/policy/resource-quotas/`
  - 命令行：`kubectl explain pod.spec.affinity.nodeAffinity --recursive`、`kubectl explain pod.spec.tolerations`

## 7. 自测清单

- [ ] 能不查文档写出 nodeAffinity（硬 + 软）和 toleration 的 YAML
- [ ] 能解释「有容忍但仍然调度到别的节点」的原因，并给出修正方法
- [ ] 能说清三种 QoS 等级的判定规则以及驱逐顺序
- [ ] 能为命名空间配置 LimitRange + ResourceQuota，并验证超额 Pod 被拒绝
- [ ] 能从 `kubectl describe pod` 的 Events 中读出 `0/3 nodes are available: ...` 的每一种原因
- [ ] 能让 Deployment 的 3 个副本强制分布到 3 个不同节点
