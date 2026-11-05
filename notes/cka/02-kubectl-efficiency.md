# CKA-02 kubectl 高效操作

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA 全部领域的基本功（考试 2 小时、十几道实操题，速度就是分数） ｜ **建议用时**：6 h（之后每天 15 分钟保持手感） ｜ **难度**：★☆☆
>
> **前置**：[CKA-01 集群架构与组件](01-architecture.md) · [F4 YAML 语法](../00-foundations/04-yaml.md) · [F7 vim / tmux / 考场效率](../00-foundations/07-vim-tmux-exam-efficiency.md)
> **后续**：[CKA-06 RBAC 与 ServiceAccount](06-rbac.md) · [CKA-09 工作负载](09-workloads.md)
> **关联**（跨轨道）：[RHCE-03 Ad-hoc、模块与 ansible-doc](../rhce/03-adhoc-modules-docs.md)（`kubectl explain` ≈ `ansible-doc`） · [RHCSA-01 基础工具](../rhcsa/01-essential-tools.md)

## 1. 这个知识点在网络中的位置

CKA 不考你背 YAML，考的是在限定时间里**正确地**改集群。高手的套路是：命令式生成骨架 → vim 小改 → `apply` → 验证。
这一篇是所有后续笔记的「操作系统」：K6～K15 里的每个命令都建立在这里的别名、`--dry-run`、`explain`、`jsonpath` 之上。
你熟悉的 `docker ps / logs / exec` 在这里都有直接对应，迁移成本很低。

## 2. 核心概念

### 2.1 命令式 vs 声明式

| 方式 | 例子 | 什么时候用 |
|---|---|---|
| 命令式命令 | `kubectl create deploy web --image=nginx --replicas=3` | 考试首选：快 |
| 命令式 + 生成 YAML | `... --dry-run=client -o yaml > web.yaml` | 需要加探针、资源、卷等命令行没有的字段时 |
| 声明式 | `kubectl apply -f web.yaml` | 修改、可重复执行 |
| 直接编辑 | `kubectl edit deploy web` | 改一两个字段；**不可改的字段**（如 Pod 的大部分 spec）会被拒绝，改用 `replace --force` |

### 2.2 docker CLI ↔ kubectl

| docker | kubectl |
|---|---|
| `docker ps` | `kubectl get pods`（`-A` 全部命名空间，`-o wide` 看节点和 IP） |
| `docker run -d --name web nginx` | `kubectl run web --image=nginx` |
| `docker logs -f web` | `kubectl logs -f web`（多容器加 `-c 容器名`，上一次崩溃加 `-p`） |
| `docker exec -it web sh` | `kubectl exec -it web -- sh` |
| `docker inspect web` | `kubectl describe pod web` / `kubectl get pod web -o yaml` |
| `docker compose up -d` | `kubectl apply -f dir/` 或 `kubectl apply -k dir/` |
| `docker compose down` | `kubectl delete -f dir/` |
| `docker port` / `-p 8080:80` | `kubectl port-forward pod/web 8080:80`、`kubectl expose` |

### 2.3 kubeconfig 与 context

`~/.kube/config` 里有三类条目：`clusters`（apiserver 地址 + CA）、`users`（证书或 token）、`contexts`（cluster + user + 默认 namespace 的组合）。
考试有多个集群，**每题先切 context**（或按题目要求 ssh 到指定主机）。

## 3. 必会操作

```bash
# —— 开考第一分钟（若环境未预配置）——
alias k=kubectl
source <(kubectl completion bash); complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"      # 用法：k run tmp --image=nginx $do > pod.yaml
export now="--force --grace-period=0"     # 用法：k delete pod web $now（立即删除）
# ~/.vimrc：set expandtab tabstop=2 shiftwidth=2 （YAML 只能用空格）

# —— context / namespace ——
k config get-contexts                     # 列出所有 context，* 是当前
k config use-context <ctx>                # 切集群（每题第一步）
k config set-context --current --namespace=dev   # 切默认命名空间

# —— 生成 YAML 骨架 ——
k run nginx --image=nginx --port=80 --labels=app=web $do > pod.yaml
k create deploy web --image=nginx:1.27 --replicas=3 $do > deploy.yaml
k create job pi --image=perl -- perl -Mbignum=bpi -wle 'print bpi(100)'
k create cronjob bk --image=busybox --schedule="*/5 * * * *" -- date
k expose deploy web --port=80 --target-port=80 --type=NodePort $do
k create cm app-cfg --from-literal=MODE=prod --from-file=nginx.conf
k create secret generic db --from-literal=PASSWORD='s3cr3t'
k create sa app-sa; k create ns dev

# —— 修改 ——
k set image deploy/web nginx=nginx:1.28    # 触发滚动更新
k scale deploy web --replicas=5
k label node node1 disk=ssd                # 去掉标签：k label node node1 disk-
k annotate deploy web owner=ops
k replace --force -f pod.yaml              # 删除并重建（改 Pod 不可变字段时）

# —— 查询与输出 ——
k explain deploy.spec.strategy             # 查字段含义（不用开浏览器）
k explain pod.spec --recursive | grep -i toleration
k get pods -l app=web --show-labels
k get pods -A --field-selector status.phase!=Running
k get pods --sort-by=.metadata.creationTimestamp
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
k get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IMAGE:.spec.containers[0].image
k get events -A --sort-by=.lastTimestamp | tail
k diff -f deploy.yaml                      # apply 前看会改什么

# —— 临时调试 Pod ——
k run tmp --image=busybox:1.36 --rm -it --restart=Never -- sh   # 用完自动删除
k run curl --image=curlimages/curl --rm -it --restart=Never -- curl -s web.dev.svc
```

