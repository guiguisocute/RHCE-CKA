# CKA 轨道索引：Certified Kubernetes Administrator

> **上级**：[知识网络总览](../README.md) ｜ **考纲**：[CKA_Curriculum_v1.37.pdf](../../references/cka/CKA_Curriculum_v1.37.pdf)（CNCF 官方，2026-11 抓取） ｜ **实验**：[labs/cka](../../labs/cka/00-lab-setup.md)

## 1. 考试简介

| 项目 | 内容（以 [LF 官网](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) 与考生手册为准） |
|---|---|
| 主办 | Linux Foundation（LF）与 CNCF |
| 形式 | **2 小时上机实操**，在线远程监考（PSI 安全浏览器 + 远程桌面），每题在指定集群/主机上动手完成 |
| 考纲版本 | v1.37（考纲大版本号与 Kubernetes 小版本同步，例如 v1.37 ↔ Kubernetes 1.37） |
| 可用文档 | 考场浏览器只能打开官方允许的站点：kubernetes.io/docs、kubernetes.io/blog 等。Helm、Gateway API 文档是否允许以[考生须知](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad)为准 |
| 附带权益 | 购买考试通常含 **killer.sh 模拟考 2 次** + **一次免费重考**（以购买页为准） |
| 证书有效期 | 以官网为准（近年为 2 年） |
| 及格线 | 以官网为准（长期为 66%） |

### 五大领域与权重

| 领域 | 权重 | 对应笔记 |
|---|---|---|
| Cluster Architecture, Installation & Configuration | **25%** | K1、K3～K8 |
| Workloads & Scheduling | 15% | K9、K10 |
| Services & Networking | 20% | K11～K13 |
| Storage | 10% | K14 |
| Troubleshooting | **30%** | K15（以及所有笔记里的「排错」部分） |

> 排错占 30%，是最大的一块，而排错 = Linux 基本功（systemd、日志、网络、证书）+ K8s 对象理解。这正是先学 RHCSA 的回报。

## 2. 考纲逐条映射（v1.37 PDF 原文 → 笔记）

