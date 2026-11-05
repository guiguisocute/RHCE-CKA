# CKA-07 Helm 与 Kustomize

> **轨道**：[CKA](README.md) ｜ **考纲**：CKA「Use Helm and Kustomize to install cluster components」 ｜ **建议用时**：6 h ｜ **难度**：★★☆
>
> **前置**：[CKA-09 工作负载](09-workloads.md) · [CKA-02 kubectl 高效操作](02-kubectl-efficiency.md)
> **后续**：[CKA-08 扩展接口：CNI/CSI/CRI、CRD 与 Operator](08-extension-interfaces-crd.md) · [CKA-13 Ingress 与 Gateway API](13-ingress-gateway-api.md)（控制器通常用 Helm 安装）
> **关联**（跨轨道）：[RHCE-07 Jinja2 模板](../rhce/07-jinja2-templates.md)（模板化思想） · [RHCE-08 Roles](../rhce/08-roles.md)（打包与复用） · [RHCE-09 Collections](../rhce/09-collections-navigator.md)（仓库/分发） · [RHCE-05 变量与 facts](../rhce/05-variables-facts.md)（变量优先级 ↔ values 覆盖）

## 1. 这个知识点在网络中的位置

装 Ingress 控制器、Gateway 实现、metrics-server、各种 Operator 时，几乎没人手写几十个 YAML——要么用 **Helm**（模板 + 打包 + 版本管理），要么用 **Kustomize**（无模板的叠加补丁，`kubectl` 内置）。
考纲要求「用 Helm 和 Kustomize 安装集群组件」：会搜仓库、看默认 values、覆盖参数、安装/升级/回滚/卸载；会写一个 `kustomization.yaml` 并 `kubectl apply -k`。
如果你学过 RHCE，这一篇几乎是「换了语法的 Ansible Role」。

## 2. 核心概念

### 2.1 Helm 三个词

| 概念 | 含义 | 类比 |
|---|---|---|
| **Chart** | 一个包：`Chart.yaml` + `values.yaml` + `templates/*.yaml` | Ansible Role |
| **Repository** | 存放 chart 的 HTTP 仓库或 OCI 镜像仓库 | Ansible Galaxy / Automation Hub |
| **Release** | chart 在某个命名空间里的一次安装实例，有版本历史（存成该命名空间里的 Secret） | 对某组主机跑过一次 playbook 的结果 |

当前 Helm 文档已是 **Helm 4**（2025 年底发布）。`repo add/install/upgrade/rollback/uninstall/template` 这些日常命令与 Helm 3 基本一致；插件、post-renderer 等高级功能有变化，见 [Helm 4 Overview](../../references/cka/helm-docs/overview.md)。

### 2.2 Helm ↔ Ansible Role 对照（RHCE 学过的直接迁移）

| Helm | Ansible（RHCE） |
|---|---|
| `Chart.yaml`（名称、版本、依赖） | `meta/main.yml` |
| `values.yaml`（默认参数） | `defaults/main.yml` |
| `templates/*.yaml`，Go 模板：`{{ .Values.replicaCount }}` | `templates/*.j2`，Jinja2：`{{ replica_count }}` |
| `{{- if .Values.ingress.enabled }} ... {{- end }}` | `{% if ingress_enabled %} ... {% endif %}` |
| `{{ range .Values.hosts }}` | `{% for h in hosts %}` |
| `--set a.b=1` / `-f my-values.yaml` 覆盖 | `-e` extra vars / `group_vars` 覆盖默认值 |
| `helm template`（只渲染不安装） | `ansible-playbook --check --diff` |
| `helm repo add` + `helm install` | `ansible-galaxy install` + 在 playbook 里调用 role |
| `helm rollback` | Ansible 没有内置回滚——这是 Helm 的优势 |

### 2.3 Kustomize：不用模板的「叠加」

- 一个目录 + 一个 `kustomization.yaml`，列出 `resources`，再声明要做的变换：`namespace`、`namePrefix`、`labels`、`images`、`patches`、`configMapGenerator`/`secretGenerator`。
- **base / overlays**：`base/` 放通用清单，`overlays/dev`、`overlays/prod` 各自引用 base 并打补丁。
- 内置于 kubectl：`kubectl kustomize <dir>` 渲染，`kubectl apply -k <dir>` 应用。
- docker compose 类比：`docker-compose.yml` + `docker-compose.override.yml` 的叠加方式，就是 base + overlay 的思路。

| 选 Helm | 选 Kustomize |
|---|---|
| 安装第三方组件（官方提供 chart） | 管理自己的清单、按环境做小改动 |
| 需要版本历史和回滚 | 想要纯 YAML、无模板语言 |

## 3. 必会操作

### 3.1 Helm