### jsonpath 速记

| 需求 | 表达式 |
|---|---|
| 所有 Pod 名 | `{.items[*].metadata.name}` |
| 每行一个 | `{range .items[*]}{.metadata.name}{"\n"}{end}` |
| 带过滤 | `{.items[?(@.spec.nodeName=="node1")].metadata.name}` |
| 取 Secret 并解码 | `k get secret db -o jsonpath='{.data.PASSWORD}' \| base64 -d` |

## 4. 考试坑点

- **忘记切 context / namespace** 是第一大丢分点。题目说 namespace `prod`，就在命令里显式写 `-n prod`。
- `kubectl run` 只建 Pod；要 Deployment 用 `kubectl create deploy`。
- `--dry-run=client` 生成的 YAML 里有 `creationTimestamp: null`、`status: {}`，不影响 apply，可以不删。
- YAML 缩进只能用空格，从网页复制粘贴后在 vim 里用 `:set paste` 防止自动缩进错乱。
- 要求「输出写入文件」的题：确认路径、确认只包含题目要的内容（别把表头也写进去，必要时 `--no-headers`）。
- `kubectl edit` 保存失败时会把修改存到 `/tmp/kubectl-edit-xxxx.yaml`，用它 `replace --force -f` 即可。
- `-o yaml` 导出的对象带 `resourceVersion`、`uid`、`status`，复制成新对象时要删掉。

## 5. 动手练习

- [labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md)：每道题都尽量先用命令式完成，再看能否更快
- 每日 15 分钟热身：不看笔记写出 Pod、Deployment、Service、ConfigMap、Secret、Job、CronJob 的生成命令
- 计时练：用 jsonpath 输出所有节点名和 InternalIP 到文件，目标 2 分钟内

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 考场在线路径 |
|---|---|---|
| **kubectl 速查表（考场最常用页）** | [reference/kubectl/quick-reference.md](../../references/cka/kubernetes-docs/reference/kubectl/quick-reference.md) | kubernetes.io/docs/reference/kubectl/quick-reference/ |
| JSONPath 语法 | [reference/kubectl/jsonpath.md](../../references/cka/kubernetes-docs/reference/kubectl/jsonpath.md) | kubernetes.io/docs/reference/kubectl/jsonpath/ |
| docker 命令对照 | [reference/kubectl/docker-cli-to-kubectl.md](../../references/cka/kubernetes-docs/reference/kubectl/docker-cli-to-kubectl.md) | kubernetes.io/docs/reference/kubectl/docker-cli-to-kubectl/ |
| kubectl 约定（生成器、dry-run） | [reference/kubectl/conventions.md](../../references/cka/kubernetes-docs/reference/kubectl/conventions.md) | kubernetes.io/docs/reference/kubectl/conventions/ |
| 命令式管理对象 | [tasks/manage-kubernetes-objects/imperative-command.md](../../references/cka/kubernetes-docs/tasks/manage-kubernetes-objects/imperative-command.md) | kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-command/ |
| 声明式管理对象 | [tasks/manage-kubernetes-objects/declarative-config.md](../../references/cka/kubernetes-docs/tasks/manage-kubernetes-objects/declarative-config.md) | kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/ |
| kubeconfig 多集群 | [tasks/access-application-cluster/configure-access-multiple-clusters.md](../../references/cka/kubernetes-docs/tasks/access-application-cluster/configure-access-multiple-clusters.md) | kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/ |
| 各子命令参考 | [reference/kubectl/generated/](../../references/cka/kubernetes-docs/reference/kubectl/generated/) | kubernetes.io/docs/reference/kubectl/generated/ |

考场里 `kubectl <子命令> -h` 的 Examples 段落往往比翻网页更快。

## 7. 自测清单

- [ ] 30 秒内配好 `alias k`、补全、`$do` 变量和 vim 缩进
- [ ] 不看文档写出 7 种常见对象的生成命令
- [ ] 能用 jsonpath 和 custom-columns 各输出一份「Pod 名 + 所在节点」
- [ ] 能在多个 context 之间切换，并知道当前默认 namespace 是什么
- [ ] 改 Pod 的 image 以外字段失败时，知道用 `replace --force`
