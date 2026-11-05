# CKA-15 排错（Troubleshooting，30%）

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Troubleshooting (30%)」——集群与节点、集群组件、资源监控、容器输出流、服务与网络 ｜ **建议用时**：12 h（贯穿整个 CKA 阶段反复练） ｜ **难度**：★★★
>
> **前置**：[CKA-04 集群生命周期](04-cluster-lifecycle.md) · [CKA-11 Service 与 CoreDNS](11-services-dns.md) · [CKA-14 存储](14-storage.md) · [RHCSA-03 运行中的系统](../rhcsa/03-operate-running-systems.md) · [F2 systemd 与 journald](../00-foundations/02-systemd-journald.md)
> **后续**：[CKA 模拟考](../../labs/cka/mock-exam.md)
> **关联**（跨轨道）：[CKA-01 集群架构](01-architecture.md) · [CKA-03 kubeadm 装集群](03-kubeadm-install.md) · [CKA-10 调度](10-scheduling.md) · [F6 TLS / PKI 基础](../00-foundations/06-tls-pki-basics.md) · [RHCSA-09 防火墙与 SELinux](../rhcsa/09-security-firewalld-selinux.md)

## 1. 这个知识点在网络中的位置

排错是权重最高的领域，也是**把前面所有节点串起来**的地方：调度（K10）→ Pending，镜像/配置（K9）→ CrashLoop，Service/DNS（K11）→ 访问不通，存储（K14）→ ContainerCreating，kubeadm/证书（K3/K4）→ 控制平面挂掉。
而节点层的排错本质上就是 RHCSA 技能：`systemctl`、`journalctl`、看配置文件、看磁盘和进程。你的 docker 经验也直接可用：`crictl` 几乎就是节点上的 `docker` 命令。

| docker | 节点上（containerd） | 集群层 |
|---|---|---|
| `docker ps -a` | `crictl ps -a` / `crictl pods` | `kubectl get pods -A -o wide` |
| `docker logs` | `crictl logs <id>` | `kubectl logs` |
| `docker inspect` | `crictl inspect <id>` | `kubectl describe` / `-o yaml` |
| `docker exec -it` | `crictl exec -it <id> sh` | `kubectl exec -it` / `kubectl debug` |
| `docker images` | `crictl images` | — |

## 2. 核心概念

**分层排查模型**——从下往上，先确定是哪一层坏了：

1. **节点层**：OS（磁盘、内存、swap、时间）、`containerd`、`kubelet`（systemd 服务）。
2. **控制平面**：kube-apiserver、etcd、kube-scheduler、kube-controller-manager——kubeadm 集群里它们是**静态 Pod**，清单在 `/etc/kubernetes/manifests/`，由 kubelet 直接拉起（不经过 apiserver）。
3. **集群网络**：CNI（`/etc/cni/net.d/`、`/opt/cni/bin/`）、kube-proxy（DaemonSet）、CoreDNS（Deployment）。
4. **应用层**：Pod 状态、Service/EndpointSlice、NetworkPolicy、PVC。

**关键文件速查**（kubeadm 默认路径）：

| 路径 | 内容 |
|---|---|
| `/etc/kubernetes/manifests/*.yaml` | 静态 Pod 清单（改完 kubelet 自动重建） |
| `/etc/kubernetes/admin.conf` | 管理员 kubeconfig |
| `/etc/kubernetes/kubelet.conf` | kubelet 连接 apiserver 的 kubeconfig |
| `/var/lib/kubelet/config.yaml` | kubelet 配置（`staticPodPath`、`clusterDNS`、`cgroupDriver`…） |
| `/var/lib/kubelet/kubeadm-flags.env`、`/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf` | kubelet 启动参数（drop-in 路径因发行版而异，用 `systemctl cat kubelet` 查） |
| `/etc/kubernetes/pki/` | 集群证书（apiserver、etcd、front-proxy、CA） |
| `/etc/containerd/config.toml` | containerd 配置（`SystemdCgroup = true`） |
| `/var/log/pods/`、`/var/log/containers/` | 容器日志文件（apiserver 挂了 `kubectl logs` 用不了时就看这里） |

