# LeetCode 题解（go/leetcode/）

刷题计划见 [`labs/go/leetcode-plan.md`](../../labs/go/leetcode-plan.md)，Go 刷题写法汇总见 [G15 用 Go 刷 LeetCode](../../notes/go/15-leetcode-in-go.md)。

## 目录约定

```text
go/leetcode/
├── 0001-two-sum/              # 题号补足 4 位 + 题目 slug
│   ├── solution.go            # package p0001：解法 + 思路与复杂度注释
│   └── solution_test.go       # 表驱动测试，至少包含题目示例和边界用例
└── 0146-lru-cache/
    ├── solution.go
    └── solution_test.go
```

- **一题一个 package**，package 名是 `p` 加 4 位题号（`p0001`、`p0146`）。不同题里的同名函数（比如都叫 `Constructor`）不会冲突。
- 函数签名和 LeetCode 网页上的保持一致（通常是小写开头的未导出函数），这样写完可以直接粘过去提交。
- 链表和二叉树题：LeetCode 已经定义了 `ListNode` / `TreeNode`，本地要在同一个目录下建 `types.go` 自己定义，提交时不要带上它。
- 设计题（`Constructor` + 方法）：提交时复制类型定义、`Constructor` 和全部方法。
- [`0001-two-sum/`](0001-two-sum/) 是完整示范：哈希表解法、思路与复杂度注释、9 个表驱动用例和一个基准测试。

## 工作流

在仓库根目录生成骨架（题目信息从 [`leetcode-problems.tsv`](../../labs/go/leetcode-problems.tsv) 里查）：

```bash
./scripts/new-leetcode.sh 146
```

计划外的题，手动指定 slug 和标题：

```bash
./scripts/new-leetcode.sh 2000 --slug reverse-prefix-of-word --title "Reverse Prefix of Word" --title-zh "反转单词前缀" --difficulty Easy
```

然后：

1. 打开生成的 `solution.go`，从网页复制函数签名，写解法。
2. 打开 `solution_test.go`，删掉 `t.Skip(...)`，把题目示例和自己想到的边界情况写成用例。
3. 跑测试，全部通过后再去网页提交：

```bash
cd go && go test ./leetcode/0146-lru-cache/ -v
```

4. 提交通过后，在 [`leetcode-plan.md`](../../labs/go/leetcode-plan.md) 里把这题的 `- [ ]` 改成 `- [x]`。

## 常用命令

所有题一起测：

```bash
cd go && go test ./leetcode/...
```

只跑某个用例（`-run` 接正则，子测试名里的空格会变成下划线）：

```bash
cd go && go test ./leetcode/0001-two-sum/ -run 'TestTwoSum/示例_1' -v
```

并发题（如 1114）加上数据竞争检测：

```bash
cd go && go test -race ./leetcode/1114-print-in-order/
```

基准测试，比较两种解法的速度和内存分配：

```bash
cd go && go test -run '^$' -bench . -benchmem ./leetcode/0001-two-sum/
```

提交前格式化和静态检查：

```bash
cd go && gofmt -l . && go vet ./...
```