```bash
helm version
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx   # 示例仓库；以题目给出的为准
helm repo update
helm repo list
helm search repo ingress-nginx --versions | head          # 查可用 chart 版本
helm show values ingress-nginx/ingress-nginx > values.yaml # 看/改默认参数（考试最常用）
helm show chart ingress-nginx/ingress-nginx

helm install my-ing ingress-nginx/ingress-nginx -n ingress --create-namespace \
  --version <chart版本> --set controller.replicaCount=2     # 或 -f values.yaml
helm list -A                                               # 所有命名空间的 release
helm status my-ing -n ingress
helm get values my-ing -n ingress                          # 看这次安装用户覆盖了哪些值
helm get manifest my-ing -n ingress | less                 # 实际下发的 YAML

helm upgrade my-ing ingress-nginx/ingress-nginx -n ingress --reuse-values --set controller.replicaCount=3
helm upgrade --install my-ing ingress-nginx/ingress-nginx -n ingress   # 不存在就装，存在就升
helm history my-ing -n ingress
helm rollback my-ing 1 -n ingress
helm uninstall my-ing -n ingress

helm template my-ing ingress-nginx/ingress-nginx -n ingress > rendered.yaml   # 只渲染
helm pull ingress-nginx/ingress-nginx --untar              # 下载 chart 源码查看
helm install demo oci://registry.example.com/charts/demo --version 1.2.3      # OCI 仓库
helm create mychart                                        # 生成 chart 骨架，对照 RHCE 的 ansible-galaxy role init
```

### 3.2 Kustomize

```bash
mkdir -p app/base app/overlays/prod
cat > app/base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
- service.yaml
EOF
cat > app/overlays/prod/kustomization.yaml <<'EOF'
resources:
- ../../base
namespace: prod
namePrefix: prod-
labels:
- pairs:
    env: prod
  includeSelectors: true
images:
- name: nginx
  newTag: "1.28"
patches:
- target:
    kind: Deployment
    name: web
  patch: |-
    - op: replace
      path: /spec/replicas
      value: 3
configMapGenerator:
- name: app-cfg
  literals:
  - MODE=prod
EOF
kubectl kustomize app/overlays/prod          # 先看渲染结果
kubectl apply -k app/overlays/prod
kubectl delete -k app/overlays/prod
```

`configMapGenerator` 生成的 ConfigMap 名字带内容哈希后缀，内容一变就换名，从而触发引用它的 Deployment 滚动更新。

## 4. 考试坑点

- Helm 的 release **属于某个命名空间**：`helm list` 默认只看当前命名空间，找不到就加 `-A`；所有命令都别忘 `-n`。
- 题目要求特定 chart 版本时用 `--version`（这是 chart 版本，不是应用版本，`helm search repo --versions` 两列都有）。
- `helm upgrade` 不带 `--reuse-values` 或 `-f` 时，之前 `--set` 的值会被重置为默认值。
- 要求「生成清单文件而不安装」→ `helm template ... > file.yaml`。
- Kustomize 中 `labels` 配合 `includeSelectors: true` 会改 selector；旧写法 `commonLabels` 已不推荐（以官方文档为准）。
- `kubectl apply -k` 指向**目录**，不是 `kustomization.yaml` 文件。
- 考场能否访问 Helm 文档以考生手册为准；`helm <子命令> --help` 永远可用。

## 5. 动手练习

- 用 Helm 安装 metrics-server（之后 [K15](15-troubleshooting.md) 的 `kubectl top` 要用），并通过 `--set` 修改参数。
- 用 Helm 安装一个 Ingress 控制器，升级修改副本数，再回滚到第 1 版。
- 把 [K9](09-workloads.md) 中写的 Deployment + Service 改造成 base + dev/prod 两个 overlay。
- [labs/cka/practice-set-1.md](../../labs/cka/practice-set-1.md) 中 Helm/Kustomize 相关题。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

| 主题 | 离线文件 | 在线路径 |
|---|---|---|
| **Kustomize 管理对象** | [tasks/manage-kubernetes-objects/kustomization.md](../../references/cka/kubernetes-docs/tasks/manage-kubernetes-objects/kustomization.md) | kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/ |
| Helm 快速开始 | [helm-docs/intro/quickstart.md](../../references/cka/helm-docs/intro/quickstart.md) | helm.sh/docs/intro/quickstart/ |
| **使用 Helm（install/upgrade/rollback/--set 语法）** | [helm-docs/intro/using_helm.mdx](../../references/cka/helm-docs/intro/using_helm.mdx) | helm.sh/docs/intro/using_helm/ |
| Helm 速查表 | [helm-docs/intro/CheatSheet.mdx](../../references/cka/helm-docs/intro/CheatSheet.mdx) | helm.sh/docs/intro/cheatsheet/ |
| Helm 命令参考 | [helm-docs/helm/](../../references/cka/helm-docs/helm/)（如 [helm_install.md](../../references/cka/helm-docs/helm/helm_install.md)） | helm.sh/docs/helm/ |
| Chart 结构 | [helm-docs/topics/charts.mdx](../../references/cka/helm-docs/topics/charts.mdx) | helm.sh/docs/topics/charts/ |
| Chart 模板指南（Go 模板） | [helm-docs/chart_template_guide/](../../references/cka/helm-docs/chart_template_guide/) | helm.sh/docs/chart_template_guide/ |
| Helm 4 变化 | [helm-docs/overview.md](../../references/cka/helm-docs/overview.md) | helm.sh/docs/overview/ |

快速搜索：`grep -rn "reuse-values" references/cka/helm-docs/helm/`。

## 7. 自测清单

- [ ] 能说清 chart / repository / release 的区别
- [ ] 能用 `helm show values` 找到某个参数并在安装时覆盖
- [ ] 能完成 install → upgrade → history → rollback → uninstall 全流程
- [ ] 能写出包含 namespace、images、patches、configMapGenerator 的 kustomization.yaml
- [ ] 能对照 Ansible Role 说出 Helm chart 各文件的作用