**Pod 状态决策树**：

| 现象 | 第一条命令 | 常见原因 → 修复 |
|---|---|---|
| `Pending` | `kubectl describe pod` 看 Events | 资源不足、污点未容忍、nodeSelector/亲和性不匹配、PVC 未绑定（→ K10/K14）；**完全没有 Events 且没有被调度** → kube-scheduler 挂了 |
| `ContainerCreating` 很久 | `describe` | 卷挂载失败（PVC/NFS/Secret 不存在）、CNI 故障（`failed to setup network`） |
| `ErrImagePull` / `ImagePullBackOff` | `describe` | 镜像名或 tag 拼错、私有仓库缺 `imagePullSecrets`、节点无法访问仓库 |
| `CreateContainerConfigError` | `describe` | 引用的 ConfigMap/Secret 或其中的 key 不存在 |
| `CrashLoopBackOff` | `kubectl logs <pod> --previous` | 启动命令/参数错、配置缺失、依赖连不上、liveness 探针误杀、**OOMKilled**（`describe` 中 Last State: `Reason: OOMKilled`，exit code 137） |
| `Running` 但 `READY 0/1` | `describe` 看 Readiness 失败信息 | readinessProbe 路径/端口错 → Service 没有 Endpoints |
| `Terminating` 卡住 | `kubectl get pod -o yaml` 看 finalizers、节点状态 | 节点失联、finalizer；必要时 `kubectl delete pod x --grace-period=0 --force` |

退出码：`1` 应用错误、`126/127` 命令不可执行/找不到、`137` 被 SIGKILL（常为 OOM）、`143` 被 SIGTERM。

**哪个组件坏了 → 什么症状**：

| 组件 | 症状 |
|---|---|
| kube-apiserver | `kubectl` 报 `connection refused` / 超时（6443） |
| etcd | apiserver 反复重启、日志里连不上 `127.0.0.1:2379` |
| kube-scheduler | 新 Pod 一直 Pending 且 Events 为空 |
| kube-controller-manager | Deployment 不创建 ReplicaSet/Pod、`scale` 无效、节点失联后 Pod 不迁移 |
| kubelet | 节点 `NotReady`，该节点上的状态不再更新 |
| kube-proxy | Service ClusterIP 不通，但直接访问 Pod IP 通 |
| CoreDNS | IP 能通、域名不通 |
| CNI | 节点 `NotReady`（`cni plugin not initialized`）、Pod 卡 ContainerCreating、跨节点 Pod 不通 |

## 3. 必会操作

