# F4 YAML 语法：Ansible 与 Kubernetes 的共同语言

> **轨道**：[公共基础](README.md) ｜ **考纲**：EX294 全部 playbook 题、CKA 全部 manifest 题的前提 ｜ **建议用时**：2 h ｜ **难度**：★☆☆
>
> **前置**：[F7 vim / tmux / 考场效率](07-vim-tmux-exam-efficiency.md)（先把编辑器配好再写 YAML）
> **后续**：[RHCE-04 Playbook 基础](../rhce/04-playbooks.md) · [CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md)
> **关联**（跨轨道）：[RHCE-02 Inventory 与 ansible.cfg](../rhce/02-inventory-and-config.md) · [CKA-09 工作负载](../cka/09-workloads.md) · [F5 Docker → Podman → K8s](05-containers-docker-to-k8s.md)

## 1. 这个知识点在网络中的位置

你写过 `docker-compose.yml`，所以 YAML 并不陌生。但 RHCE 和 CKA 都是**考场手写 YAML**：
一个缩进错误就让整题失败，而且报错信息往往指向错误的行。
这一篇只讲「写对」所需的最小语法 + 两门考试各自的坑，后面 playbook、manifest 都在此之上展开。

## 2. 核心概念

### 2.1 三种基本结构

```yaml
# 标量（scalar）
name: web            # 字符串
replicas: 3          # 整数
enabled: true        # 布尔

# 映射（map / dict）：key: value，子级用空格缩进
metadata:
  name: web
  labels:
    app: web

# 序列（list）：每项以 "- " 开头
ports:
  - 80
  - 443

# 列表里套映射（最常见：K8s containers、Ansible tasks）
containers:
  - name: nginx
    image: nginx:1.27
  - name: sidecar
    image: busybox
```

### 2.2 必须记住的规则

| 规则 | 说明 |
|---|---|
| 只能用空格缩进 | **Tab 是非法字符**；同级元素缩进必须完全一致（习惯 2 空格） |
| `key: value` 冒号后要有空格 | `key:value` 会被当成一个字符串 |
| `#` 开始注释 | 行内注释前要有空格 |
| `---` 分隔多个文档 | 一个文件里放多个 K8s 对象就用它 |
| 多行字符串 `\|` | 保留换行（写配置文件内容、脚本） |
| 多行字符串 `>` | 折叠成一行（长句子） |
| `\|-` / `>-` | 去掉末尾换行 |
| 行内写法 | `[a, b]` 是列表，`{k: v}` 是映射，与 JSON 兼容 |

### 2.3 「看起来像字符串，其实不是」——类型陷阱

| 写法 | 被解析为 | 该怎么写 |
|---|---|---|
| `value: yes` / `on` / `no` | 布尔值（YAML 1.1 规则，Ansible 和 K8s 的解析器都受影响） | 要字符串就加引号 `"yes"` |
| `value: 8080`（K8s env 的 value） | 整数 → `kubectl apply` 报 cannot unmarshal number into ... string | `value: "8080"` |
| `mode: 644`（Ansible file 模块） | 十进制 644，权限全乱 | `mode: '0644'` |
| `msg: {{ var }}`（Ansible） | YAML 把 `{` 当成映射开头，语法错误 | `msg: "{{ var }}"`，以 `{{` 开头的值必须加引号 |
| `time: 12:30` | 某些解析器当成六十进制数 | `"12:30"` |
| `password: abc: def` | 第二个冒号引起歧义 | 加引号 |

## 3. 必会操作

```bash
# 校验 YAML 是否能被解析（RHEL 自带 python3；考场若无 PyYAML 就用下面两条）
python3 -c 'import sys, yaml; list(yaml.safe_load_all(open(sys.argv[1]))); print("OK")' file.yaml

# Ansible：只做语法检查，不执行
ansible-playbook --syntax-check site.yml
ansible-navigator run site.yml --syntax-check -m stdout

# Kubernetes：客户端/服务端干跑，能发现字段名拼错
kubectl apply -f pod.yaml --dry-run=client
kubectl apply -f pod.yaml --dry-run=server     # 会经过 API Server 校验，更严格

# 不确定字段层级时，让工具告诉你
kubectl explain pod.spec.containers.env        # 字段说明和类型
kubectl explain deploy.spec --recursive | less # 整棵字段树

# 生成 YAML 骨架，而不是从零手写（CKA 核心技巧，见 CKA-02）
kubectl create deployment web --image=nginx --replicas=3 --dry-run=client -o yaml > web.yaml

# 在 vim 里查看有没有 Tab 和行尾空格
# :set list      （Tab 显示为 ^I 或 >-）
```

