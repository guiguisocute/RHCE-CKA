# Go-13 Controller 与 Operator：controller-runtime 与 kubebuilder

> **轨道**：[Go](README.md) ｜ **运维场景**：「每个打了标签的命名空间都必须有默认拒绝的 NetworkPolicy」「用户建一个 StaticSite 对象，自动给他配好 Deployment + Service」——把运维规范写成持续生效的控制循环 ｜ **建议用时**：6 h（第 21 周读源码，第 22 周用 kubebuilder 做项目） ｜ **难度**：★★★★
>
> **前置**：[Go-12 client-go](12-client-go.md)
> **后续**：Go 轨道的终点之一。之后可以读 Kubernetes 自带 controller 的源码，或者研究你在用的 operator
> **关联**（跨轨道）：[CKA-08 扩展接口、CRD 与 Operator](../cka/08-extension-interfaces-crd.md) · [CKA-01 集群架构](../cka/01-architecture.md)（controller-manager 就是一堆 controller）· [CKA-06 RBAC](../cka/06-rbac.md) · [CKA-12 NetworkPolicy](../cka/12-network-policy.md) · [RHCE-04 Playbook 与幂等](../rhce/04-playbooks.md)

## 1. 这个知识点在网络中的位置

CKA 考纲要求「理解 CRD，安装和配置 operator」。考试里你只需要会装和用，这一节你要自己写一个，写过之后整个 Kubernetes 的工作方式就清楚了：

- **声明式**：你只写期望状态（`replicas: 3`），controller 负责不断把实际状态往期望状态拉。CKA-01 里的 kube-controller-manager 就是几十个这样的 controller。
- **幂等**：Reconcile 会被反复调用（对象变化、子资源变化、定期 resync、出错重试），**不管调用多少次，结果都必须一样**。这和 RHCE 里 Ansible 模块的幂等是同一个思想：先看现状，不一样才改。
- **Operator = CRD + 懂业务的 controller**：比如 Prometheus Operator 根据 `ServiceMonitor` 对象生成抓取配置。

| 你见过的 | 本节对应的 |
|---|---|
| Ansible：`state: present` 的模块，第二次运行 `changed=0` | `controllerutil.CreateOrUpdate`，没变化时返回 `unchanged` |
| Deployment 自动重建被删掉的 Pod | `Owns(&Deployment{})`：子资源被删 → 触发 Reconcile → 重新创建 |
| 删除 Deployment，ReplicaSet 和 Pod 一起没了 | OwnerReference + 垃圾回收 |
| `kubectl get crd`、`kubectl explain` | kubebuilder 生成的 CRD，带 OpenAPI 校验 |

## 2. 核心概念

