# CKA 模拟考（原创）

> **声明**：本套题根据 [CKA 官方考纲 v1.37](../../references/cka/CKA_Curriculum_v1.37.pdf) 的领域和权重**原创**，不是真题，也不代表真实考试的题目或难度。真实考试的形式、时长、及格线、允许使用的文档等以 [Linux Foundation 官方页面](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) 和考生手册为准。
>
> 先做完 [练习题集](practice-set-1.md) 再来；考前 1~2 周做一遍，做完对照文末评分表打分。官方购买考试后附赠的 killer.sh 模拟环境建议留到最后一周。

## 考试设定

| 项目 | 设定 |
|---|---|
| 时长 | **120 分钟**，严格计时，中途不看笔记 |
| 题量 / 总分 | 17 题 / 100 分，按考纲权重分配；**66 分及格**（参照官方公布的及格线，以官网为准） |
| 允许的资料 | 只开一个浏览器标签访问 kubernetes.io/docs（练习时也可用本仓库 [`references/cka/kubernetes-docs/`](../../references/cka/kubernetes-docs/) 代替，但只许 `grep`/阅读，不许看本仓库笔记） |
| 集群 | 两个 context：`k8s-a`（主集群：cp1 + worker1 + worker2）、`k8s-b`（用于升级与排错，可以是第二套小集群） |
| 答案文件 | 写入跳板机的 `/opt/answers/`，题目会指明文件名 |

**每道题开头的 `kubectl config use-context ...` 必须先执行**——这是真实考试中最常见的丢分原因。

只有一套集群也能做：用 `kubectl config rename-context` / `kubectl config set-context` 给同一集群建两个 context 名，把 `k8s-b` 的题也在同一集群上做（升级题和破坏性排错题之前打快照）。

<details><summary>出题人准备（请让朋友执行，或自己在<strong>阅读题目之前</strong>执行；内容即剧透）</summary>

```bash
# 在 k8s-a 上
kubectl config use-context k8s-a
kubectl create ns apps; kubectl create ns secure; kubectl create ns client; kubectl create ns storage
kubectl create deploy payment -n apps --image=nginx:1.27 --replicas=3
kubectl create deploy reports -n apps --image=nginx --replicas=2
kubectl create deploy legacy -n apps --image=nginx --replicas=2
kubectl create service clusterip legacy -n apps --tcp=80:80
kubectl patch svc legacy -n apps -p '{"spec":{"selector":{"app":"legasy"}}}'
kubectl create deploy api -n secure --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
kubectl expose deploy api -n secure --port=80 --target-port=8080
kubectl create deploy worker -n apps --image=busybox:1.36 -- sh -c 'echo "ERROR: db timeout"; echo "INFO: retry"; sleep 5; exit 3'
# 在 k8s-b 上（破坏两个组件，事先打快照）
kubectl config use-context k8s-b
ssh <k8s-b 的 worker 节点> 'sudo systemctl stop containerd && sudo systemctl disable containerd'
ssh <k8s-b 的控制平面> 'sudo cp /etc/kubernetes/manifests/kube-controller-manager.yaml /root/kcm.bak && sudo sed -i "s#/etc/kubernetes/controller-manager.conf#/etc/kubernetes/controller-manager.conf.bad#g" /etc/kubernetes/manifests/kube-controller-manager.yaml'
```
</details>

---

## 题目

### 第 1 题 · RBAC（5 分）｜ context：`k8s-a`

在命名空间 `apps` 中创建 ServiceAccount `ci-bot`。创建 ClusterRole `deploy-manager`，只允许对 `deployments`、`statefulsets`、`daemonsets` 执行 `create`、`update`、`patch`、`get`、`list`。让 `ci-bot` **只在 `apps` 命名空间**拥有该权限。

### 第 2 题 · etcd 备份与恢复（7 分）｜ context：`k8s-a`，在 `cp1` 上操作

1. 将 etcd 快照保存到 `/opt/backup/etcd-mock.db`（证书在 `/etc/kubernetes/pki/etcd/`）。
2. 删除命名空间 `storage`，然后用刚才的快照恢复 etcd（数据目录使用 `/var/lib/etcd-mock`），使 `storage` 命名空间重新出现。

