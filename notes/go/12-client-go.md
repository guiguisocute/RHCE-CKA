# Go-12 client-go：用代码操作 Kubernetes

> **轨道**：[Go](README.md) ｜ **运维场景**：写一个巡检工具，一条命令列出全集群所有不健康的 Pod 和原因；或者持续 watch Pod 变化，出问题就发告警 ｜ **建议用时**：5 h（第 18 周，第 19 周学 watch / informer） ｜ **难度**：★★★
>
> **前置**：[Go-04 方法、接口与泛型](04-methods-interfaces-generics.md) · [Go-07 并发与 context](07-concurrency-context.md)
> **后续**：[Go-13 Controller 与 Operator](13-controller-operator.md)
> **关联**（跨轨道）：[CKA-01 集群架构](../cka/01-architecture.md)（一切都经过 apiserver）· [CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md) · [CKA-06 RBAC 与 ServiceAccount](../cka/06-rbac.md) · [CKA-15 排错](../cka/15-troubleshooting.md)

## 1. 这个知识点在网络中的位置

kubectl 本身就是一个 client-go 程序：读 kubeconfig、向 apiserver 发 REST 请求、把 JSON 解析成 Go 结构体。学会 client-go，你就能把 CKA 排错时手敲的一串 `kubectl get / describe` 变成一个可重复执行的工具，也为下一节写 controller 打基础。

| kubectl | client-go |
|---|---|
| `~/.kube/config`、`KUBECONFIG`、`--context` | `clientcmd` 的加载规则，行为和 kubectl 一致 |
| `kubectl get pods -A` | `cs.CoreV1().Pods("").List(ctx, metav1.ListOptions{})` |
| `kubectl get pods -l app=web` | `ListOptions{LabelSelector: "app=web"}` |
| `kubectl get pods -w` | `Watch`，或者更稳的 **informer** |
| `kubectl auth can-i list pods --as=system:serviceaccount:ops:kpods` | 程序在 Pod 里跑时用的就是这个 ServiceAccount 的权限 |

## 2. 核心概念

- **版本对应**：`k8s.io/client-go`、`k8s.io/api`、`k8s.io/apimachinery` 的 `v0.X.Y` 对应 Kubernetes `1.X.Y`。写作时最新是 v0.37.2，对应 Kubernetes 1.37。三个模块保持同一个版本，并尽量和集群的小版本一致；相差一个小版本通常也能用，但新字段可能缺失，以 client-go 仓库 README 的兼容性说明为准。
- **配置来源**：集群外用 kubeconfig（out-of-cluster），Pod 里用挂载进来的 ServiceAccount token（in-cluster，`rest.InClusterConfig()`）。
- **Clientset**：按 API 组生成的强类型客户端，`cs.CoreV1()`、`cs.AppsV1()`、`cs.NetworkingV1()`……返回的是 `k8s.io/api` 里的 struct，字段和 YAML 一一对应（`kubectl explain pod.status` 看到的字段）。
- **Informer**：先 List 一次，再持续 Watch，把对象缓存在本地内存里，变化时回调你的函数。断线会自动重连并重新 List。controller 都建立在 informer 之上。
- **Workqueue**：informer 回调里只把对象的 key（`namespace/name`）放进队列，由 worker 慢慢处理，失败了限速重试。`client-go-examples/workqueue` 就是这个模式。

## 3. 必会操作

```bash
go mod init example.com/kpods
go get k8s.io/client-go@v0.37.2 k8s.io/api@v0.37.2 k8s.io/apimachinery@v0.37.2   # 版本与集群对齐
```

> client-go v0.37 要求 go 1.26，`go get` 会自动抬高 `go.mod` 里的 go 版本。

核心代码（完整版带 `-n`、`--context` 参数和表格输出，已用 `fake.NewClientset` 写单元测试并通过 `go test -race`）：

