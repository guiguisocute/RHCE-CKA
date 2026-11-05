# F7 vim / tmux / 考场效率：手速就是分数

> **轨道**：[公共基础](README.md) ｜ **考纲**：不单列，但 EX200 / EX294 / CKA 都是限时上机实操 ｜ **建议用时**：2 h 配置 + 每天 10 分钟刻意练习 ｜ **难度**：★☆☆
>
> **前置**：无（可以和 [F1](01-ubuntu-to-rhel.md) 同时开始）
> **后续**：[RHCSA-01 基础工具](../rhcsa/01-essential-tools.md)
> **关联**（跨轨道）：[F4 YAML 语法](04-yaml.md) · [CKA-02 kubectl 高效操作](../cka/02-kubectl-efficiency.md) · [RHCE-03 ansible-doc](../rhce/03-adhoc-modules-docs.md) · [RHCE-04 Playbook 基础](../rhce/04-playbooks.md)

## 1. 这个知识点在网络中的位置

三门考试都没有选择题，全是在终端里限时完成任务：RHCSA/RHCE 约 3~4 小时，CKA 2 小时 15~20 题左右（以官方为准）。
会做但做不完是最常见的失败原因。vim 写 YAML、bash 补全、kubectl 别名这些「肌肉记忆」要**从第一天就开始练**，而不是考前突击。

## 2. 核心概念

- **少打字**：补全（Tab）、别名、历史搜索、生成模板（`--dry-run=client -o yaml`、`ansible-doc` 的 EXAMPLES）。
- **不写错**：vim 配好 2 空格缩进、显示 Tab；每次改完立刻验证（`--syntax-check`、`--dry-run`、`mount -a`）。
- **不迷路**：CKA 每题开头确认 context/主机；红帽考试每题确认在哪台机器上操作。
- **会取舍**：先做有把握的，卡住超过预算时间就标记跳过。

## 3. 必会操作

### 3.1 `~/.vimrc`（考场第一件事：先写这几行，约 30 秒）

```vim
" 最小可用版本（考场手敲这 3 行就够）
set expandtab tabstop=2 shiftwidth=2
set autoindent number
syntax on

" 完整版（自己的实验环境用）
set nocompatible
filetype plugin indent on
set softtabstop=2
set ruler                         " 右下角显示行列号，对齐缩进时有用
set cursorcolumn                  " 竖线标出光标所在列，YAML 对齐神器（嫌晃可去掉）
set list listchars=tab:>-,trail:~ " 把 Tab 显示成 >-、行尾空格显示成 ~
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
```

> RHEL 上 `vi` 可能是精简版 vim-minimal，读的是同一个 `~/.vimrc`；需要完整功能就 `dnf install vim-enhanced` 后用 `vim`。

### 3.2 `:set paste` 的正确用法（重要）

- 从浏览器（CKA 的 kubernetes.io 文档）复制 YAML 粘进 vim，如果出现**阶梯式越来越深的缩进**，说明自动缩进在叠加。
- 解决：`:set paste` → `i` 进入插入模式粘贴 → `Esc` → **`:set nopaste`**。
- **坑**：`paste` 模式会临时关闭 `expandtab`、`autoindent` 等选项。忘了关掉就继续手打，按 Tab 会插入真正的 Tab 字符，YAML 直接报错。所以粘完立刻 `:set nopaste`。
- 较新的 vim + 终端支持 bracketed paste，会自动处理；若粘贴正常就不用管它。

### 3.3 写 YAML 最常用的 vim 操作

```text
V 上下移动 >       选中多行整体右移一级（< 左移，. 重复）
Ctrl-v 选列 I# Esc  块选择后在每行行首插入 #（批量注释）
yy / dd / p        复制 / 剪切 / 粘贴一行；5yy 复制 5 行
u / Ctrl-r         撤销 / 重做
:%s/old/new/g      全文替换
/关键词  n  N      搜索、下一个、上一个
:42                跳到第 42 行（配合报错行号）
gg / G             文件头 / 文件尾
ci"                修改引号里的内容
:w  :wq  :q!       保存 / 保存退出 / 不保存退出
```

### 3.4 bash 效率

```bash
sudo dnf install -y bash-completion   # RHEL 实验机先装；装完重新登录才生效
# Tab 补全：命令、文件、systemctl 服务名、nmcli 参数、firewall-cmd 参数都能补
# Ctrl-r：反向搜索历史命令（比上下箭头快得多）
# Ctrl-a / Ctrl-e：跳到行首 / 行尾；Alt-.：插入上一条命令的最后一个参数
history | grep nmcli                  # 找回之前敲过的长命令
```

### 3.5 kubectl 别名与补全（CKA 环境通常已预配 `k` 别名，以考生手册为准）

```bash
source <(kubectl completion bash)                       # 当前 shell 开启补全
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc   # 让别名 k 也能补全
echo 'export do="--dry-run=client -o yaml"' >> ~/.bashrc       # k run web --image=nginx $do > web.yaml
echo 'export now="--force --grace-period 0"' >> ~/.bashrc      # k delete pod web $now（立刻删除）
source ~/.bashrc
```

