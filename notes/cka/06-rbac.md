# CKA-06 RBAC 与 ServiceAccount

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Manage role based access control (RBAC)」 ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[CKA-02 kubectl 高效操作](02-kubectl-efficiency.md) · [F6 TLS/PKI 基础](../00-foundations/06-tls-pki-basics.md)
> **后续**：[CKA-09 工作负载](09-workloads.md) · [CKA-07 Helm 与 Kustomize](07-helm-kustomize.md)（chart 里常带 RBAC 清单）
> **关联**（跨轨道）：[RHCSA-08 用户、组与 sudo](../rhcsa/08-users-groups-sudo.md)（sudoers ↔ RoleBinding） · [RHCE-02 Inventory 与 ansible.cfg](../rhce/02-inventory-and-config.md)（become 提权 ↔ 权限最小化）

## 1. 这个知识点在网络中的位置

apiserver 处理每个请求都要走三关：**认证（你是谁）→ 鉴权（你能干什么）→ 准入（这个请求合不合规）**。RBAC 就是第二关。
它和 RHCSA 的 sudo 很像：sudoers 规定「哪个用户/组可以在哪些主机上执行哪些命令」，RBAC 规定「哪个用户/组/ServiceAccount 可以在哪个命名空间对哪些资源做哪些动作」。
考试常见题型：给某个 ServiceAccount 或用户授予最小权限，并用 `kubectl auth can-i` 验证。

## 2. 核心概念

### 2.1 四个对象

| 对象 | 作用范围 | 内容 |
|---|---|---|
| `Role` | 单个命名空间 | 规则列表：apiGroups + resources + verbs |
| `ClusterRole` | 全集群（也可被 RoleBinding 引用到某个命名空间） | 同上，还能授权节点、PV、命名空间等集群级资源和非资源 URL |
| `RoleBinding` | 单个命名空间 | 把 Role **或 ClusterRole** 绑定给 subjects，只在本命名空间生效 |
| `ClusterRoleBinding` | 全集群 | 把 ClusterRole 绑定给 subjects，所有命名空间生效 |

记忆：**Role 定义「能做什么」，Binding 定义「谁」和「在哪」。** RBAC 只有允许规则，没有拒绝规则。

### 2.2 subjects：三种身份

| 类型 | 来源 | 写法 |
|---|---|---|
| User | 客户端证书的 CN（或 OIDC 等），K8s 里**没有 User 对象** | `--user=jane` |
| Group | 客户端证书的 O 字段 | `--group=dev-team` |
| ServiceAccount | K8s 对象，Pod 内进程使用 | `--serviceaccount=<ns>:<name>`；在 `--as` 里写成 `system:serviceaccount:<ns>:<name>` |

### 2.3 规则字段

- `apiGroups`：核心组写 `""`；Deployment 在 `apps`；Ingress/NetworkPolicy 在 `networking.k8s.io`。不确定就 `kubectl api-resources | grep <资源>` 看 APIVERSION 列。
- `resources`：复数小写，如 `pods`、`deployments`；子资源写成 `pods/log`、`pods/exec`、`deployments/scale`。
- `verbs`：`get list watch create update patch delete deletecollection`，`*` 代表全部。
- `resourceNames`：限定到具体对象名。

### 2.4 内置 ClusterRole

`cluster-admin`（全部权限）、`admin`（命名空间内几乎全部）、`edit`（读写大多数对象，不能改 RBAC）、`view`（只读，不能看 Secret）。
常见做法：`RoleBinding` 引用 ClusterRole `view`，就能把「只读」限定在一个命名空间里。

### 2.5 ServiceAccount 与 token

- 每个命名空间自动有 `default` SA；Pod 不指定就用它。
- 当前版本中 Pod 内的 token 是**有时效的投射卷（projected token）**，不再自动生成长期 Secret。
- 需要临时 token：`kubectl create token <sa>`。
- 不想挂载 token：`automountServiceAccountToken: false`。

## 3. 必会操作