```bash
# —— 全局概览（每道排错题的第一步）——
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -v Running
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl events -n app --for pod/web-0                  # 新版 kubectl 的 events 子命令
kubectl get events -n app --field-selector type=Warning

# —— 节点 NotReady ——
kubectl describe node node01 | sed -n '/Conditions/,/Addresses/p'
ssh node01
sudo systemctl status kubelet containerd
sudo journalctl -u kubelet --no-pager -n 50          # 看最近的报错
sudo journalctl -u kubelet -f                         # 跟踪
systemctl cat kubelet                                 # 看实际生效的 unit 和 drop-in
sudo vim /var/lib/kubelet/config.yaml                 # 修配置
sudo systemctl daemon-reload && sudo systemctl enable --now kubelet && sudo systemctl restart kubelet
swapon --show; df -h; free -m                         # swap 开启、磁盘满、内存不足也会导致问题

# —— 节点上的容器（apiserver 挂了也能用）——
sudo crictl ps -a | grep -E 'kube-apiserver|etcd|scheduler|controller'
sudo crictl logs --tail 30 <container-id>
sudo crictl pods --name kube-apiserver
sudo crictl info | head                               # containerd 是否正常
ls /var/log/pods/ ; sudo tail -n 30 /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log

# —— 控制平面静态 Pod ——
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # 备份到 manifests 目录之外！
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml   # 保存后 kubelet 自动重建，等 30~60 秒
watch sudo crictl ps                                       # 看容器是否起来

# —— 证书 ——
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all        # 之后需重启控制平面静态 Pod，并更新 ~/.kube/config（复制新的 admin.conf）
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer -dates

# —— kubeconfig / context ——
kubectl config get-contexts
kubectl config use-context <ctx>
kubectl config view --minify            # 当前 context 连的 server 地址、用户

# —— 资源监控（需要 metrics-server）——
kubectl top nodes
kubectl top pods -A --sort-by=memory
kubectl top pod web-0 --containers
kubectl get apiservices | grep metrics   # v1beta1.metrics.k8s.io 是否 Available

# —— 容器输出流（stdout/stderr）——
kubectl logs web-0                          # 默认第一个容器（多容器时会提示）
kubectl logs web-0 -c sidecar               # 指定容器
kubectl logs web-0 --previous               # 上一次崩溃前的日志（CrashLoop 必用）
kubectl logs deploy/web --all-containers --since=1h --timestamps
kubectl logs -l app=web --tail=20 --prefix
kubectl logs web-0 -c app | grep -i error > /opt/answers/errors.txt   # 题目要求写入文件

# —— 进容器/节点调试 ——
kubectl exec -it web-0 -- sh
kubectl debug -it web-0 --image=busybox:1.36 --target=app    # 临时容器，共享目标容器进程命名空间
kubectl debug node/node01 -it --image=busybox:1.36           # 节点根文件系统挂在 /host

# —— Service / 网络 ——
kubectl get svc,endpointslices -n app
kubectl get pods -n app --show-labels
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system get ds kube-proxy; kubectl -n kube-system logs ds/kube-proxy | tail
kubectl get netpol -A
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh   # wget / nslookup / nc -zv
```

**Service 访问不通的标准流程**：

1. `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` 有没有地址？没有 → 对比 `svc.spec.selector` 与 Pod 标签；Pod 是否 Ready。
2. 有地址 → 从临时 Pod 直接访问 **Pod IP:容器端口**：不通 → 应用没监听该端口 / NetworkPolicy / CNI。
3. Pod IP 通、ClusterIP 不通 → `targetPort` 写错或 kube-proxy 有问题。
4. ClusterIP 通、域名不通 → CoreDNS（Pod 状态、`kube-dns` Service 的 Endpoints、Corefile、Egress 策略是否挡了 53 端口）。
5. 集群外访问 NodePort 不通 → 节点防火墙（RHCSA-09 的 firewalld 知识）、`externalTrafficPolicy: Local` 而该节点上没有 Pod。

## 4. 考试坑点

- **先 `kubectl config use-context`**：每道题开头给的切换命令必须执行，在错误的集群上修好了也是 0 分。
- 需要 ssh 到节点时，做完 `exit` 回到跳板机再做下一题；节点上可能要 `sudo -i`。
- 改静态 Pod 清单前，把备份放在 `/etc/kubernetes/manifests/` **之外**——放在里面 kubelet 会把备份也当成 Pod 跑起来（同名冲突）。
- 改完 kubelet 配置必须 `systemctl restart kubelet`；改了 unit/drop-in 还要先 `daemon-reload`；题目说「重启后也要生效」要 `enable`。
- apiserver 挂掉时 `kubectl` 全部失效，别等——直接 `crictl` + `/var/log/pods` + 检查 manifest 的 YAML 缩进/参数拼写/证书路径。
- `kubectl logs` 只能看到 stdout/stderr；应用写文件的日志要用 sidecar 输出或 `kubectl exec ... cat`。
- CrashLoopBackOff 看 `--previous`，否则看到的是刚重启、还没来得及报错的新容器。
- `kubectl top` 报 `Metrics API not available` → 先修 metrics-server（实验环境常需 `--kubelet-insecure-tls`），别以为是命令写错。
- 修复后一定验证：节点 `Ready`、Pod `Running` 且 `READY` 满、Service 能 curl 通。