### 3.6 Ansible 速查习惯（RHCE）

```bash
ansible-doc -l | grep -i firewall    # 找模块名
ansible-doc -s ansible.posix.firewalld   # 只看参数骨架（snippet），可直接粘进 playbook
ansible-doc ansible.builtin.user     # 翻到最后的 EXAMPLES 段抄写法
```

### 3.7 tmux 基本键位（前缀键默认 `Ctrl-b`）

| 操作 | 按键 |
|---|---|
| 新建会话 / 重新连接 | `tmux new -s exam` / `tmux attach -t exam` |
| 左右分屏 / 上下分屏 | `Ctrl-b %` / `Ctrl-b "` |
| 在窗格间移动 | `Ctrl-b 方向键` |
| 当前窗格最大化/还原 | `Ctrl-b z` |
| 新窗口 / 下一个 / 上一个 | `Ctrl-b c` / `Ctrl-b n` / `Ctrl-b p` |
| 滚动查看历史输出 | `Ctrl-b [`，方向键/PgUp 滚动，`q` 退出 |
| 断开会话（后台继续运行） | `Ctrl-b d` |

典型用法：左边 `vim deploy.yaml`，右边 `kubectl get pods -w` 或 `journalctl -f`。考场是否提供 tmux 以实际环境为准；没有也不影响，多开终端标签即可。

## 4. 考试坑点

- **在错误的机器 / context 上答题**：CKA 每题开头会给出切换 context 或 ssh 到指定主机的命令，**先执行再做题**；红帽考试注意题目要求在哪台主机（如 serverA / serverB）上操作。
- **粘贴模式没关**：见 3.2。
- **时间分配**：开考先浏览全部题目，按「分值高 + 有把握」排序；单题卡住超过预算（RHCSA 约 10 分钟、CKA 约 7~8 分钟）就标记跳过。
- **红帽考试：留时间重启验证**。做完存储、网络、引导相关题后主动重启一次，确认系统能正常启动、配置都还在（`/etc/fstab` 写错会导致无法启动，必须留时间修复）。
- **别依赖网上搜索**：红帽考场只有 man / `/usr/share/doc` / `ansible-doc`，平时就要用它们查。

## 5. 动手练习

- 把上面的 `~/.vimrc` 和 bash 配置写进你所有的实验机（可以放进 [`labs/rhce/00-lab-setup.md`](../../labs/rhce/00-lab-setup.md) 里的 Ansible 初始化 playbook，一举两得）。
- 计时练习：用 vim 从零手写一个 30 行的 Deployment YAML，目标 3 分钟内 `--dry-run=client` 一次通过。
- 练习题集：[`labs/rhcsa/practice-set-1.md`](../../labs/rhcsa/practice-set-1.md) · [`labs/rhce/practice-set-1.md`](../../labs/rhce/practice-set-1.md) · [`labs/cka/practice-set-1.md`](../../labs/cka/practice-set-1.md)（每套都计时完成）。

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：[`references/cka/kubernetes-docs/reference/kubectl/quick-reference.md`](../../references/cka/kubernetes-docs/reference/kubectl/quick-reference.md)（kubectl 速查表，开头就是补全与别名配置；考场可在 kubernetes.io 打开同一页）
- 离线：[`references/cka/kubernetes-docs/tasks/tools/included/optional-kubectl-configs-bash-linux.md`](../../references/cka/kubernetes-docs/tasks/tools/included/optional-kubectl-configs-bash-linux.md)（bash 补全的官方配置方法）
- 离线：[`references/rhce/ansible-docs/command_guide/cheatsheet.rst`](../../references/rhce/ansible-docs/command_guide/cheatsheet.rst)（Ansible 命令速查）
- 离线：[`references/rhce/ansible-docs/command_guide/command_line_tools.rst`](../../references/rhce/ansible-docs/command_guide/command_line_tools.rst)（ansible-doc 等命令行工具）

考场查法：

```bash
vimtutor              # 30 分钟 vim 官方交互教程（vim-enhanced 包自带），零基础先跑一遍
man tmux              # KEY BINDINGS 一节
help set              # bash 内建命令帮助
```

## 7. 自测清单

- [ ] 能在 30 秒内凭记忆写好最小 `~/.vimrc`
- [ ] 能用 `V` + `>` 批量调整 YAML 缩进，用 `Ctrl-v` + `I` 批量注释
- [ ] 知道 `:set paste` 会关闭 `expandtab`，粘完会立刻 `:set nopaste`
- [ ] 配好 `k` 别名 + 补全，`k get po -n kube-` 按 Tab 能补全命名空间
- [ ] 能用 `ansible-doc -s` 在 1 分钟内拿到任意模块的参数骨架
- [ ] 至少完成过一次全程计时的模拟练习，并记录每题用时
