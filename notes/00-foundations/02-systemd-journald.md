# F2 systemd 与 journald：服务、target、日志

> **轨道**：[公共基础](README.md) ｜ **考纲**：EX200「Operate running systems」「Deploy, configure, and maintain systems」的底座；CKA「Troubleshooting」 ｜ **建议用时**：4 h ｜ **难度**：★★☆
>
> **前置**：[F1 Ubuntu → RHEL 对照](01-ubuntu-to-rhel.md)
> **后续**：[RHCSA-03 运行中的系统](../rhcsa/03-operate-running-systems.md)
> **关联**（跨轨道）：[RHCSA-06 计划任务与引导](../rhcsa/06-software-scheduling-boot.md) · [RHCE-11 用 Ansible 管服务](../rhce/11-automate-rhcsa-tasks.md) · [CKA-03 kubeadm 装集群](../cka/03-kubeadm-install.md) · [CKA-15 排错](../cka/15-troubleshooting.md)

## 1. 这个知识点在网络中的位置

Ubuntu 和 RHEL 都用 systemd，所以这是你最容易迁移的一块。它在三门考试里反复出现：

- **RHCSA**：服务开机自启、切换默认 target、救援模式改 root 密码、让 journal 持久化。
- **RHCE**：`ansible.builtin.systemd_service` / `service` 模块本质上就是在帮你执行 `systemctl`。
- **CKA**：`kubelet` 和 `containerd` 都是 systemd 服务。节点 NotReady 时，第一反应就是 `systemctl status kubelet` + `journalctl -u kubelet`。

## 2. 核心概念

| 概念 | 说明 | 类比 |
|---|---|---|
| unit | systemd 管理的对象：`.service`、`.socket`、`.timer`、`.mount`、`.target`、`.path` | docker compose 里的一个 service 定义 |
| unit 文件位置 | 软件包自带：`/usr/lib/systemd/system/`；管理员自定义（优先级更高）：`/etc/systemd/system/`；运行时：`/run/systemd/system/` | `/etc` 覆盖 `/usr` |
| drop-in | `/etc/systemd/system/<unit>.d/*.conf`，只覆盖部分字段，`systemctl edit <unit>` 自动生成 | compose 的 `docker-compose.override.yml` |
| enable vs start | `start` = 现在启动；`enable` = 开机自启（建软链接）；`enable --now` = 两者都做 | `restart: always` 大致等于 enable |
| mask | 把 unit 链接到 `/dev/null`，任何方式都无法启动 | 比 disable 更彻底 |
| target | 一组 unit 的集合，相当于旧的 runlevel：`multi-user.target`（命令行）、`graphical.target`（图形）、`rescue.target`、`emergency.target` | runlevel 3 / 5 / 1 |
| journald | systemd 自带的二进制日志，`journalctl` 查询；默认可能**不持久化**，重启后旧日志丢失 | `docker logs` 但面向整个系统 |
| rsyslog | 传统文本日志，写 `/var/log/messages`、`/var/log/secure` 等 | Ubuntu 的 `/var/log/syslog` |

## 3. 必会操作

```bash
# —— 服务管理 ——
systemctl status sshd                 # 状态、最近日志、是否 enabled
sudo systemctl enable --now httpd     # 立即启动 + 开机自启（考试最常用的一条）
sudo systemctl restart chronyd        # 重启服务（配置改完后）
sudo systemctl reload sshd            # 重载配置不中断连接（服务支持时）
systemctl is-enabled httpd            # 只看是否开机自启
systemctl is-active httpd             # 只看是否运行
systemctl list-units --type=service --state=failed   # 列出失败的服务
sudo systemctl mask --now nftables    # 禁止某服务被任何方式启动（如与 firewalld 冲突时）

# —— unit 文件 ——
systemctl cat sshd                    # 查看最终生效的 unit 内容（含 drop-in）
sudo systemctl edit httpd             # 创建 drop-in 覆盖（自动 daemon-reload）
sudo systemctl daemon-reload          # 手工改了 unit 文件后必须执行

# —— target / 启动级别 ——
systemctl get-default                 # 当前默认 target
sudo systemctl set-default multi-user.target   # 改默认启动到命令行（重启后生效）
sudo systemctl isolate multi-user.target       # 立即切换（不改默认值）

# —— journalctl ——
journalctl -u kubelet -f              # 跟踪某个服务的日志（CKA 排错必用）
journalctl -u sshd --since "10 min ago"        # 时间范围
journalctl -p err -b                  # 本次启动以来所有 error 级别以上日志
journalctl -b -1                      # 上一次启动的日志（需要持久化 journal）
journalctl --list-boots               # 列出保留了哪些启动记录：只有 0 说明没持久化
journalctl -k                         # 只看内核日志（等同 dmesg）
logger -p user.notice "hello from logger"      # 往日志里写一条，验证日志链路

# —— 让 journal 持久化（RHCSA 常考）——
sudo mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\n' | sudo tee /etc/systemd/journald.conf.d/persistent.conf
sudo systemctl restart systemd-journald
ls /var/log/journal/                  # 出现以 machine-id 命名的目录即成功
```