```go
// newClient 优先用 kubeconfig（和 kubectl 一样认 KUBECONFIG 和 --context），在 Pod 里退回 in-cluster 配置
func newClient(kubeContext string) (kubernetes.Interface, error) {
	rules := clientcmd.NewDefaultClientConfigLoadingRules()
	overrides := &clientcmd.ConfigOverrides{CurrentContext: kubeContext}
	cfg, err := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, overrides).ClientConfig()
	if err != nil {
		if cfg, err = rest.InClusterConfig(); err != nil {
			return nil, fmt.Errorf("既没有可用的 kubeconfig，也不在集群内: %w", err)
		}
	}
	cfg.Timeout = 15 * time.Second
	return kubernetes.NewForConfig(cfg)
}

// reason 把 Pod 状态翻译成 CKA 排错时最先要看的那个原因
func reason(p *corev1.Pod) (string, int32, bool) {
	var restarts int32
	for _, cs := range p.Status.ContainerStatuses {
		restarts += cs.RestartCount
		if w := cs.State.Waiting; w != nil { // CrashLoopBackOff、ImagePullBackOff……
			return w.Reason, restarts, true
		}
		if t := cs.State.Terminated; t != nil && t.ExitCode != 0 {
			return fmt.Sprintf("Terminated(%s, exit %d)", t.Reason, t.ExitCode), restarts, true
		}
	}
	switch p.Status.Phase {
	case corev1.PodPending:
		for _, c := range p.Status.Conditions {
			if c.Type == corev1.PodScheduled && c.Status == corev1.ConditionFalse {
				return c.Reason + ": " + c.Message, restarts, true // Unschedulable：资源 / 污点 / PVC
			}
		}
		return "Pending", restarts, true
	case corev1.PodFailed, corev1.PodUnknown:
		return string(p.Status.Phase) + " " + p.Status.Reason, restarts, true
	}
	return "", restarts, false
}

func unhealthy(ctx context.Context, cs kubernetes.Interface, ns string) ([]Finding, error) {
	pods, err := cs.CoreV1().Pods(ns).List(ctx, metav1.ListOptions{}) // ns 为空 = 所有命名空间
	if err != nil {
		return nil, err
	}
	var out []Finding
	for i := range pods.Items {
		p := &pods.Items[i]
		if p.Status.Phase == corev1.PodSucceeded { // Job 跑完的 Pod 不算问题
			continue
		}
		if r, n, bad := reason(p); bad {
			out = append(out, Finding{p.Namespace, p.Name, string(p.Status.Phase), r, n})
		}
	}
	return out, nil
}
```

测试不需要真集群，把 `kubernetes.Interface` 换成假的实现即可（这就是 [G4](04-methods-interfaces-generics.md) 里讲的「面向接口编程」的好处）：

```go
cs := fake.NewClientset(&corev1.Pod{ /* 构造一个 CrashLoopBackOff 的 Pod */ })
got, err := unhealthy(context.Background(), cs, "")
```

### 3.1 watch：informer 版的 `kubectl get pods -w`

```go
factory := informers.NewSharedInformerFactoryWithOptions(cs, 10*time.Minute, informers.WithNamespace(ns))
podInformer := factory.Core().V1().Pods().Informer()
podInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
	AddFunc: func(obj any) { p := obj.(*corev1.Pod); fmt.Println("ADD", p.Namespace+"/"+p.Name) },
	UpdateFunc: func(oldObj, newObj any) {
		o, n := oldObj.(*corev1.Pod), newObj.(*corev1.Pod)
		if o.Status.Phase != n.Status.Phase {
			fmt.Println("UPDATE", n.Name, o.Status.Phase, "->", n.Status.Phase)
		}
	},
	DeleteFunc: func(obj any) { fmt.Println("DELETE", obj) }, // 可能收到 DeletedFinalStateUnknown，要做类型判断
})
factory.Start(ctx.Done())                                       // 后台：先 List，再 Watch
if !cache.WaitForCacheSync(ctx.Done(), podInformer.HasSynced) { // 等本地缓存第一次填满
	return fmt.Errorf("cache 同步失败")
}
<-ctx.Done()
```

### 3.2 运维场景示例：在集群里定时巡检

把 kpods 做成 CronJob，每 10 分钟跑一次，发现问题时退出码为 2（Job 显示失败，便于告警）。需要的 RBAC：

```bash
kubectl create ns ops
kubectl -n ops create serviceaccount kpods
kubectl create clusterrole pod-reader --verb=get,list,watch --resource=pods
kubectl create clusterrolebinding kpods-pod-reader --clusterrole=pod-reader --serviceaccount=ops:kpods
kubectl auth can-i list pods -A --as=system:serviceaccount:ops:kpods     # yes
kubectl auth can-i delete pods -A --as=system:serviceaccount:ops:kpods   # no：最小权限
```