### 同一个应用，三种 YAML 对照

```yaml
# docker-compose.yml（你熟悉的）
services:
  web:
    image: nginx:1.27
    ports: ["8080:80"]
```

```yaml
# Ansible playbook（RHCE）：顶层是一个 play 的列表
- name: Deploy web
  hosts: webservers
  become: true
  tasks:
    - name: Install httpd
      ansible.builtin.dnf:
        name: httpd
        state: present
```

```yaml
# Kubernetes manifest（CKA）：apiVersion/kind/metadata/spec 四件套
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels: {app: web}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
```

## 4. 考试坑点

- **从浏览器粘贴 YAML 出现阶梯式缩进**：vim 的自动缩进叠加了。用 `:set paste` 粘贴，粘完 `:set nopaste`（详见 [F7](07-vim-tmux-exam-efficiency.md)）。
- **列表项和父级对齐方式混用**：`containers:` 下面的 `- name` 缩进 0 或 2 空格都合法，但**同一文件里要统一**，别和兄弟字段错位。
- **Ansible 模块参数缩进不够**：参数要比模块名再缩进一级，否则会被当成 task 级关键字报错。
- **K8s 的 `selector.matchLabels` 和 `template.metadata.labels` 不一致**：YAML 合法但 Deployment 创建失败。
- **报错行号不可信**：YAML 报错通常指向「发现问题的地方」，真正的错误往往在上面几行。

## 5. 动手练习

- [`labs/rhce/practice-set-1.md`](../../labs/rhce/practice-set-1.md)：从 playbook 题开始，故意制造一个缩进错误，用 `--syntax-check` 找出来
- [`labs/cka/practice-set-1.md`](../../labs/cka/practice-set-1.md)：用 `--dry-run=client -o yaml` 生成骨架再修改
- 自测：把你实验室里任意一个 `docker-compose.yml` 手工改写成 Deployment + Service 两个 K8s 对象（参考 [F5](05-containers-docker-to-k8s.md)）。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：[`references/rhce/ansible-docs/reference_appendices/YAMLSyntax.rst`](../../references/rhce/ansible-docs/reference_appendices/YAMLSyntax.rst)（Ansible 官方 YAML 语法 + Gotchas 一节必读）
- 离线：[`references/rhce/ansible-docs/getting_started/yaml/`](../../references/rhce/ansible-docs/getting_started/yaml/)（inventory / playbook 的 YAML 示例）
- 离线：[`references/cka/kubernetes-docs/concepts/overview/working-with-objects/_index.md`](../../references/cka/kubernetes-docs/concepts/overview/working-with-objects/_index.md)（K8s 对象的 YAML 结构：apiVersion/kind/metadata/spec）
- 离线：[`references/cka/kubernetes-docs/concepts/overview/working-with-objects/object-management.md`](../../references/cka/kubernetes-docs/concepts/overview/working-with-objects/object-management.md)（命令式 vs 声明式管理）

考场查法：

```bash
ansible-doc ansible.builtin.file        # 看 EXAMPLES 段，直接抄正确的 YAML 写法
kubectl explain <资源>.<字段>           # K8s 字段层级
```

## 7. 自测清单

- [ ] 能解释 `|`、`>`、`|-` 的区别，并各举一个使用场景
- [ ] 能列出至少 4 个「需要加引号」的情况
- [ ] 不看笔记手写一个包含 `containers` 列表、`env` 列表、`ports` 列表的 Pod YAML，`--dry-run=client` 一次通过
- [ ] 能把一个 compose 文件翻译成 Ansible 任务或 K8s manifest
- [ ] 知道 `ansible-playbook --syntax-check` 和 `kubectl apply --dry-run=server` 分别能发现什么错误