### 第 3 题 · 集群升级（7 分）｜ context：`k8s-b`

将 `k8s-b` 的**控制平面节点**上的控制平面组件、kubelet 和 kubectl 升级到下一个小版本的最新补丁版本。升级前驱逐该节点，完成后恢复调度。**不要**升级工作节点。

### 第 4 题 · Helm 与 Kustomize（3 分）｜ context：`k8s-a`

1. 使用 Helm 在命名空间 `monitoring`（自动创建）安装 `podinfo/podinfo` chart，release 名 `status-page`，副本数 2，Service 类型 `NodePort`。
2. 目录 `/opt/kustomize/overlays/dev` 下已有 base 的引用（若不存在请自行创建一个包含 Deployment 的 base），为 overlay 添加：命名空间 `dev`、标签 `env=dev`、镜像 tag `1.28`，并应用到集群。

### 第 5 题 · 扩展接口与 CRD（3 分）｜ context：`k8s-a`

1. 把集群使用的 CNI 插件名写入 `/opt/answers/q5-cni.txt`，把节点容器运行时的 endpoint 写入 `/opt/answers/q5-cri.txt`。
2. 把集群中所有 CRD 里属于 `gateway.networking.k8s.io` 组的名字写入 `/opt/answers/q5-crds.txt`。

### 第 6 题 · 滚动更新与回滚（5 分）｜ context：`k8s-a`

命名空间 `apps` 中的 Deployment `payment`：

1. 修改滚动更新策略，保证更新过程中**可用副本数永远不少于 3**，且最多只多出 1 个 Pod。
2. 将镜像更新为 `nginx:1.28`，变更原因记录为 `security patch`。
3. 把 `kubectl rollout history` 的输出写入 `/opt/answers/q6-history.txt`。

### 第 7 题 · 配置与自动扩缩（5 分）｜ context：`k8s-a`

1. 在 `apps` 中创建 ConfigMap `reports-cfg`（`REPORT_FORMAT=pdf`、`RETENTION_DAYS=30`），以环境变量方式全部注入 Deployment `reports`。
2. 为 `reports` 配置 HPA：CPU 平均利用率 60%，副本数 2~8，**缩容稳定窗口 120 秒**。（需要时为容器补充资源请求。）

### 第 8 题 · 调度（5 分）｜ context：`k8s-a`

1. 给 `worker2` 添加污点 `team=analytics:NoSchedule` 和标签 `team=analytics`。
2. 在 `apps` 中创建 Deployment `analytics`（`busybox:1.36`，命令 `sleep 3600`，2 副本），要求**所有副本都只运行在 `worker2` 上**；每个容器请求 `cpu: 50m`、`memory: 32Mi`，内存上限 `64Mi`。

### 第 9 题 · Service 排错与暴露（4 分）｜ context：`k8s-a`

1. `apps` 中的 Service `legacy` 没有任何后端，修复它（不要删除重建 Deployment）。
2. 把 Deployment `payment` 以 NodePort `30443` 暴露为 Service `payment-np`（端口 80）。

### 第 10 题 · CoreDNS（4 分）｜ context：`k8s-a`

1. 把 `secure` 命名空间中 Service `api` 的完整 DNS 名写入 `/opt/answers/q10-fqdn.txt`。
2. 在 `client` 命名空间创建 Pod `dns-check`（`busybox:1.36`，`sleep 3600`），并把在其中执行 `nslookup api.secure` 的输出写入 `/opt/answers/q10-nslookup.txt`。

### 第 11 题 · NetworkPolicy（5 分）｜ context：`k8s-a`

在命名空间 `secure` 中创建 NetworkPolicy `api-ingress`：

- 只允许来自 `client` 命名空间、且标签为 `access=api` 的 Pod 访问 `app=api` 的 Pod；
- 只开放 TCP 8080；
- `secure` 命名空间中的其他 Pod 不受此策略影响。

验证：给第 10 题的 `dns-check` 打上 `access=api` 前后各访问一次 `http://api.secure/hostname`，结果应为「先失败、后成功」。

