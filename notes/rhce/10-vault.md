# RHCE-10 Ansible Vault

> **轨道**：[RHCE](README.md) ｜ **考纲**：EX294「Use Ansible Vault in playbooks to protect sensitive data」 ｜ **建议用时**：2 h ｜ **难度**：★☆☆
>
> **前置**：[RHCE-04 Playbook 基础](04-playbooks.md)
> **后续**：[RHCE-11 用 Ansible 自动化 RHCSA 任务](11-automate-rhcsa-tasks.md)
> **关联**（跨轨道）：[CKA-09 工作负载](../cka/09-workloads.md)（K8s Secret 默认只是 base64，**不是加密**；Vault 是真加密 AES256） · [RHCSA-08 用户、组与 sudo](../rhcsa/08-users-groups-sudo.md)（加密的通常就是用户密码）

## 1. 这个知识点在网络中的位置

playbook 会进 git 仓库，密码不能明文写在里面。Vault 用 AES256 加密整个变量文件（或单个字符串），运行时提供密码解密。
考试典型题：「创建加密文件 `secrets.yml`，包含变量 `pw_dev`、`pw_ops`，vault 密码为 X，并把密码放到 `secret.txt`」，后续创建用户的题会用到它。

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| 加密文件 | 整个 YAML 文件被加密，开头是 `$ANSIBLE_VAULT;1.1;AES256` |
| 加密字符串 | `encrypt_string` 生成 `!vault |` 块，嵌在普通 YAML 里 |
| 密码来源 | `--ask-vault-pass` 交互输入；`--vault-password-file <文件>`；或 `ansible.cfg` 的 `vault_password_file` |
| vault-id | 多个密码时用 `--vault-id label@source` 区分（考试一般用不到） |
| 自动解密 | `vars_files`、`group_vars/`、`host_vars/`、`include_vars` 中的加密文件运行时都会被自动解密 |

## 3. 必会操作

```bash
# 准备密码文件（权限收紧）
echo 'Vault-Lab-2026' > /home/student/ansible/secret.txt
chmod 600 /home/student/ansible/secret.txt

# 创建加密文件（会打开编辑器）
ansible-vault create secrets.yml --vault-password-file secret.txt
#   在编辑器中写入：
#   pw_dev: Dev@Pass1
#   pw_ops: Ops@Pass1

# 其他常用操作
ansible-vault view secrets.yml --vault-password-file secret.txt     # 查看
ansible-vault edit secrets.yml --vault-password-file secret.txt     # 编辑
ansible-vault encrypt plain.yml --vault-password-file secret.txt   # 加密已有文件
ansible-vault decrypt secrets.yml --vault-password-file secret.txt  # 解密成明文（慎用）
ansible-vault rekey secrets.yml                                     # 改密码（交互输入新旧密码）
ansible-vault rekey secrets.yml --vault-password-file old.txt --new-vault-password-file new.txt

# 加密单个字符串
ansible-vault encrypt_string --vault-password-file secret.txt 'S3cret!' --name 'db_password'

# 运行使用了加密文件的 playbook
ansible-playbook users.yml --vault-password-file secret.txt
ansible-playbook users.yml --ask-vault-pass
ansible-navigator run users.yml -m stdout --pae false --ask-vault-pass   # navigator 交互输入
```

`EDITOR=vim` 可以指定编辑器；在 vim 里 `:wq` 保存后文件自动加密。

### 在 playbook 中使用

```yaml
---
- name: Create users with vaulted passwords
  hosts: dev
  vars_files:
    - secrets.yml                         # 加密文件，运行时自动解密
  tasks:
    - name: Create developer account
      ansible.builtin.user:
        name: devops
        password: "{{ pw_dev | password_hash('sha512') }}"
        update_password: on_create       # 已存在的用户不再改密码，保证幂等
      no_log: true                       # 不在输出里打印敏感信息
```

### ansible.cfg 里固定密码文件（省去每次输入）

```ini
[defaults]
vault_password_file = /home/student/ansible/secret.txt
```

## 4. 考试坑点

- **密码文件里的换行**：`echo` 写入会有结尾换行，Ansible 读取时会去掉首尾空白，一般没问题；但**不要多写空格**。
- **题目要求 vault 密码文件路径**：判分可能会用这个文件去解密你的 vault 文件，路径和内容都要对。
- **不要 `decrypt` 后忘了加密回去**：判分检查文件是否为加密状态（开头 `$ANSIBLE_VAULT`）。
- **`ansible-vault create` 时文件已存在会报错**，用 `edit`。
- **变量名拼错**：vault 文件内容看不见，最好 `ansible-vault view` 再确认一次。
- **user 模块的 password 参数要的是哈希**，必须 `| password_hash('sha512')`，直接写明文会导致无法登录。
- `no_log: true` 是好习惯，但排错时先去掉。

## 5. 动手练习

- [practice-set-1 · E10 节](../../labs/rhce/practice-set-1.md#e10)

## 6. 官方文档（本仓库离线版 + 考场可用的查法）

- 离线：
  - [vault_guide/vault.rst](../../references/rhce/ansible-docs/vault_guide/vault.rst)
  - [vault_guide/vault_encrypting_content.rst](../../references/rhce/ansible-docs/vault_guide/vault_encrypting_content.rst)（`create`/`encrypt`/`encrypt_string`）
  - [vault_guide/vault_managing_passwords.rst](../../references/rhce/ansible-docs/vault_guide/vault_managing_passwords.rst)
  - [vault_guide/vault_using_encrypted_content.rst](../../references/rhce/ansible-docs/vault_guide/vault_using_encrypted_content.rst)
- 考场：
  - `ansible-vault --help`、`ansible-vault create --help`
  - `ansible-config list | grep -i -A5 vault_password` 查配置键名
  - `ansible-doc -t filter ansible.builtin.password_hash`（或 `ansible-doc ansible.builtin.user` 的 EXAMPLES 里有 password 示例）

## 7. 自测清单

- [ ] 能用密码文件创建、查看、编辑、重设密码（rekey）一个 vault 文件
- [ ] 能用 `encrypt_string` 生成一个内嵌加密变量
- [ ] 能在 playbook 中引用 vault 变量并正确哈希成用户密码
- [ ] 知道 `ansible-playbook` 和 `ansible-navigator` 分别怎样提供 vault 密码
- [ ] 能解释 Vault 加密与 K8s Secret base64 的区别
