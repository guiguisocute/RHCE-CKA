# RHCSA-02 Shell 脚本：条件、循环、参数与命令输出

> **轨道**：[RHCSA](README.md) ｜ **考纲**：EX200「Create simple shell scripts」 ｜ **建议用时**：5 h ｜ **难度**：★★☆
>
> **前置**：[S1 基础工具](01-essential-tools.md)
> **后续**：[RHCE-11 用 Ansible 自动化 RHCSA 任务](../rhce/11-automate-rhcsa-tasks.md)（EX294 要求「读懂简单 shell 脚本并改写成 playbook」）
> **关联**（跨轨道）：[RHCE-04 Playbook 基础](../rhce/04-playbooks.md) · [RHCE-06 循环、条件与错误处理](../rhce/06-loops-conditions-errors.md)（概念一一对应）

## 1. 这个知识点在网络中的位置

RHCSA 只考「简单脚本」：条件判断、循环、处理参数、处理命令输出。不需要写复杂程序，但要**一次写对、能执行、权限正确**。

它在网络中的作用：

- RHCE 里的 `when` / `loop` / `register` 就是 shell 里 `if` / `for` / `$(...)` 的声明式版本；
- EX294（RHEL 9 版考纲）明确有一条「Be able to analyze simple shell scripts and convert them to playbooks」；
- CKA 里 `for` 循环 + `kubectl` 也常用来批量排查。

## 2. 核心概念

| 概念 | 写法 | 说明 |
|---|---|---|
| Shebang | `#!/bin/bash` | 第一行，指定解释器 |
| 位置参数 | `$0 $1 $2 ... $# $@ "$*"` | 脚本名、第 n 个参数、参数个数、全部参数 |
| 退出码 | `$?`、`exit 0/1` | 0=成功，非 0=失败；题目常要求「参数错误时以 1 退出」 |
| 命令替换 | `$(cmd)` | 把命令输出放进变量；比反引号更推荐 |
| 测试 | `[ ... ]` / `test` / `[[ ... ]]` | `-f` 文件存在 `-d` 目录 `-z` 空串 `-eq -ne -gt -lt` 数字比较 `=` `!=` 字符串 |
| 条件 | `if ...; then ...; elif ...; else ...; fi` | 也可 `cmd && echo ok || echo fail` |
| 循环 | `for x in ...; do ...; done`、`while read line; do ...; done < file` | 处理文件逐行用 `while read` |
| case | `case "$1" in start) ...;; stop) ...;; *) ...;; esac` | 多分支 |
| 算术 | `$(( a + b ))` | 整数运算 |

## 3. 必会操作

```bash
#!/bin/bash
# 例 1：参数检查 + 条件判断
# 用法：./checkuser.sh <用户名>
if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>" >&2      # 提示写到标准错误
    exit 1
fi

if id "$1" &>/dev/null; then
    echo "$1 exists, uid=$(id -u "$1")"  # 命令替换
else
    echo "$1 not found"
    exit 2
fi
```

```bash
#!/bin/bash
# 例 2：for 循环处理命令行参数 / 文件列表
for f in "$@"; do
    if [ -f "$f" ]; then
        echo "$f: $(wc -l < "$f") lines"
    elif [ -d "$f" ]; then
        echo "$f is a directory"
    else
        echo "$f does not exist"
    fi
done
```

```bash
#!/bin/bash
# 例 3：while read 逐行处理文件——批量建用户
# users.txt 每行一个用户名
while read -r user; do
    [ -z "$user" ] && continue            # 跳过空行
    useradd "$user" && echo "redhat" | passwd --stdin "$user"
done < /root/users.txt
```

```bash
#!/bin/bash
# 例 4：处理命令输出——找出 /etc 下大于 10k 的 .conf 文件并记录
out=/root/bigconf.txt
: > "$out"                                # 清空输出文件
for f in $(find /etc -name '*.conf' -size +10k 2>/dev/null); do
    echo "$f $(stat -c %s "$f")" >> "$out"
done
echo "found $(wc -l < "$out") files"
```

```bash
# 让脚本能直接执行
chmod +x /usr/local/bin/checkuser.sh      # 放到 PATH 里的目录，题目常要求「任何用户都能直接运行」
bash -n script.sh                         # 只检查语法不执行
bash -x script.sh arg1                    # 逐行跟踪，调试神器
```

> `passwd --stdin` 是 RHEL 系特有的（Ubuntu 的 passwd 没有这个选项，Ubuntu 上常用 `chpasswd`）。RHEL 上两者都可用：`echo 'alice:redhat' | chpasswd`。

## 4. 考试坑点

- **忘记 `chmod +x`**、忘记写 shebang、脚本放错路径——评分脚本直接执行失败。
- **变量不加引号**：`[ $1 = abc ]` 在 `$1` 为空时报错；写成 `[ "$1" = abc ]`。
- **`[` 两侧必须有空格**：`[ -f "$f" ]`，不是 `[-f "$f"]`。
- **数字比较用 `-eq`，字符串比较用 `=`**；`==` 只在 `[[ ]]` 里推荐使用。
- **题目要求的输出格式/退出码要精确**：例如「无参数时输出 Usage 到 stderr 并 exit 1」。
- Windows 编辑器的 `\r\n` 换行会导致 `/bin/bash^M: bad interpreter`——考场里都用 vim，一般不会遇到，但自己练习时要注意。

## 5. 动手练习

- [练习题集 · S2 Shell 脚本](../../labs/rhcsa/practice-set-1.md#s2)
- 进阶：把例 3 改写成 Ansible playbook（`ansible.builtin.user` + `loop`），见 [RHCE-11](../rhce/11-automate-rhcsa-tasks.md)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 红帽文档里没有单独的 bash 教程，考场全靠 `man bash`：
  - `/CONDITIONAL EXPRESSIONS`：所有 `-f -d -z -eq ...` 测试运算符
  - `/Compound Commands`：`if`、`for`、`while`、`case` 语法
  - `/Special Parameters`：`$# $@ $? $$`
  - `/Parameter Expansion`：`${var:-default}`、`${var#prefix}` 等
- `man test`：`[ ]` 的独立手册，比 `man bash` 短得多
- `help if`、`help for`、`help read`：bash 内建命令的简明帮助（考场可用）

## 7. 自测清单

- [ ] 能在 5 分钟内写出「检查参数个数，不对就打印用法并 exit 1」的脚本骨架
- [ ] 能用 `while read` 逐行处理文件
- [ ] 能用 `$(...)` 把命令输出赋给变量并在条件里使用
- [ ] 知道 `$@` 和 `$*` 加引号时的区别
- [ ] 能用 `bash -x` 定位脚本错误
- [ ] 能把一个 10 行的建用户脚本讲成 Ansible 的 `user` + `loop`（为 RHCE 铺路）