```bash
# —— ServiceAccount + Role + RoleBinding（最常考）——
k create ns dev
k create sa deployer -n dev
k create role deploy-mgr -n dev --verb=get,list,watch,create,update,patch,delete --resource=deployments,replicasets,pods
k create rolebinding deploy-mgr-bind -n dev --role=deploy-mgr --serviceaccount=dev:deployer
k auth can-i create deployments -n dev --as=system:serviceaccount:dev:deployer   # yes
k auth can-i delete nodes --as=system:serviceaccount:dev:deployer                # no
k auth can-i --list -n dev --as=system:serviceaccount:dev:deployer

# —— ClusterRole + ClusterRoleBinding ——
k create clusterrole node-reader --verb=get,list,watch --resource=nodes
k create clusterrolebinding node-reader-bind --clusterrole=node-reader --user=jane
k create rolebinding jane-view -n dev --clusterrole=view --user=jane              # ClusterRole 限定到 dev

# —— 子资源与 resourceNames ——
k create role log-reader -n dev --verb=get --resource=pods,pods/log
k create role cm-one -n dev --verb=get,update --resource=configmaps --resource-name=app-cfg

# —— Pod 使用 SA ——
k run app -n dev --image=nginx --overrides='{"apiVersion":"v1","spec":{"serviceAccountName":"deployer"}}'
k set serviceaccount deploy/web deployer -n dev          # 已有 Deployment 换 SA（会触发滚动更新）
k create token deployer -n dev --duration=1h
k describe rolebinding deploy-mgr-bind -n dev
k get rolebinding,clusterrolebinding -A -o wide | grep deployer   # 反查某个身份有哪些绑定
```

### 3.1 给新用户签发证书（CSR 流程）

```bash
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane/O=dev-team"     # CN=用户名，O=组
cat <<EOF | k apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 -w0 < jane.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF
k get csr && k certificate approve jane
k get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt

# 写入 kubeconfig 并测试
k config set-credentials jane --client-key=jane.key --client-certificate=jane.crt --embed-certs=true
k config set-context jane@kubernetes --cluster=kubernetes --user=jane --namespace=dev
k --context=jane@kubernetes get pods     # 绑定权限前应为 Forbidden
```

## 4. 考试坑点

- `--serviceaccount` 的格式是 `命名空间:名字`；`--as` 的格式是 `system:serviceaccount:命名空间:名字`，两者别混。
- 授权 Deployment 时 `apiGroups` 是 `apps`；用 `kubectl create role` 会自动推断，手写 YAML 最容易错。
- RoleBinding 不能引用其他命名空间的 Role；但可以引用 ClusterRole。
- `roleRef` 创建后**不可修改**，要换角色只能删掉 Binding 重建。
- 题目说「只允许在 namespace X」时，不要用 ClusterRoleBinding。
- 写完一定用 `kubectl auth can-i` 正反各验证一次（应该能的 yes、不该能的 no）。

## 5. 动手练习

- [labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md) 中 RBAC 相关题
- 给 SA `ci` 只授予在 `staging` 命名空间更新 Deployment 镜像（`patch deployments`）的权限，验证不能删除。
- 用 CSR 流程创建用户 `bob`（组 `qa`），把内置 `view` 角色通过 RoleBinding 授予组 `qa`，再用 bob 的 context 验证。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| **RBAC 鉴权（含完整示例 YAML）** | [reference/access-authn-authz/rbac.md](../../references/cka/kubernetes-docs/reference/access-authn-authz/rbac.md) | kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| 认证（用户、证书、token） | [reference/access-authn-authz/authentication.md](../../references/cka/kubernetes-docs/reference/access-authn-authz/authentication.md) | kubernetes.io/docs/reference/access-authn-authz/authentication/ |
| **CSR：给普通用户签发证书** | [reference/access-authn-authz/certificate-signing-requests.md](../../references/cka/kubernetes-docs/reference/access-authn-authz/certificate-signing-requests.md) | kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/ |
| ServiceAccount 概念 | [concepts/security/service-accounts.md](../../references/cka/kubernetes-docs/concepts/security/service-accounts.md) | kubernetes.io/docs/concepts/security/service-accounts/ |
| 为 Pod 配置 ServiceAccount | [tasks/configure-pod-container/configure-service-account.md](../../references/cka/kubernetes-docs/tasks/configure-pod-container/configure-service-account.md) | kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/ |
| RBAC 最佳实践 | [concepts/security/rbac-good-practices.md](../../references/cka/kubernetes-docs/concepts/security/rbac-good-practices.md) | kubernetes.io/docs/concepts/security/rbac-good-practices/ |
| kubeconfig 组织 | [concepts/configuration/organize-cluster-access-kubeconfig.md](../../references/cka/kubernetes-docs/concepts/configuration/organize-cluster-access-kubeconfig.md) | kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/ |

考场技巧：搜 `certificate signing request`，页面里「Normal user」一节就是完整的 openssl + CSR + kubeconfig 流程。

## 7. 自测清单

- [ ] 能说清楚 Role/ClusterRole/RoleBinding/ClusterRoleBinding 的四种组合各自效果
- [ ] 2 分钟内用命令式完成「SA + Role + RoleBinding + can-i 验证」
- [ ] 知道 Deployment、Ingress、NetworkPolicy 各自的 apiGroup
- [ ] 能完成 CSR 签发用户证书并配置 kubeconfig context
- [ ] 能说出 4 个内置 ClusterRole 的区别，以及 `view` 为什么看不到 Secret