- **controller-runtime**：在 client-go 之上封装的框架（`sigs.k8s.io/controller-runtime`）。`Manager` 管理共享缓存和多个 controller；`Client` 的读操作走 informer 缓存，写操作直接发给 apiserver；你只需要实现 `Reconcile(ctx, req) (Result, error)`。
- **版本对应**：controller-runtime 的小版本跟着 Kubernetes 走，写作时 v0.25.2 依赖 k8s.io/* v0.37.0（Kubernetes 1.37）。以它的 README 兼容性表为准。
- **kubebuilder**：脚手架工具。`init` 生成项目骨架（Makefile、main.go、config/ 下的 kustomize 清单），`create api` 生成 CRD 类型和 controller 骨架，代码里的 `// +kubebuilder:...` 标记会被 controller-gen 转成 CRD 校验规则和 RBAC 清单。
- **Level-triggered**：Reconcile 只拿到对象的名字（`req.NamespacedName`），不告诉你「发生了什么变化」。你要做的永远是：读当前状态 → 和期望比较 → 补齐差异。
- **status 子资源**：spec 是用户写的，status 是 controller 写的。更新 status 用 `r.Status().Update()`。
- **finalizer**：删除前要做清理（比如删外部的云资源）时用；只管集群内子资源的话，用 OwnerReference 让垃圾回收处理就够了。

## 3. 必会操作

### 3.1 第一个 controller：用内置资源，不需要 CRD

```bash
go mod init example.com/nsguard
go get sigs.k8s.io/controller-runtime@v0.25.2   # 会带上 k8s.io/* v0.37.0；需要 go 1.26
```

需求：命名空间带 `netpol=default-deny` 标签时，自动创建一条拒绝所有入站流量的 NetworkPolicy（[CKA-12](../cka/12-network-policy.md) 里的 default-deny）；标签去掉时删除。

```go
// +kubebuilder:rbac:groups="",resources=namespaces,verbs=get;list;watch
// +kubebuilder:rbac:groups=networking.k8s.io,resources=networkpolicies,verbs=get;list;watch;create;update;patch;delete

func (r *NamespaceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	var ns corev1.Namespace
	if err := r.Get(ctx, req.NamespacedName, &ns); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err) // 命名空间已删除：没事可做
	}
	np := &networkingv1.NetworkPolicy{ObjectMeta: metav1.ObjectMeta{Name: policyName, Namespace: ns.Name}}

	if ns.Labels[labelKey] != labelValue { // 期望状态：不应该有这条策略
		if err := r.Delete(ctx, np); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, err
		}
		return ctrl.Result{}, nil
	}
	// 期望状态：存在一条选中所有 Pod、不放行任何入站流量的策略
	op, err := controllerutil.CreateOrUpdate(ctx, r.Client, np, func() error {
		np.Labels = map[string]string{"app.kubernetes.io/managed-by": "nsguard"}
		np.Spec.PodSelector = metav1.LabelSelector{}                                     // 空选择器 = 所有 Pod
		np.Spec.PolicyTypes = []networkingv1.PolicyType{networkingv1.PolicyTypeIngress} // 没写 ingress 规则 = 全部拒绝
		return controllerutil.SetControllerReference(&ns, np, r.Scheme())                // 命名空间删除时一并回收
	})
	if err != nil {
		return ctrl.Result{}, err // 返回错误 = 稍后自动重试（带退避）
	}
	if op != controllerutil.OperationResultNone {
		logger.Info("reconciled", "namespace", ns.Name, "operation", op) // created / updated
	}
	return ctrl.Result{}, nil
}

func (r *NamespaceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Namespace{}).            // 监听 Namespace
		Owns(&networkingv1.NetworkPolicy{}). // 策略被人改动或删掉时，也会触发所属 Namespace 的 Reconcile
		Complete(r)
}
```

`main` 里只有三步：`ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{})` → `SetupWithManager(mgr)` → `mgr.Start(ctrl.SetupSignalHandler())`。
开头两行 `+kubebuilder:rbac` 标记在 kubebuilder 项目里由 `make manifests` 转成 ClusterRole；这里没有用 kubebuilder，可以用 `controller-gen rbac:roleName=nsguard paths=./...` 生成，或者照着写一个 ClusterRole（参数以 `controller-gen -h` 为准）。

**幂等性测试**（controller-runtime 自带假 client，不需要集群；已通过）：

```go
c := fake.NewClientBuilder().WithObjects(ns).Build()
r := &NamespaceReconciler{Client: c}
for i := 0; i < 2; i++ { // 连续调两次
	if _, err := r.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
}
// 断言：只存在 1 条 NetworkPolicy，并且带 OwnerReference；去掉标签再 Reconcile 一次，策略被删除
```

```bash
go run .                                          # 用当前 kubeconfig 连集群
kubectl create ns shop && kubectl label ns shop netpol=default-deny
kubectl -n shop get networkpolicy                 # default-deny-ingress 出现
kubectl -n shop delete networkpolicy default-deny-ingress && kubectl -n shop get networkpolicy   # 又被建回来了
```

### 3.2 用 kubebuilder 写带 CRD 的 operator（流程以 Kubebuilder Book 快速开始为准）

```bash
curl -L -o kubebuilder "https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)"
chmod +x kubebuilder && sudo mv kubebuilder /usr/local/bin/
mkdir staticsite && cd staticsite
kubebuilder init --domain lab.local --repo example.com/staticsite
kubebuilder create api --group web --version v1alpha1 --kind StaticSite   # 两个问题都回答 y
# 编辑 api/v1alpha1/staticsite_types.go（spec/status 字段 + 校验标记）
# 编辑 internal/controller/staticsite_controller.go（Reconcile 逻辑）
make manifests        # 根据标记生成 CRD 和 RBAC 清单
make install          # 把 CRD 装进当前集群
make run              # 在本机跑 controller
kubectl apply -k config/samples/
make test             # envtest：本地起 apiserver + etcd 跑测试
make docker-build docker-push IMG=<registry>/staticsite:v0.1.0 && make deploy IMG=<registry>/staticsite:v0.1.0
```

## 4. 考试坑点

- **Reconcile 里直接 `Create`**：第二次调用就报 `AlreadyExists`。用 `CreateOrUpdate`，或者先 `Get` 判断 `IsNotFound`。
- **每次都写对象**：即使没变化也 `Update`，会触发新的事件，再进 Reconcile，形成死循环。`CreateOrUpdate` 会先比较再写。
- **更新 status 用了 `r.Update()`**：开启 status 子资源后，`Update` 会忽略 status 的改动。要用 `r.Status().Update()`。
- **忘了 RBAC 标记**：本机 `make run` 用的是你自己的 kubeconfig（通常是 cluster-admin），一切正常；`make deploy` 进集群后用 ServiceAccount，立刻 `forbidden`。
- **OwnerReference 方向**：命名空间级对象可以以集群级对象（如 Namespace）为 owner，反过来不行；跨命名空间的 owner 也不行。
- **finalizer 写了却不移除**：对象会一直卡在 Terminating（CKA 排错里常见的现象，原因就在这里）。

## 5. 动手练习

- 第 21 周：读 [sample-controller 的 controller.go](../../references/go/k8s/sample-controller/controller.go)，对照 [原理图](../../references/go/k8s/sample-controller/docs/controller-client-go.md) 找到 informer、workqueue、syncHandler 三部分；然后实现本节的 nsguard。
- 第 22 周项目：[P11 operator：StaticSite CRD + controller](../../labs/go/projects.md#p11)。

**配套 LeetCode（第 21~22 周，[刷题计划](../../labs/go/leetcode-plan.md#w21)）**

- [875. 爱吃香蕉的珂珂](https://leetcode.cn/problems/koko-eating-bananas/)：在答案上二分，≈ 找能扛住流量的最小副本数
- [1011. 在 D 天内送达包裹的能力](https://leetcode.cn/problems/capacity-to-ship-packages-within-d-days/)：同一个套路的容量规划题
- 第 22 周（[计划](../../labs/go/leetcode-plan.md#w22)）：[1396. 设计地铁系统](https://leetcode.cn/problems/design-underground-system/)、[1472. 设计浏览器历史记录](https://leetcode.cn/problems/design-browser-history/)、[460. LFU 缓存](https://leetcode.cn/problems/lfu-cache/)（困难）：练「设计类」题，和设计 CRD 的 spec/status 一样，先想清楚状态怎么存

## 6. 官方文档（本仓库离线版 + 本机查法）

- Kubebuilder Book：[快速开始](../../references/go/k8s/kubebuilder-book/quick-start.md)、[架构](../../references/go/k8s/kubebuilder-book/architecture.md)、[CronJob 教程：controller 概览](../../references/go/k8s/kubebuilder-book/cronjob-tutorial/controller-overview.md)、[controller 实现](../../references/go/k8s/kubebuilder-book/cronjob-tutorial/controller-implementation.md)
- 标记与测试：[RBAC 标记](../../references/go/k8s/kubebuilder-book/reference/markers/rbac.md)、[CRD 校验标记](../../references/go/k8s/kubebuilder-book/reference/markers/crd-validation.md)、[envtest](../../references/go/k8s/kubebuilder-book/reference/envtest.md)、[finalizer](../../references/go/k8s/kubebuilder-book/reference/using-finalizers.md)、[最佳实践](../../references/go/k8s/kubebuilder-book/reference/good-practices.md)
- 官方示例控制器：[sample-controller](../../references/go/k8s/sample-controller/README.md)
- Kubernetes 文档：[controller 概念](../../references/cka/kubernetes-docs/concepts/architecture/controller.md)、[CRD](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/api-extension/custom-resources.md)、[Operator 模式](../../references/cka/kubernetes-docs/concepts/extend-kubernetes/operator.md)、[owner 与 dependent](../../references/cka/kubernetes-docs/concepts/overview/working-with-objects/owners-dependents.md)
- 本机：`go doc sigs.k8s.io/controller-runtime/pkg/controller/controllerutil.CreateOrUpdate`、`kubebuilder --help`

## 7. 自测清单

- [ ] 能用自己的话解释「level-triggered」和「Reconcile 必须幂等」，并和 Ansible 的幂等对比
- [ ] 不用 CRD，写出一个监听内置资源的 controller，并用 fake client 测试连续 Reconcile 两次的结果
- [ ] 能说出 `For()` 和 `Owns()` 的区别，以及 OwnerReference 对垃圾回收的作用
- [ ] 会用 kubebuilder 完成 `init` → `create api` → `make manifests install run`
- [ ] 能写出 RBAC 标记，并解释为什么本机 `make run` 正常、部署后却 forbidden
- [ ] 能解释一个对象卡在 Terminating 时，finalizer 起了什么作用
