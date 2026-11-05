# 知识网络（notes/）

每篇笔记 = 知识网络里的一个节点。每篇顶部都写明：

- **前置**：学它之前最好先掌握的节点
- **后续**：学完之后自然衔接的节点
- **关联**：其他轨道里会复用这个知识的节点（比如 RHCSA 的 LVM ↔ RHCE 的存储自动化 ↔ CKA 的持久卷）
- **官方文档**：链接到 [`references/`](../references/) 里对应的离线官方文档

> 推荐用 [Obsidian](https://obsidian.md/) 打开整个仓库：笔记之间是标准 Markdown 相对链接，Obsidian 的「关系图谱」可以直接看到整张网络；在 GitHub 网页上点链接也能跳转。
> 新写笔记请复制 [`_template.md`](_template.md)。

## 全局地图

```mermaid
flowchart LR
  subgraph F[00 · 公共基础]
    F1[Ubuntu → RHEL]
    F2[systemd/journald]
    F3[网络基础]
    F4[YAML]
    F5[Docker → Podman → K8s]
    F6[TLS/PKI]
    F7[vim/tmux 考场效率]
  end
  subgraph S[RHCSA · EX200]
    S1[基础工具] --> S2[Shell 脚本]
    S1 --> S3[运行中的系统]
    S1 --> S4[本地存储/LVM] --> S5[文件系统/NFS/autofs]
    S3 --> S6[软件/计划任务/时间]
    S1 --> S7[网络 nmcli]
    S1 --> S8[用户与 sudo]
    S7 --> S9[防火墙/SELinux]
    S8 --> S9
    S9 --> S10[Podman 容器]
  end
  subgraph E[RHCE · EX294]
    E1[Ansible 架构] --> E2[Inventory/配置] --> E3[Ad-hoc/模块/ansible-doc] --> E4[Playbook]
    E4 --> E5[变量与 facts] --> E6[循环/条件/错误处理] --> E7[Jinja2 模板]
    E6 --> E8[Roles] --> E9[Collections/navigator]
    E4 --> E10[Vault]
    E8 --> E11[自动化 RHCSA 任务]
    E9 --> E12[RHEL System Roles]
  end
  subgraph K[CKA]
    K1[集群架构] --> K2[kubectl 效率]
    K1 --> K3[kubeadm 装集群] --> K4[升级/etcd 备份] --> K5[高可用控制平面]
    K2 --> K6[RBAC]
    K2 --> K9[工作负载] --> K10[调度]
    K3 --> K8[CNI/CSI/CRI/CRD]
    K9 --> K7[Helm/Kustomize]
    K9 --> K11[Service/DNS] --> K12[NetworkPolicy]
    K11 --> K13[Ingress/Gateway API]
    K9 --> K14[存储]
    K4 --> K15[排错 30%]
    K11 --> K15
    K14 --> K15
  end
  F1 --> S1
  F2 --> S3
  F3 --> S7
  F4 --> E4
  F4 --> K2
  F5 --> S10 --> K1
  F6 --> K4
  F6 --> K6
  F7 --> S1
  S9 --> E11
  S4 --> E11
  S6 --> E11
  S8 --> E11
  S4 --> K14
  S7 --> K11
  S3 --> K15
  S6 --> K3
  E7 -.类比.-> K7
  E8 -.类比.-> K7
```

## 节点清单

### 00 · 公共基础（[`00-foundations/`](00-foundations/)）

| # | 笔记 | 一句话 |
|---|---|---|
| F1 | [Ubuntu → RHEL 对照](00-foundations/01-ubuntu-to-rhel.md) | apt→dnf、ufw→firewalld、AppArmor→SELinux、netplan→NetworkManager |
| F2 | [systemd 与 journald](00-foundations/02-systemd-journald.md) | 服务、target、日志——RHCSA 和 CKA 排错的共同底座 |
| F3 | [网络基础](00-foundations/03-networking-basics.md) | IP/掩码/路由/DNS/端口，后面 nmcli 和 K8s Service 都靠它 |
| F4 | [YAML 语法](00-foundations/04-yaml.md) | Ansible 和 Kubernetes 的共同语言 |
| F5 | [Docker → Podman → Kubernetes](00-foundations/05-containers-docker-to-k8s.md) | 把你的 docker/compose 经验迁移过来 |
| F6 | [TLS / PKI 基础](00-foundations/06-tls-pki-basics.md) | 证书、CA、kubeconfig 里的那串 base64 到底是什么 |
| F7 | [vim / tmux / 考场效率](00-foundations/07-vim-tmux-exam-efficiency.md) | 三门都是上机实操考试，手速就是分数 |

### RHCSA · EX200（[`rhcsa/`](rhcsa/README.md)）

| # | 笔记 | 考纲领域 |
|---|---|---|
| S1 | [基础工具](rhcsa/01-essential-tools.md) | Understand and use essential tools |
| S2 | [Shell 脚本](rhcsa/02-shell-scripting.md) | Create simple shell scripts |
| S3 | [运行中的系统](rhcsa/03-operate-running-systems.md) | Operate running systems |
| S4 | [本地存储与 LVM](rhcsa/04-local-storage-lvm.md) | Configure local storage |
| S5 | [文件系统 / NFS / autofs](rhcsa/05-file-systems-nfs-autofs.md) | Create and configure file systems |
| S6 | [软件、计划任务、时间、引导](rhcsa/06-software-scheduling-boot.md) | Deploy, configure, and maintain systems |
| S7 | [网络配置 nmcli](rhcsa/07-networking-nmcli.md) | Manage basic networking |
| S8 | [用户、组与 sudo](rhcsa/08-users-groups-sudo.md) | Manage users and groups |
| S9 | [防火墙与 SELinux](rhcsa/09-security-firewalld-selinux.md) | Manage security |
| S10 | [Podman 容器](rhcsa/10-containers-podman.md) | Manage containers（RHEL 9 版考纲；RHEL 10 版可能已移除，仍是通往 CKA 的桥） |

### RHCE · EX294（[`rhce/`](rhce/README.md)）

| # | 笔记 | 考纲领域 |
|---|---|---|
| E1 | [Ansible 架构与安装](rhce/01-ansible-architecture.md) | Understand core components / Install and configure a control node |
| E2 | [Inventory 与 ansible.cfg](rhce/02-inventory-and-config.md) | Control node / Managed nodes |
| E3 | [Ad-hoc、模块与 ansible-doc](rhce/03-adhoc-modules-docs.md) | Use provided documentation |
| E4 | [Playbook 基础](rhce/04-playbooks.md) | Create Ansible plays and playbooks |
| E5 | [变量与 facts](rhce/05-variables-facts.md) | Variables / Facts |
| E6 | [循环、条件、handler 与错误处理](rhce/06-loops-conditions-errors.md) | Loops / Conditionals / Handling task failure |
| E7 | [Jinja2 模板](rhce/07-jinja2-templates.md) | Manage content |
| E8 | [Roles](rhce/08-roles.md) | Use roles |
| E9 | [Collections 与 ansible-navigator](rhce/09-collections-navigator.md) | Content Collections / Automation content navigator |
| E10 | [Ansible Vault](rhce/10-vault.md) | Use Ansible Vault |
| E11 | [用 Ansible 自动化 RHCSA 任务](rhce/11-automate-rhcsa-tasks.md) | Automate standard RHCSA tasks（**连接 RHCSA 全部节点的枢纽**） |
| E12 | [RHEL System Roles](rhce/12-rhel-system-roles.md) | Use RHEL system roles / collections |

### CKA（[`cka/`](cka/README.md)）

| # | 笔记 | 考纲领域（权重） |
|---|---|---|
| K1 | [集群架构与组件](cka/01-architecture.md) | Cluster Architecture (25%) |
| K2 | [kubectl 高效操作](cka/02-kubectl-efficiency.md) | 全部领域的基本功 |
| K3 | [用 kubeadm 搭建集群](cka/03-kubeadm-install.md) | Cluster Architecture (25%) |
| K4 | [集群生命周期：升级与 etcd 备份恢复](cka/04-cluster-lifecycle.md) | Cluster Architecture (25%) |
| K5 | [高可用控制平面](cka/05-ha-control-plane.md) | Cluster Architecture (25%) |
| K6 | [RBAC 与 ServiceAccount](cka/06-rbac.md) | Cluster Architecture (25%) |
| K7 | [Helm 与 Kustomize](cka/07-helm-kustomize.md) | Cluster Architecture (25%) |
| K8 | [扩展接口：CNI/CSI/CRI、CRD 与 Operator](cka/08-extension-interfaces-crd.md) | Cluster Architecture (25%) |
| K9 | [工作负载：Deployment、ConfigMap/Secret、HPA](cka/09-workloads.md) | Workloads & Scheduling (15%) |
| K10 | [调度：资源、亲和性、污点](cka/10-scheduling.md) | Workloads & Scheduling (15%) |
| K11 | [Service 与 CoreDNS](cka/11-services-dns.md) | Services & Networking (20%) |
| K12 | [NetworkPolicy](cka/12-network-policy.md) | Services & Networking (20%) |
| K13 | [Ingress 与 Gateway API](cka/13-ingress-gateway-api.md) | Services & Networking (20%) |
| K14 | [存储：PV/PVC/StorageClass](cka/14-storage.md) | Storage (10%) |
| K15 | [排错](cka/15-troubleshooting.md) | Troubleshooting (30%) |