镜像按 [G11](11-containerize-deploy.md) 的方式构建，CronJob 的 Pod 模板里写 `serviceAccountName: kpods`。程序里的 `rest.InClusterConfig()` 会自动读取 `/var/run/secrets/kubernetes.io/serviceaccount/` 下的 token 和 CA。

## 4. 考试坑点

- client-go、api、apimachinery 三个模块版本不一致，会出现一堆编译错误。统一用同一个 `v0.X.Y`。
- `List` 返回的 `Items` 是值切片：`for _, p := range pods.Items` 会复制整个 Pod 结构体，用下标 `&pods.Items[i]` 更省。
- 只在本机测过 kubeconfig，放进集群就报 `Forbidden`：ServiceAccount 默认没有任何权限，RBAC 要自己授权（[CKA-06](../cka/06-rbac.md)）。
- 直接用 `Watch` 写长期运行的程序，连接断开后不会自动恢复，还会漏事件。长期运行的场景用 informer。
- informer 回调拿到的对象是共享缓存里的指针，**不要修改它**；要改就先 `p.DeepCopy()`。

## 5. 动手练习

- 项目：[P9 kpods：找出不健康的 Pod](../../labs/go/projects.md#p9)（第 18~19 周）：第 18 周做 List 版，第 19 周加 `-w` watch 模式
- 对照练习：在自己的 kind 集群里制造 ImagePullBackOff、CrashLoopBackOff、Pending（资源请求超大），检查 kpods 的输出和 `kubectl describe` 是否一致

**配套 LeetCode（第 18~19 周，[刷题计划](../../labs/go/leetcode-plan.md#w18)）**

- [380. O(1) 时间插入、删除和获取随机元素](https://leetcode.cn/problems/insert-delete-getrandom-o1/)：map + 切片的组合，informer 本地缓存的索引也是类似思路
- [528. 按权重随机选择](https://leetcode.cn/problems/random-pick-with-weight/)：按权重把流量分给后端（前缀和 + 二分）
- 第 19 周（[计划](../../labs/go/leetcode-plan.md#w19)）：[743. 网络延迟时间](https://leetcode.cn/problems/network-delay-time/)（Dijkstra）、[547. 省份数量](https://leetcode.cn/problems/number-of-provinces/)（并查集：网络分区）、[684. 冗余连接](https://leetcode.cn/problems/redundant-connection/)（找出成环的那条链路）

## 6. 官方文档（本仓库离线版 + 本机查法）

- client-go 官方示例：[out-of-cluster](../../references/go/k8s/client-go-examples/out-of-cluster-client-configuration/main.go)、[in-cluster](../../references/go/k8s/client-go-examples/in-cluster-client-configuration/main.go)、[workqueue](../../references/go/k8s/client-go-examples/workqueue/main.go)、[fake-client 测试](../../references/go/k8s/client-go-examples/fake-client/main_test.go)、[创建/更新/删除 Deployment](../../references/go/k8s/client-go-examples/create-update-delete-deployment/main.go)
- informer / workqueue 原理图解：[controller-client-go.md](../../references/go/k8s/sample-controller/docs/controller-client-go.md)
- API 约定（List、Watch、resourceVersion）：[api-concepts.md](../../references/cka/kubernetes-docs/reference/using-api/api-concepts.md)
- 在 Pod 里访问 API：[access-api-from-pod.md](../../references/cka/kubernetes-docs/tasks/run-application/access-api-from-pod.md)
- RBAC：[rbac.md](../../references/cka/kubernetes-docs/reference/access-authn-authz/rbac.md)
- 本机：`go doc k8s.io/client-go/kubernetes.Interface`、`kubectl explain pod.status.containerStatuses.state`

## 7. 自测清单

- [ ] 能说出 client-go `v0.37.x` 对应哪个 Kubernetes 版本
- [ ] 能写出同时支持 kubeconfig 和 in-cluster 的 `newClient`
- [ ] 能用 fake clientset 给自己的函数写单元测试
- [ ] 能解释 informer 相比直接 Watch 多做了什么（初始 List、本地缓存、断线重连）
- [ ] 能给一个 ServiceAccount 授予最小权限，并用 `kubectl auth can-i --as` 验证
- [ ] 能用 kpods 定位一个 CrashLoopBackOff 的 Pod，再用 `kubectl logs --previous` 找到根因