### 第 12 题 · Ingress（3 分）｜ context：`k8s-a`

在 `apps` 中创建 Ingress `payment-ing`：使用集群中的 IngressClass，主机名 `pay.lab.local`，路径 `/pay`（Prefix）转发到 Service `payment-np` 的 80 端口。

### 第 13 题 · Gateway API（4 分）｜ context：`k8s-a`

1. 在命名空间 `apps` 中创建 Gateway `apps-gw`：使用集群中已有的 GatewayClass，HTTP 监听器端口 80，只接受同命名空间的路由。
2. 创建 HTTPRoute `payment-route`：主机名 `pay.lab.local`，路径前缀 `/` 的流量 **90%** 发往 `payment-np:80`、**10%** 发往 `legacy:80`。
3. 确认 Route 的 `Accepted` 条件为 `True`。

### 第 14 题 · 存储（10 分）｜ context：`k8s-a`

1. 创建 StorageClass `retain-local`：provisioner 使用集群中 local-path 所用的 provisioner，回收策略 `Retain`，绑定模式 `WaitForFirstConsumer`。
2. 在 `storage` 命名空间创建 PVC `archive`（`retain-local`，RWO，200Mi）和 Pod `archiver`（`busybox:1.36`），把 PVC 挂到 `/archive`，并向 `/archive/hello.txt` 写入 `hello cka`。
3. 删除 Pod 和 PVC 后，确认对应 PV 仍然存在且状态为 `Released`，把该 PV 的名字写入 `/opt/answers/q14-pv.txt`。

### 第 15 题 · 节点排错（10 分）｜ context：`k8s-b`

`k8s-b` 中有一个工作节点处于 `NotReady`。找出原因并修复，要求修复在节点**重启后依然有效**。把根因（一句话）写入 `/opt/answers/q15-cause.txt`。

### 第 16 题 · 控制平面排错（10 分）｜ context：`k8s-b`

在 `k8s-b` 中执行 `kubectl create deploy probe --image=nginx --replicas=2` 后，Deployment 存在但**一直没有创建出任何 Pod**（`READY 0/2`，`kubectl get rs` 为空）。找出出问题的组件并修复，使 2 个 Pod 运行起来。

### 第 17 题 · 应用排错与监控（10 分）｜ context：`k8s-a`

1. `apps` 中的 Deployment `worker` 反复崩溃。把它**上一次崩溃前**输出中含 `ERROR` 的行写入 `/opt/answers/q17-errors.txt`，并把容器退出码写入 `/opt/answers/q17-exitcode.txt`。
2. 把集群中（所有命名空间）**内存占用最高**的 Pod，以 `命名空间/Pod名` 的格式写入 `/opt/answers/q17-top.txt`。

---

## 参考思路（做完再看）

<details><summary>第 1~5 题</summary>