## 5. 动手练习

- [CKA 练习题集 · K15 排错](../../labs/cka/practice-set-1.md#k15-排错)（故意弄坏 kubelet / 静态 Pod / CoreDNS / selector / 镜像 / 探针，再修好）
- [CKA 模拟考](../../labs/cka/mock-exam.md) 第 15、16、17 题
- 建议：每天花 20 分钟让朋友（或自己写脚本）随机破坏实验集群的一个组件，计时修复。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - 集群排错：[总览](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/_index.md) · [crictl 调试节点](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/crictl.md) · [kubectl 调试节点](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/kubectl-node-debug.md) · [kubectl 故障排查](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/troubleshoot-kubectl.md) · [节点健康监控](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/monitor-node-health.md)
  - 资源监控：[资源指标管道（metrics-server）](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/resource-metrics-pipeline.md) · [资源监控工具](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/resource-usage-monitoring.md)
  - 应用排错：[总览](../../references/cka/kubernetes-docs/tasks/debug/debug-application/_index.md) · [调试 Pod](../../references/cka/kubernetes-docs/tasks/debug/debug-application/debug-pods.md) · [调试运行中的 Pod（kubectl debug）](../../references/cka/kubernetes-docs/tasks/debug/debug-application/debug-running-pod.md) · [调试 Service](../../references/cka/kubernetes-docs/tasks/debug/debug-application/debug-service.md) · [确定 Pod 失败原因](../../references/cka/kubernetes-docs/tasks/debug/debug-application/determine-reason-pod-failure.md) · [调试 Init 容器](../../references/cka/kubernetes-docs/tasks/debug/debug-application/debug-init-containers.md)
  - [日志架构（sidecar 输出日志）](../../references/cka/kubernetes-docs/concepts/cluster-administration/logging.md) · [调试 DNS](../../references/cka/kubernetes-docs/tasks/administer-cluster/dns-debugging-resolution.md) · [静态 Pod](../../references/cka/kubernetes-docs/tasks/configure-pod-container/static-pod.md) · [kubeadm 证书管理](../../references/cka/kubernetes-docs/tasks/administer-cluster/kubeadm/kubeadm-certs.md) · [kubeadm 故障排查](../../references/cka/kubernetes-docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm.md) · [节点](../../references/cka/kubernetes-docs/concepts/architecture/nodes.md)
  - [kubectl 速查表](../../references/cka/kubernetes-docs/reference/kubectl/quick-reference.md)（logs / top / debug 全部用法）
- 考场（kubernetes.io）：
  - `/docs/tasks/debug/`（Troubleshooting 总入口，下面分 Cluster / Application 两支）
  - `/docs/tasks/debug/debug-application/debug-service/`（按步骤排查 Service，几乎就是上面的流程）
  - `/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/`
  - 命令行：`kubectl logs -h`、`kubectl debug -h`、`kubectl top pod -h`、`crictl --help`、`journalctl -h`

## 7. 自测清单

- [ ] 节点 NotReady：能在 5 分钟内定位到 kubelet / containerd / CNI / 证书中的哪一个，并修复
- [ ] 能在 apiserver 不可用时用 `crictl` 和 `/var/log/pods` 找到报错并修好静态 Pod 清单
- [ ] 能根据 Pod 状态（Pending / ContainerCreating / ImagePullBackOff / CrashLoopBackOff / 0/1 Ready）说出第一条排查命令和三种常见原因
- [ ] 能用 `kubeadm certs check-expiration` 检查并续期证书
- [ ] 能按「EndpointSlice → Pod IP → ClusterIP → DNS」的顺序排查 Service 不通
- [ ] 能用 `kubectl top` 找出命名空间里内存占用最高的 Pod 并把名字写入指定文件
- [ ] 能取出多容器 Pod 中指定容器上一次崩溃的日志