> 也可以直接编辑 `/etc/systemd/journald.conf` 把 `#Storage=auto` 改为 `Storage=persistent`。
> 用 drop-in 目录的好处是：不管发行版把默认配置放在 `/etc` 还是 `/usr/lib`，都能生效。
> `Storage=auto` 的含义是「`/var/log/journal` 存在就持久化」，所以只 `mkdir /var/log/journal` 再重启 journald 也行。

### 一个最小的自定义 service（理解 unit 文件结构）

```ini
# /etc/systemd/system/hello.service
[Unit]
Description=Hello demo
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/bash -c 'while true; do echo hello; sleep 10; done'
Restart=on-failure

[Install]
WantedBy=multi-user.target      # enable 时挂到哪个 target 下
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now hello
journalctl -u hello -n 5        # 看最后 5 行输出
```

## 4. 考试坑点

- **只 start 不 enable**：重启后服务没起来 = 题目零分。养成 `enable --now` 的习惯，做完用 `systemctl is-enabled` 复查。
- **改了 unit 文件不 `daemon-reload`**：systemd 还在用旧定义。
- **`isolate` 和 `set-default` 搞混**：题目说「系统默认启动到图形/命令行界面」要用 `set-default`。
- **journal 持久化后没重启 journald**：`/var/log/journal` 建了但没生效。用 `journalctl --list-boots` 验证。
- **CKA：kubelet 起不来先看日志再动手**。常见原因：swap 没关、证书/kubeconfig 路径错、容器运行时 socket 不通、`/var/lib/kubelet/config.yaml` 写错。顺序：`systemctl status kubelet` → `journalctl -u kubelet -n 50` → 改配置 → `systemctl restart kubelet`。
- **静态 Pod 不是 systemd 服务**：kube-apiserver 等控制面组件在 kubeadm 集群里是 kubelet 读取 `/etc/kubernetes/manifests/` 拉起的静态 Pod，不要找 `kube-apiserver.service`（见 [CKA-01](../cka/01-architecture.md)）。

## 5. 动手练习

- [`labs/rhcsa/practice-set-1.md`](../../labs/rhcsa/practice-set-1.md)：服务自启、默认 target、journal 持久化相关题
- [`labs/cka/practice-set-1.md`](../../labs/cka/practice-set-1.md)：节点 NotReady / kubelet 故障排查题
- 自己动手：写上面的 `hello.service`，故意把 `ExecStart` 路径写错，用 `systemctl status` + `journalctl` 找出原因。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- RHEL 在线：[Managing systemd](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/managing_systemd/index)（RHEL 10 中 systemd 章节可能并入其他手册，链接以官网为准）
- RHEL 在线：[Configuring basic system settings（RHEL 9，含 systemd 与日志章节）](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/configuring_basic_system_settings/index)
- 离线（CKA 视角）：[`references/cka/kubernetes-docs/tasks/debug/debug-cluster/_index.md`](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/_index.md)（集群排错，含查看 kubelet 日志）
- 离线（CKA 视角）：[`references/cka/kubernetes-docs/tasks/debug/debug-cluster/kubectl-node-debug.md`](../../references/cka/kubernetes-docs/tasks/debug/debug-cluster/kubectl-node-debug.md)
- 离线（CKA 视角）：[`references/cka/kubernetes-docs/concepts/architecture/cgroups.md`](../../references/cka/kubernetes-docs/concepts/architecture/cgroups.md)（kubelet 和容器运行时都要用 systemd cgroup 驱动）

考场查法：

```bash
man systemctl             # 全部子命令
man systemd.unit          # [Unit] / [Install] 段的字段
man systemd.service       # [Service] 段：Type、ExecStart、Restart……
man journalctl            # 过滤参数
man journald.conf         # Storage= 等配置项
man systemd.special       # 各种 target 的含义
```

## 7. 自测清单

- [ ] 能说出 `/usr/lib/systemd/system` 和 `/etc/systemd/system` 的区别与优先级
- [ ] 2 分钟内让一台机器的 journal 持久化，并用 `journalctl --list-boots` 证明
- [ ] 能把默认 target 改成 `multi-user.target`，并解释它和 `isolate` 的区别
- [ ] 不看笔记写出一个带 `[Install]` 段、能 `enable` 的 service 文件
- [ ] 能用 `journalctl -u kubelet` 定位一个 kubelet 启动失败的原因（CKA 场景）