- **Q1**：`kubectl create clusterrole deploy-manager --verb=create,update,patch,get,list --resource=deployments,statefulsets,daemonsets`；**RoleBinding**（不是 ClusterRoleBinding）`kubectl create rolebinding ci-bot -n apps --clusterrole=deploy-manager --serviceaccount=apps:ci-bot`。验证 `kubectl auth can-i create deployments -n apps --as=system:serviceaccount:apps:ci-bot` 为 yes，`-n default` 为 no。
- **Q2**：见 [练习 4.3/4.4](practice-set-1.md#k4-集群生命周期升级与-etcd)。恢复后改 `etcd.yaml` 的 `etcd-data` hostPath 为 `/var/lib/etcd-mock`，等待 etcd/apiserver 重建。
- **Q3**：见 [CKA-04](../../notes/cka/04-cluster-lifecycle.md)。只在控制平面执行 `kubeadm upgrade apply`；`kubectl get nodes` 中只有控制平面显示新版本。
- **Q4**：`helm install status-page podinfo/podinfo -n monitoring --create-namespace --set replicaCount=2 --set service.type=NodePort`（values 键名以 `helm show values` 为准）；Kustomize 用 `namespace:`、`labels:`（或 `commonLabels`）、`images:`，`kubectl apply -k`。
- **Q5**：`ls /etc/cni/net.d/`；`grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml`；`kubectl get crd -o name | grep gateway.networking.k8s.io`。
</details>

<details><summary>第 6~10 题</summary>

- **Q6**：3 副本时「可用不少于 3」⇒ `maxUnavailable: 0`、`maxSurge: 1`；`set image` + `annotate kubernetes.io/change-cause="security patch"`；`kubectl rollout history deploy/payment -n apps > /opt/answers/q6-history.txt`。
- **Q7**：`kubectl set env deploy/reports -n apps --from=configmap/reports-cfg`；`kubectl set resources ... --requests=cpu=100m`；HPA 用 `autoscaling/v2` YAML，`behavior.scaleDown.stabilizationWindowSeconds: 120`。
- **Q8**：容忍 + `nodeSelector: {team: analytics}`（或 nodeAffinity）缺一不可：只有容忍不能保证落在 worker2，只有 nodeSelector 会因污点 Pending。
- **Q9**：`kubectl get endpointslices -n apps -l kubernetes.io/service-name=legacy` 为空 → `kubectl edit svc legacy -n apps` 把 selector 改为 `app: legacy`；NodePort 用 YAML 写 `nodePort: 30443`。
- **Q10**：`api.secure.svc.cluster.local`（集群域以 kubelet `clusterDomain` 为准）；`kubectl exec -n client dns-check -- nslookup api.secure > /opt/answers/q10-nslookup.txt`。
</details>

<details><summary>第 11~14 题</summary>

- **Q11**：`podSelector: {matchLabels: {app: api}}`（不要用 `{}`，否则影响整个命名空间）；`from` 中 namespaceSelector（`kubernetes.io/metadata.name: client`）与 podSelector（`access: api`）在**同一元素**；`ports: [{protocol: TCP, port: 8080}]`。
- **Q12**：`kubectl create ingress payment-ing -n apps --class=<class> --rule="pay.lab.local/pay*=payment-np:80"`。
- **Q13**：Gateway `allowedRoutes.namespaces.from: Same`；HTTPRoute 两个 `backendRefs` 分别 `weight: 90` / `weight: 10`；`kubectl describe httproute payment-route -n apps`。
- **Q14**：`kubectl get sc local-path -o jsonpath='{.provisioner}'` 获取 provisioner；Pod 创建后 PVC 才会 Bound（WaitForFirstConsumer）；`kubectl exec archiver -n storage -- sh -c 'echo hello cka > /archive/hello.txt'`；删除后 `kubectl get pv` 状态 `Released`。
</details>

<details><summary>第 15~17 题</summary>

- **Q15**：`kubectl describe node` → ssh → `systemctl status kubelet`（kubelet 报连不上 containerd socket）→ `systemctl status containerd` 为 inactive/disabled → `sudo systemctl enable --now containerd` → 必要时重启 kubelet。根因：containerd 被停止并禁用。
- **Q16**：Deployment 不产生 ReplicaSet ⇒ kube-controller-manager。`kubectl -n kube-system get pods` 看到它 CrashLoop / 不存在 → 节点上 `crictl ps -a`、`crictl logs` → kubeconfig 路径错误 → 修正 `/etc/kubernetes/manifests/kube-controller-manager.yaml` 中的路径（注意 `--kubeconfig`、`--authentication-kubeconfig`、`--authorization-kubeconfig` 和 volume 都可能被改到）。
- **Q17**：`kubectl logs deploy/worker -n apps --previous | grep ERROR > /opt/answers/q17-errors.txt`；退出码：`kubectl get pod <pod> -n apps -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'`（本题为 3）；`kubectl top pods -A --sort-by=memory --no-headers | head -1 | awk '{print $1"/"$2}'`。
</details>

---

## 评分自查表

| 题 | 分值 | 得分检查点（每个检查点平分该题分值） | 得分 |
|---|---|---|---|
| 1 | 5 | SA 存在；ClusterRole 动词/资源正确；用 RoleBinding 绑在 `apps`；`can-i` 在 apps 为 yes、在 default 为 no | |
| 2 | 7 | 快照文件存在且 `snapshot status` 正常；`storage` 命名空间恢复；集群其他功能正常 | |
| 3 | 7 | 控制平面组件新版本；kubelet/kubectl 新版本；节点 Ready 且已 uncordon；工作节点未变 | |
| 4 | 3 | release 状态 deployed、2 副本、NodePort；overlay 资源在 `dev` 且带标签和新镜像 | |
| 5 | 3 | 三个答案文件内容正确 | |
| 6 | 5 | 策略正确；镜像 1.28；change-cause；history 文件 | |
| 7 | 5 | ConfigMap 两个键；Pod 中有环境变量；HPA 范围/目标/稳定窗口正确且 TARGETS 非 unknown | |
| 8 | 5 | 污点和标签；2 副本都在 worker2；资源设置正确 | |
| 9 | 4 | legacy 有 Endpoints 且可访问；payment-np 为 NodePort 30443 | |
| 10 | 4 | FQDN 正确；nslookup 输出文件存在且解析成功 | |
| 11 | 5 | 只选中 app=api；AND 关系正确；端口 8080；验证「先失败后成功」 | |
| 12 | 3 | class、host、path、pathType、后端正确 | |
| 13 | 4 | Gateway 正确且 Programmed；HTTPRoute 权重 90/10；Accepted=True | |
| 14 | 10 | SC 三个参数；PVC Bound；文件内容；PV Released 且名字写对 | |
| 15 | 10 | 节点 Ready；重启后仍 Ready（containerd enabled）；根因描述 | |
| 16 | 10 | 定位到 controller-manager；清单修复；probe 2/2 Running | |
| 17 | 10 | ERROR 行；退出码；内存最高 Pod 的格式与内容 | |
| **合计** | **100** | | |

**及格参考 66 分**。按领域统计失分，回到 [notes/cka/](../../notes/cka/README.md) 对应节点补课：

| 领域（权重） | 题号 | 满分 |
|---|---|---|
| Cluster Architecture, Installation & Configuration（25%） | 1–5 | 25 |
| Workloads & Scheduling（15%） | 6–8 | 15 |
| Services & Networking（20%） | 9–13 | 20 |
| Storage（10%） | 14 | 10 |
| Troubleshooting（30%） | 15–17 | 30 |

---

## 考前一周冲刺清单

**D-7 ~ D-5：查漏补缺**
- [ ] 把模拟考失分的领域对应笔记的「自测清单」全部重做一遍
- [ ] 默写（不查文档）：Deployment、Service(NodePort)、NetworkPolicy、PV+PVC+Pod、Ingress、Gateway+HTTPRoute、HPA v2
- [ ] etcd 备份/恢复、kubeadm 升级各从零完整做一遍，命令和证书路径能凭记忆写出

**D-4 ~ D-3：官方模拟环境**
- [ ] 激活第 1 次 killer.sh（购买考试后附赠，具体次数和时长以官方为准），完整做完，复盘每一道错题
- [ ] 练习在 kubernetes.io 用搜索框定位页面：deployment、network policy、persistent volume、ingress、gateway、kubeadm upgrade、etcd backup、static pod、debug service

**D-2：效率**
- [ ] `alias k=kubectl`、`export do="--dry-run=client -o yaml"`、`kubectl completion bash`（考场环境通常已预配置别名与补全，以考生手册为准）
- [ ] vim：`set ts=2 sw=2 et`、可视模式缩进 `>`/`<`、粘贴前 `:set paste`
- [ ] 第 2 次 killer.sh，目标在 2 小时内完成且准确率 > 80%

**D-1：考务**
- [ ] 按考生手册完成系统检查（摄像头、麦克风、网络、浏览器），清理桌面，准备证件
- [ ] 复习本仓库的 [排错笔记](../../notes/cka/15-troubleshooting.md) 的「哪个组件坏了 → 什么症状」表
- [ ] 早点睡

**考试当天的策略**
- 每题先 `use-context`，再读题；先做分值高、有把握的题，卡住超过 6 分钟就标记跳过。
- 修改系统文件前备份到 `/etc/kubernetes/manifests/` 之外；ssh 到节点做完记得 `exit`。
- 每题做完用验证命令确认结果（Running / Ready / Bound / can-i / curl），不要只看 `created`。