| 领域 | 考纲条目（原文） | 主笔记 | 辅助笔记 |
|---|---|---|---|
| Cluster Architecture | Manage role based access control (RBAC) | [K6 RBAC](06-rbac.md) | [F6 TLS/PKI](../00-foundations/06-tls-pki-basics.md) |
| Cluster Architecture | Prepare underlying infrastructure for installing a Kubernetes cluster | [K3 kubeadm 装集群](03-kubeadm-install.md) | [实验环境](../../labs/cka/00-lab-setup.md)、[RHCSA-06](../rhcsa/06-software-scheduling-boot.md) |
| Cluster Architecture | Create and manage Kubernetes clusters using kubeadm | [K3 kubeadm 装集群](03-kubeadm-install.md) | [K1 架构](01-architecture.md) |
| Cluster Architecture | Manage the lifecycle of Kubernetes clusters | [K4 升级/etcd 备份](04-cluster-lifecycle.md) | [K3](03-kubeadm-install.md) |
| Cluster Architecture | Implement and configure a highly-available control plane | [K5 高可用控制平面](05-ha-control-plane.md) | [K4](04-cluster-lifecycle.md) |
| Cluster Architecture | Use Helm and Kustomize to install cluster components | [K7 Helm/Kustomize](07-helm-kustomize.md) | [K8](08-extension-interfaces-crd.md) |
| Cluster Architecture | Understand extension interfaces (CNI, CSI, CRI, etc.) | [K8 扩展接口](08-extension-interfaces-crd.md) | [K1](01-architecture.md)、[K14](14-storage.md) |
| Cluster Architecture | Understand CRDs, install and configure operators | [K8 扩展接口](08-extension-interfaces-crd.md) | [K7](07-helm-kustomize.md) |
| Workloads & Scheduling | Understand application deployments and how to perform rolling update and rollbacks | [K9 工作负载](09-workloads.md) | [K2](02-kubectl-efficiency.md) |
| Workloads & Scheduling | Use ConfigMaps and Secrets to configure applications | [K9 工作负载](09-workloads.md) | — |
| Workloads & Scheduling | Configure workload autoscaling | [K9 工作负载](09-workloads.md) | [K15 资源监控](15-troubleshooting.md) |
| Workloads & Scheduling | Understand the primitives used to create robust, self-healing, application deployments | [K9 工作负载](09-workloads.md) | [K10](10-scheduling.md) |
| Workloads & Scheduling | Configure Pod admission and scheduling (limits, node affinity, etc.) | [K10 调度](10-scheduling.md) | — |
| Services & Networking | Understand connectivity between Pods | [K11 Service/DNS](11-services-dns.md) | [K8 CNI](08-extension-interfaces-crd.md)、[F3 网络基础](../00-foundations/03-networking-basics.md) |
| Services & Networking | Define and enforce Network Policies | [K12 NetworkPolicy](12-network-policy.md) | — |
| Services & Networking | Use ClusterIP, NodePort, LoadBalancer service types and endpoints | [K11 Service/DNS](11-services-dns.md) | — |
| Services & Networking | Use the Gateway API to manage Ingress traffic | [K13 Ingress/Gateway](13-ingress-gateway-api.md) | [K8 CRD](08-extension-interfaces-crd.md) |
| Services & Networking | Know how to use Ingress controllers and Ingress resources | [K13 Ingress/Gateway](13-ingress-gateway-api.md) | [K7 Helm](07-helm-kustomize.md) |
| Services & Networking | Understand and use CoreDNS | [K11 Service/DNS](11-services-dns.md) | — |
| Storage | Implement storage classes and dynamic volume provisioning | [K14 存储](14-storage.md) | [K8 CSI](08-extension-interfaces-crd.md) |
| Storage | Configure volume types, access modes and reclaim policies | [K14 存储](14-storage.md) | — |
| Storage | Manage persistent volumes and persistent volume claims | [K14 存储](14-storage.md) | [RHCSA-04 LVM](../rhcsa/04-local-storage-lvm.md) |
| Troubleshooting | Troubleshoot clusters and nodes | [K15 排错](15-troubleshooting.md) | [K1](01-architecture.md)、[F2 systemd](../00-foundations/02-systemd-journald.md) |
| Troubleshooting | Troubleshoot cluster components | [K15 排错](15-troubleshooting.md) | [K1](01-architecture.md)、[K4](04-cluster-lifecycle.md) |
| Troubleshooting | Monitor cluster and application resource usage | [K15 排错](15-troubleshooting.md) | [K9 HPA](09-workloads.md) |
| Troubleshooting | Manage and evaluate container output streams | [K15 排错](15-troubleshooting.md) | [K2](02-kubectl-efficiency.md) |
| Troubleshooting | Troubleshoot services and networking | [K15 排错](15-troubleshooting.md) | [K11](11-services-dns.md)、[K12](12-network-policy.md) |

## 3. 学习顺序与建议用时（约 6～8 周，每周 10～12 h）

| 周 | 笔记 | 目标 |
|---|---|---|
| 第 1 周 | [K1 架构](01-architecture.md) → [K2 kubectl](02-kubectl-efficiency.md) | 用 kind/minikube 起一个集群，`kubectl` 命令式 + `--dry-run=client -o yaml` 生成 YAML 形成肌肉记忆 |
| 第 2 周 | [K9 工作负载](09-workloads.md) → [K10 调度](10-scheduling.md) | 能 3 分钟内写出带探针、资源限制、ConfigMap 的 Deployment |
| 第 3 周 | [K11 Service/DNS](11-services-dns.md) → [K12 NetworkPolicy](12-network-policy.md) → [K13 Ingress/Gateway](13-ingress-gateway-api.md) | 切到 kubeadm 集群（需要支持 NetworkPolicy 的 CNI） |
| 第 4 周 | [K14 存储](14-storage.md) → [K6 RBAC](06-rbac.md) | 能用 CSR 给新用户签证书并绑定权限 |
| 第 5 周 | [K3 kubeadm](03-kubeadm-install.md) → [K4 生命周期](04-cluster-lifecycle.md) → [K5 HA](05-ha-control-plane.md) | 亲手从零装 3 节点集群、升级一个小版本、做 etcd 备份恢复 |
| 第 6 周 | [K7 Helm/Kustomize](07-helm-kustomize.md) → [K8 扩展接口/CRD](08-extension-interfaces-crd.md) | 用 Helm 装 Ingress/Gateway 控制器、用 Operator 装组件 |
| 第 7 周 | [K15 排错](15-troubleshooting.md) | 故意弄坏集群（停 kubelet、改错静态 Pod 清单、删 CNI 配置）再修好 |
| 第 8 周 | [练习题](../../labs/cka/practice-set-1.md) → [模拟考](../../labs/cka/mock-exam.md) → killer.sh | 严格计时，2 小时内完成 |

> 编号是「知识网络里的位置」，不是学习顺序。上表的顺序是先上手用、再学装和运维——对已经会 docker/compose 的人更顺。

## 4. 和 RHCSA / RHCE 的衔接

| 你在 RHCSA/RHCE 学的 | 在 CKA 里怎么用 |
|---|---|
| [systemd/journald](../00-foundations/02-systemd-journald.md)、[运行中的系统](../rhcsa/03-operate-running-systems.md) | kubelet、containerd 都是 systemd 服务：`systemctl status kubelet`、`journalctl -u kubelet` 是节点 NotReady 时的第一反应 |
| [软件/内核/sysctl](../rhcsa/06-software-scheduling-boot.md) | 装集群前的准备：关 swap、加载内核模块、`net.ipv4.ip_forward`、软件源与版本锁定 |
| [网络 nmcli](../rhcsa/07-networking-nmcli.md)、[F3 网络基础](../00-foundations/03-networking-basics.md) | Service/ClusterIP、Pod CIDR、DNS 解析、NodePort 端口都是网络基础的延伸 |
| [防火墙/SELinux](../rhcsa/09-security-firewalld-selinux.md) | 在 RHEL 系节点上装 K8s 要放行端口、处理 SELinux |
| [LVM/存储](../rhcsa/04-local-storage-lvm.md) | PV 的 hostPath/local 卷、StorageClass 背后都是块设备和文件系统 |
| [Podman 容器](../rhcsa/10-containers-podman.md) | 镜像、容器、命名空间、cgroups → Pod、CRI、资源限制 |
| [RHCE Jinja2 模板](../rhce/07-jinja2-templates.md)、[Roles](../rhce/08-roles.md) | Helm chart 的模板与打包思路几乎一一对应（见 [K7](07-helm-kustomize.md)） |
| [F6 TLS/PKI](../00-foundations/06-tls-pki-basics.md) | kubeconfig 里的证书、`/etc/kubernetes/pki`、`kubeadm certs`、CSR 签发用户证书 |

## 5. 考场通用技巧

- 每道题开头会告诉你要用哪个 context 或要 `ssh` 到哪台主机——**先执行这条命令再做题**，做错集群等于白做。
- `alias k=kubectl` 与命令补全通常已预配置（以考生手册为准），没有就自己配：见 [K2](02-kubectl-efficiency.md)。
- 先做分值高、把握大的题；卡住超过 5 分钟就标记跳过。
- 能用命令生成 YAML 就别手写：`k create deploy web --image=nginx --dry-run=client -o yaml > web.yaml`。
- 每题做完用 `k get`/`k describe` 验证结果，`--sort-by`、`-o jsonpath` 写入文件的题要 `cat` 一下确认格式。
