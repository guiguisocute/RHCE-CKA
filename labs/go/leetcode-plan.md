# LeetCode 刷题计划：运维场景优先（Go）

> 配合 [Go 轨道](../../notes/go/README.md) 的每周穿插表。每周 2~3 道，挑的都是能对上运维场景的题：日志统计、依赖排序、限流、容量规划、网络拓扑。
>
> 题号、中英文名、链接和难度都来自 [`leetcode-problems.tsv`](leetcode-problems.tsv)（已和 doocs/leetcode 题库核对）。力扣（leetcode.cn）和 LeetCode（leetcode.com）题号一致，选一个站刷即可。

## 怎么刷

1. 生成骨架：`./scripts/new-leetcode.sh 146`，会在 [`go/leetcode/`](../../go/leetcode/README.md) 下建好 `solution.go` 和 `solution_test.go`。
2. 先在本地写解法和表驱动测试，`cd go && go test ./leetcode/0146-lru-cache/` 通过后，再把函数粘到网页上提交。
3. 卡住 30 分钟就看题解，**第二天不看题解重写一遍**。
4. 每做完一题，把下面对应的 `- [ ]` 改成 `- [x]`；错过的题记到 [错题本](../../journal/mistakes.md)。

各周的 Go 写法套路（堆、链表、并查集、BFS 模板等）汇总在 [G15 用 Go 刷 LeetCode](../../notes/go/15-leetcode-in-go.md)。

## 每周题单

<a id="w1"></a>

### W1 · 准备 · G1 环境、模块与工具链

本周 Go 知识点：[G1](../../notes/go/01-toolchain-modules.md)

- [ ] **1. 两数之和**（Two Sum） · 简单 · [力扣](https://leetcode.cn/problems/two-sum/) · [LeetCode](https://leetcode.com/problems/two-sum/)
  - 运维场景：在一批主机的资源用量里找出两台加起来正好等于某个配额。本质是「查表」，运维脚本里最常用的就是 map。
  - 练到的 Go：`map[int]int`、comma-ok 写法 `v, ok := m[k]`（[G3](../../notes/go/03-composite-types.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>一次遍历，map 存「值 → 下标」。对每个 x 先查 `target-x` 在不在 map 里，再把 x 存进去。仓库里有完整示范：`go/leetcode/0001-two-sum/`。</details>
- [ ] **1108. IP 地址无效化**（Defanging an IP Address） · 简单 · [力扣](https://leetcode.cn/problems/defanging-an-ip-address/) · [LeetCode](https://leetcode.com/problems/defanging-an-ip-address/)
  - 运维场景：告警和工单里常把 IP 写成 `1[.]1[.]1[.]1`，防止被聊天工具自动识别成链接。
  - 练到的 Go：`strings.ReplaceAll`、`strings.Builder`（[G2](../../notes/go/02-basics-errors.md)）
  - <details><summary>提示</summary>标准库一行搞定；再手写一个 `strings.Builder` 版本，体会字符串不可变、拼接要用 Builder。</details>

<a id="w2"></a>

### W2 · 准备 · G2 基础语法与错误处理

本周 Go 知识点：[G2](../../notes/go/02-basics-errors.md)

- [ ] **20. 有效的括号**（Valid Parentheses） · 简单 · [力扣](https://leetcode.cn/problems/valid-parentheses/) · [LeetCode](https://leetcode.com/problems/valid-parentheses/)
  - 运维场景：校验配置文件、JSON、模板里的括号是否配对，是写各种 lint 工具前的热身。
  - 练到的 Go：slice 当栈、`for _, r := range s` 按 rune 遍历（[G2](../../notes/go/02-basics-errors.md)、[G3](../../notes/go/03-composite-types.md)）
  - <details><summary>提示</summary>遇到左括号入栈；遇到右括号就和栈顶比对，不匹配直接返回 false。最后栈必须为空。</details>
- [ ] **14. 最长公共前缀**（Longest Common Prefix） · 简单 · [力扣](https://leetcode.cn/problems/longest-common-prefix/) · [LeetCode](https://leetcode.com/problems/longest-common-prefix/)
  - 运维场景：求一组主机名的公共前缀（`web-prod-01`、`web-prod-02` → `web-prod-`），可以用来自动生成分组名。
  - 练到的 Go：字符串下标取到的是 byte、`strings.HasPrefix`（[G2](../../notes/go/02-basics-errors.md)）
  - <details><summary>提示</summary>以第一个字符串为基准逐字符比较；或者排序后只比较第一个和最后一个。</details>
- [ ] **929. 独特的电子邮件地址**（Unique Email Addresses） · 简单 · [力扣](https://leetcode.cn/problems/unique-email-addresses/) · [LeetCode](https://leetcode.com/problems/unique-email-addresses/)
  - 运维场景：通知收件人去重：先按规则把地址规范化，再计数。和规范化日志字段是同一个套路。
  - 练到的 Go：`strings.Cut`、`strings.ReplaceAll`、`map[string]struct{}` 当集合（[G2](../../notes/go/02-basics-errors.md)、[G3](../../notes/go/03-composite-types.md)）
  - <details><summary>提示</summary>用 `strings.Cut` 按 `@` 拆开；本地名去掉 `+` 之后的部分，再删掉所有 `.`，域名保持不变。</details>

<a id="w3"></a>

### W3 · RHCSA · G3 slice、map、struct 与指针

本周 Go 知识点：[G3](../../notes/go/03-composite-types.md)

- [ ] **49. 字母异位词分组**（Group Anagrams） · 中等 · [力扣](https://leetcode.cn/problems/group-anagrams/) · [LeetCode](https://leetcode.com/problems/group-anagrams/)
  - 运维场景：把「内容相同、顺序不同」的东西归为一组，例如只是包名顺序不同的两张变更单。
  - 练到的 Go：数组可以作 map 的 key：`map[[26]int][]string`（[G3](../../notes/go/03-composite-types.md)）
  - <details><summary>提示</summary>用 26 个字母的计数数组 `[26]int` 作 key，比把字符串排序后作 key 更快。</details>
- [ ] **347. 前 K 个高频元素**（Top K Frequent Elements） · 中等 · [力扣](https://leetcode.cn/problems/top-k-frequent-elements/) · [LeetCode](https://leetcode.com/problems/top-k-frequent-elements/)
  - 运维场景：找出访问量最高的 K 个 URL，或者报错最多的 K 个错误码。
  - 练到的 Go：map 计数，再用桶排序或 `container/heap`（[G3](../../notes/go/03-composite-types.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>先计数；再按频次分桶（下标就是频次），从高往低取够 K 个。</details>
- [ ] **811. 子域名访问计数**（Subdomain Visit Count） · 中等 · [力扣](https://leetcode.cn/problems/subdomain-visit-count/) · [LeetCode](https://leetcode.com/problems/subdomain-visit-count/)
  - 运维场景：把访问日志按域名逐级汇总：`a.b.example.com` 也要计入 `b.example.com` 和 `example.com`。典型的日志聚合。
  - 练到的 Go：`strings.Fields`、`strconv.Atoi`、循环里用 `strings.IndexByte` 切子串（[G3](../../notes/go/03-composite-types.md)、[G5](../../notes/go/05-stdlib-files-text-exec.md)）
  - <details><summary>提示</summary>对每条记录，不断去掉最左边一段子域名，把次数累加进 map。</details>

<a id="w4"></a>

### W4 · RHCSA · G4 方法、接口与泛型

本周 Go 知识点：[G4](../../notes/go/04-methods-interfaces-generics.md)

- [ ] **155. 最小栈**（Min Stack） · 中等 · [力扣](https://leetcode.cn/problems/min-stack/) · [LeetCode](https://leetcode.com/problems/min-stack/)
  - 运维场景：O(1) 查询「当前最小值」，监控里的窗口最小值是同一类需求。这题顺便练习给 struct 定义方法。
  - 练到的 Go：struct + 指针接收者方法、`Constructor()` 构造函数（[G4](../../notes/go/04-methods-interfaces-generics.md)）
  - <details><summary>提示</summary>再开一个辅助栈，和主栈同步压入「到目前为止的最小值」。</details>
- [ ] **232. 用栈实现队列**（Implement Queue using Stacks） · 简单 · [力扣](https://leetcode.cn/problems/implement-queue-using-stacks/) · [LeetCode](https://leetcode.com/problems/implement-queue-using-stacks/)
  - 运维场景：用两个栈实现队列，理解消息队列的 FIFO 语义。
  - 练到的 Go：方法集、从 slice 尾部弹出（[G4](../../notes/go/04-methods-interfaces-generics.md)）
  - <details><summary>提示</summary>一个输入栈、一个输出栈。只有输出栈空了，才把输入栈整个倒过去，均摊 O(1)。</details>
- [ ] **706. 设计哈希映射**（Design HashMap） · 简单 · [力扣](https://leetcode.cn/problems/design-hashmap/) · [LeetCode](https://leetcode.com/problems/design-hashmap/)
  - 运维场景：理解 map 底层的哈希桶。排查「热点 key」一类性能问题时用得上。
  - 练到的 Go：定长数组 + 切片桶；可以先定义一个 `Map` 接口，再写两种实现来练接口（[G4](../../notes/go/04-methods-interfaces-generics.md)）
  - <details><summary>提示</summary>对 key 取模分桶，每个桶是一个 `[]pair`，put 时先找有没有同 key 再决定更新还是追加。</details>

<a id="w5"></a>

### W5 · RHCSA · G5 运维常用标准库

本周 Go 知识点：[G5](../../notes/go/05-stdlib-files-text-exec.md)

- [ ] **71. 简化路径**（Simplify Path） · 中等 · [力扣](https://leetcode.cn/problems/simplify-path/) · [LeetCode](https://leetcode.com/problems/simplify-path/)
  - 运维场景：规范化路径，处理 `..` 和 `//`。这正是 `path.Clean` 做的事；写文件类工具时还要防止路径穿越。
  - 练到的 Go：`strings.Split`、slice 当栈；写完和 `path.Clean` 的结果对照（[G5](../../notes/go/05-stdlib-files-text-exec.md)）
  - <details><summary>提示</summary>按 `/` 切分；空串和 `.` 跳过，`..` 出栈，其余入栈；最后用 `/` 拼回去。</details>
- [ ] **609. 在系统中查找重复文件**（Find Duplicate File in System） · 中等 · [力扣](https://leetcode.cn/problems/find-duplicate-file-in-system/) · [LeetCode](https://leetcode.com/problems/find-duplicate-file-in-system/)
  - 运维场景：按内容找重复文件（类似 fdupes），清理磁盘空间用。
  - 练到的 Go：`strings.Fields`、`strings.Cut`、`map[string][]string`（[G5](../../notes/go/05-stdlib-files-text-exec.md)）
  - <details><summary>提示</summary>以「文件内容」为 key 聚合完整路径，最后只保留长度大于 1 的组。做完可以延伸：用 `os.ReadDir` + `crypto/sha256` 写一个真正的查重工具。</details>
- [ ] **692. 前K个高频单词**（Top K Frequent Words） · 中等 · [力扣](https://leetcode.cn/problems/top-k-frequent-words/) · [LeetCode](https://leetcode.com/problems/top-k-frequent-words/)
  - 运维场景：统计日志里出现最多的 K 个关键词（比如 sshd 的报错类型）；频次相同按字典序，正好练自定义排序。
  - 练到的 Go：`slices.SortFunc` 多级比较、`cmp.Compare`（[G5](../../notes/go/05-stdlib-files-text-exec.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>计数后按「频次降序、单词升序」排序，取前 K 个。进阶：用大小为 K 的堆。</details>

<a id="w6"></a>

### W6 · RHCSA · G6 测试与工程化

本周 Go 知识点：[G6](../../notes/go/06-testing-tooling.md)

- [ ] **165. 比较版本号**（Compare Version Numbers） · 中等 · [力扣](https://leetcode.cn/problems/compare-version-numbers/) · [LeetCode](https://leetcode.com/problems/compare-version-numbers/)
  - 运维场景：比较软件包或内核版本号：要不要升级、kubeadm 一次只能升一个小版本，都要先比版本。
  - 练到的 Go：`strings.Split`、`strconv.Atoi`、表驱动测试（[G6](../../notes/go/06-testing-tooling.md)）
  - <details><summary>提示</summary>按 `.` 切分，逐段转成整数比较，短的那边缺的段按 0 算。测试用例至少覆盖 `1.01` vs `1.001`、`1.0` vs `1`。</details>
- [ ] **468. 验证IP地址**（Validate IP Address） · 中等 · [力扣](https://leetcode.cn/problems/validate-ip-address/) · [LeetCode](https://leetcode.com/problems/validate-ip-address/)
  - 运维场景：校验 inventory、防火墙规则里的 IPv4 / IPv6 地址。
  - 练到的 Go：先按题目规则手写；再对照 `net/netip.ParseAddr`，用表驱动测试找出两者的差异（[G6](../../notes/go/06-testing-tooling.md)、[G8](../../notes/go/08-net-http-tls.md)）
  - <details><summary>提示</summary>IPv4：4 段，每段 0~255，不能有前导零。IPv6：8 段，每段 1~4 位十六进制。注意题目不允许 `::` 简写，标准库却允许，所以不能直接用标准库交差。</details>
- [ ] **8. 字符串转换整数 (atoi)**（String to Integer (atoi)） · 中等 · [力扣](https://leetcode.cn/problems/string-to-integer-atoi/) · [LeetCode](https://leetcode.com/problems/string-to-integer-atoi/)
  - 运维场景：解析配置里的数字：前后空格、正负号、溢出都要处理。边界情况多，正好练习写一大批测试用例。
  - 练到的 Go：`math.MaxInt32`、逐字符解析、`t.Run` 子测试（[G6](../../notes/go/06-testing-tooling.md)）
  - <details><summary>提示</summary>依次处理：跳过空格 → 读符号 → 读数字。每次累加之前先判断会不会溢出。</details>

<a id="w7"></a>

### W7 · RHCSA · G5 复习

本周 Go 知识点：[G5](../../notes/go/05-stdlib-files-text-exec.md)

- [ ] **56. 合并区间**（Merge Intervals） · 中等 · [力扣](https://leetcode.cn/problems/merge-intervals/) · [LeetCode](https://leetcode.com/problems/merge-intervals/)
  - 运维场景：合并多个维护窗口或告警静默时间段，得到实际的停机时间。
  - 练到的 Go：`slices.SortFunc` 按起点排序、`[][]int`（[G3](../../notes/go/03-composite-types.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>按起点排序后，和结果里最后一段比较：有重叠就延长右端点，否则追加新的一段。</details>
- [ ] **57. 插入区间**（Insert Interval） · 中等 · [力扣](https://leetcode.cn/problems/insert-interval/) · [LeetCode](https://leetcode.com/problems/insert-interval/)
  - 运维场景：往已经排好序的变更窗口日历里插入一个新窗口，并合并冲突的部分。
  - 练到的 Go：切片追加与拼接（[G3](../../notes/go/03-composite-types.md)）
  - <details><summary>提示</summary>分三段处理：完全在新区间左边的、和新区间重叠需要合并的、完全在右边的。</details>
- [ ] **435. 无重叠区间**（Non-overlapping Intervals） · 中等 · [力扣](https://leetcode.cn/problems/non-overlapping-intervals/) · [LeetCode](https://leetcode.com/problems/non-overlapping-intervals/)
  - 运维场景：至少取消几个任务，才能让剩下的备份窗口或计划任务互不重叠。
  - 练到的 Go：贪心 + `slices.SortFunc` 按右端点排序（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>按结束时间排序，贪心保留结束最早的区间，和它重叠的都删掉。</details>

<a id="w8"></a>

### W8 · RHCSA · SELinux 周，Go 减量

- [ ] **704. 二分查找**（Binary Search） · 简单 · [力扣](https://leetcode.cn/problems/binary-search/) · [LeetCode](https://leetcode.com/problems/binary-search/)
  - 运维场景：在按时间排好序的日志里快速定位某个时间点。
  - 练到的 Go：手写二分，再和 `slices.BinarySearch` / `sort.Search` 对照（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>注意循环条件 `left <= right`，中点写成 `left + (right-left)/2`。</details>
- [ ] **278. 第一个错误的版本**（First Bad Version） · 简单 · [力扣](https://leetcode.cn/problems/first-bad-version/) · [LeetCode](https://leetcode.com/problems/first-bad-version/)
  - 运维场景：找出第一个出问题的发布版本，思路和 `git bisect` 完全一样。
  - 练到的 Go：`sort.Search`；把 `isBadVersion` 当成函数值传来传去（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>二分查找第一个返回 true 的位置。</details>

<a id="w9"></a>

### W9 · RHCSA · G7 并发：goroutine、channel、context

本周 Go 知识点：[G7](../../notes/go/07-concurrency-context.md)

- [ ] **1114. 按序打印**（Print in Order） · 简单 · [力扣](https://leetcode.cn/problems/print-in-order/) · [LeetCode](https://leetcode.com/problems/print-in-order/)
  - 运维场景：保证三个步骤按顺序执行：先建目录，再写配置，最后启动服务。
  - 练到的 Go：无缓冲 channel 做同步、`sync.WaitGroup`、`go test -race`（[G7](../../notes/go/07-concurrency-context.md)）
  - 注意：这是并发题。LeetCode 这道题可能不提供 Go 选项，以题目页面为准；不支持时就在本地用 goroutine + channel 实现，并写测试、加 `-race` 跑。
  - <details><summary>提示</summary>两个 channel：first 执行完 `close(c1)`；second 先 `<-c1` 再执行，执行完 `close(c2)`；third 先 `<-c2`。</details>
- [ ] **622. 设计循环队列**（Design Circular Queue） · 中等 · [力扣](https://leetcode.cn/problems/design-circular-queue/) · [LeetCode](https://leetcode.com/problems/design-circular-queue/)
  - 运维场景：环形缓冲区：日志采集、保存最近 N 条事件都用它。
  - 练到的 Go：struct + 定长 slice + 取模（[G4](../../notes/go/04-methods-interfaces-generics.md)、[G7](../../notes/go/07-concurrency-context.md)）
  - <details><summary>提示</summary>只需要 `head` 和 `size` 两个变量，队尾位置是 `(head+size) % cap`。</details>
- [ ] **239. 滑动窗口最大值**（Sliding Window Maximum） · 困难 · [力扣](https://leetcode.cn/problems/sliding-window-maximum/) · [LeetCode](https://leetcode.com/problems/sliding-window-maximum/)
  - 运维场景：监控里「最近 k 个采样点的最大值」，比如滑动窗口里的 CPU 峰值。
  - 练到的 Go：单调双端队列（slice 存下标）（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>队列里保持值递减；新元素进来时把比它小的都弹掉；队头下标过期就从队头弹出。</details>

<a id="w10"></a>

### W10 · EX200 考试周

暂停刷题，专心考试。考前一天可以挑一道做过的简单题热热手。

<a id="w11"></a>

### W11 · RHCE · G9 配置、模板与 CLI

本周 Go 知识点：[G9](../../notes/go/09-config-template-cli.md)

- [ ] **394. 字符串解码**（Decode String） · 中等 · [力扣](https://leetcode.cn/problems/decode-string/) · [LeetCode](https://leetcode.com/problems/decode-string/)
  - 运维场景：展开模板里的重复语法（`3[ab]` → `ababab`），理解模板引擎是怎么一层层展开的。
  - 练到的 Go：两个栈、`strings.Repeat`、`strings.Builder`（[G9](../../notes/go/09-config-template-cli.md)）
  - <details><summary>提示</summary>遇到 `[` 就把（当前字符串, 重复次数）压栈；遇到 `]` 弹栈，把当前串重复后接到之前的串后面。</details>
- [ ] **150. 逆波兰表达式求值**（Evaluate Reverse Polish Notation） · 中等 · [力扣](https://leetcode.cn/problems/evaluate-reverse-polish-notation/) · [LeetCode](https://leetcode.com/problems/evaluate-reverse-polish-notation/)
  - 运维场景：告警规则、简单表达式求值器的基础。
  - 练到的 Go：`strconv.Atoi`、`switch`、栈（[G9](../../notes/go/09-config-template-cli.md)）
  - <details><summary>提示</summary>数字入栈；遇到运算符弹出两个数，算完再压回去。除法向零截断，Go 的整数 `/` 正好就是这样。</details>
- [ ] **224. 基本计算器**（Basic Calculator） · 困难 · [力扣](https://leetcode.cn/problems/basic-calculator/) · [LeetCode](https://leetcode.com/problems/basic-calculator/)
  - 运维场景：解析配置里的算术表达式，比如资源配额写成 `2*(512+256)`。（本题只有加减和括号，属于选做的难题。）
  - 练到的 Go：栈或递归处理括号与符号（[G9](../../notes/go/09-config-template-cli.md)）
  - <details><summary>提示</summary>维护 result 和 sign；遇到 `(` 把当前 result 和 sign 压栈并清零，遇到 `)` 弹栈合并。</details>

<a id="w12"></a>

### W12 · RHCE · G9 复习

本周 Go 知识点：[G9](../../notes/go/09-config-template-cli.md)

- [ ] **146. LRU 缓存**（LRU Cache） · 中等 · [力扣](https://leetcode.cn/problems/lru-cache/) · [LeetCode](https://leetcode.com/problems/lru-cache/)
  - 运维场景：缓存淘汰策略：DNS 缓存、facts 缓存、镜像层缓存都会用到 LRU。
  - 练到的 Go：`container/list` + `map[int]*list.Element`（[G9](../../notes/go/09-config-template-cli.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>访问一个 key 就把它移到链表头；容量满了删除链表尾。</details>
- [ ] **981. 基于时间的键值存储**（Time Based Key-Value Store） · 中等 · [力扣](https://leetcode.cn/problems/time-based-key-value-store/) · [LeetCode](https://leetcode.com/problems/time-based-key-value-store/)
  - 运维场景：带时间戳的键值存储。etcd 的 MVCC（按 revision 读取历史值）就是这个思路。
  - 练到的 Go：`map[string][]pair` + `sort.Search`（[G9](../../notes/go/09-config-template-cli.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>同一个 key 的 set 时间戳是递增的，所以 get 时二分查找最后一个 ≤ timestamp 的值。</details>

<a id="w13"></a>

### W13 · RHCE · G10 SSH 远程执行与并行任务

本周 Go 知识点：[G10](../../notes/go/10-ssh-parallel-exec.md)

- [ ] **21. 合并两个有序链表**（Merge Two Sorted Lists） · 简单 · [力扣](https://leetcode.cn/problems/merge-two-sorted-lists/) · [LeetCode](https://leetcode.com/problems/merge-two-sorted-lists/)
  - 运维场景：把两台主机按时间排好序的日志合成一份。
  - 练到的 Go：链表节点指针、哨兵（dummy）节点（[G10](../../notes/go/10-ssh-parallel-exec.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>建一个 dummy 头节点，双指针每次取较小的那个接上。</details>
- [ ] **23. 合并 K 个升序链表**（Merge k Sorted Lists） · 困难 · [力扣](https://leetcode.cn/problems/merge-k-sorted-lists/) · [LeetCode](https://leetcode.com/problems/merge-k-sorted-lists/)
  - 运维场景：合并 k 台主机按时间排好序的日志，比如把 gossh 从各台机器收回来的输出按时间合并。
  - 练到的 Go：`container/heap`：实现 `heap.Interface` 的 5 个方法（[G10](../../notes/go/10-ssh-parallel-exec.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>堆里放每条链表当前的头节点，每次弹出最小的，再把它的下一个节点压进去。</details>
- [ ] **215. 数组中的第K个最大元素**（Kth Largest Element in an Array） · 中等 · [力扣](https://leetcode.cn/problems/kth-largest-element-in-an-array/) · [LeetCode](https://leetcode.com/problems/kth-largest-element-in-an-array/)
  - 运维场景：找出第 k 大的磁盘使用率或延迟，用来定告警阈值。
  - 练到的 Go：`container/heap` 小顶堆，或快速选择（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>维护一个大小为 k 的小顶堆，遍历完堆顶就是答案。</details>

<a id="w14"></a>

### W14 · RHCE · G15 用 Go 刷 LeetCode

本周 Go 知识点：[G15](../../notes/go/15-leetcode-in-go.md)

- [ ] **207. 课程表**（Course Schedule） · 中等 · [力扣](https://leetcode.cn/problems/course-schedule/) · [LeetCode](https://leetcode.com/problems/course-schedule/)
  - 运维场景：服务、Ansible role、Helm chart 之间的依赖能不能满足，也就是有没有循环依赖。
  - 练到的 Go：邻接表 `[][]int`、入度数组、slice 当队列（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>Kahn 算法：入度为 0 的先入队，出队时把邻居的入度减一；出队总数等于 n 就说明无环。</details>
- [ ] **210. 课程表 II**（Course Schedule II） · 中等 · [力扣](https://leetcode.cn/problems/course-schedule-ii/) · [LeetCode](https://leetcode.com/problems/course-schedule-ii/)
  - 运维场景：给出一个合法的启动或部署顺序，就像 systemd 的 `After=` 和 Ansible 的 role dependencies。
  - 练到的 Go：同 207，记录出队顺序（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>在 207 的基础上记录出队顺序；如果出队数不足 n，返回空切片。</details>
- [ ] **621. 任务调度器**（Task Scheduler） · 中等 · [力扣](https://leetcode.cn/problems/task-scheduler/) · [LeetCode](https://leetcode.com/problems/task-scheduler/)
  - 运维场景：同类任务之间要有冷却时间（同一台机器两次重启至少隔 n 个单位），求最短完成时间。
  - 练到的 Go：计数数组、贪心公式或堆（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>公式：`(maxCount-1)*(n+1) + 并列最多的任务种数`，再和任务总数取最大值。</details>

<a id="w15"></a>

### W15 · RHCE · G8 网络、HTTP 与 TLS

本周 Go 知识点：[G8](../../notes/go/08-net-http-tls.md)

- [ ] **3. 无重复字符的最长子串**（Longest Substring Without Repeating Characters） · 中等 · [力扣](https://leetcode.cn/problems/longest-substring-without-repeating-characters/) · [LeetCode](https://leetcode.com/problems/longest-substring-without-repeating-characters/)
  - 运维场景：滑动窗口的基础题，后面的「最近 N 秒请求数」「会话切分」都靠这个套路。
  - 练到的 Go：`map[byte]int` 记录字符最近一次出现的位置、双指针（[G8](../../notes/go/08-net-http-tls.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>右指针不断扩张；遇到重复字符，把左指针跳到它上次出现位置的后一位。</details>
- [ ] **295. 数据流的中位数**（Find Median from Data Stream） · 困难 · [力扣](https://leetcode.cn/problems/find-median-from-data-stream/) · [LeetCode](https://leetcode.com/problems/find-median-from-data-stream/)
  - 运维场景：实时计算延迟的中位数（P50），借这题理解监控系统怎么算分位数。
  - 练到的 Go：两个堆：大顶堆 + 小顶堆（`container/heap`）（[G8](../../notes/go/08-net-http-tls.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>大顶堆放较小的一半，小顶堆放较大的一半，两边数量差不超过 1。</details>
- [ ] **703. 数据流中的第 K 大元素**（Kth Largest Element in a Stream） · 简单 · [力扣](https://leetcode.cn/problems/kth-largest-element-in-a-stream/) · [LeetCode](https://leetcode.com/problems/kth-largest-element-in-a-stream/)
  - 运维场景：在持续流入的指标里维护「第 k 大」，比如 Top-K 慢请求的门槛。
  - 练到的 Go：`container/heap` 小顶堆（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>堆的大小始终保持为 k，堆顶就是答案。</details>

<a id="w16"></a>

### W16 · EX294 考试周

暂停刷题，专心考试。考前一天可以挑一道做过的简单题热热手。

<a id="w17"></a>

### W17 · CKA · G11 容器化与在 K8s 上运行 Go 服务

本周 Go 知识点：[G11](../../notes/go/11-containerize-deploy.md)

- [ ] **200. 岛屿数量**（Number of Islands） · 中等 · [力扣](https://leetcode.cn/problems/number-of-islands/) · [LeetCode](https://leetcode.com/problems/number-of-islands/)
  - 运维场景：统计网络里有几个互不连通的区域：机房分区、网段孤岛。
  - 练到的 Go：二维切片、DFS 递归或 BFS 队列（[G11](../../notes/go/11-containerize-deploy.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>遇到 '1' 计数加一，再把相连的一整片都标成 '0'。</details>
- [ ] **994. 腐烂的橘子**（Rotting Oranges） · 中等 · [力扣](https://leetcode.cn/problems/rotting-oranges/) · [LeetCode](https://leetcode.com/problems/rotting-oranges/)
  - 运维场景：故障或配置变更在集群里一圈一圈扩散，需要多久才能覆盖全部节点（多源 BFS）。
  - 练到的 Go：队列 + 按层遍历（[G11](../../notes/go/11-containerize-deploy.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>所有烂橘子同时入队，按层推进，层数就是分钟数；最后还有新鲜橘子就返回 -1。</details>
- [ ] **102. 二叉树的层序遍历**（Binary Tree Level Order Traversal） · 中等 · [力扣](https://leetcode.cn/problems/binary-tree-level-order-traversal/) · [LeetCode](https://leetcode.com/problems/binary-tree-level-order-traversal/)
  - 运维场景：按层遍历树，就像按层打印进程树（pstree）或目录树。
  - 练到的 Go：树节点指针、队列（[G11](../../notes/go/11-containerize-deploy.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>每一层开始前先记下队列长度，只处理这么多个节点。</details>

<a id="w18"></a>

### W18 · CKA · G12 client-go

本周 Go 知识点：[G12](../../notes/go/12-client-go.md)

- [ ] **380. O(1) 时间插入、删除和获取随机元素**（Insert Delete GetRandom O(1)） · 中等 · [力扣](https://leetcode.cn/problems/insert-delete-getrandom-o1/) · [LeetCode](https://leetcode.com/problems/insert-delete-getrandom-o1/)
  - 运维场景：负载均衡：从后端池里随机挑一个，并且能 O(1) 增删后端。
  - 练到的 Go：`map[int]int` + slice；删除时和末尾元素交换；`math/rand/v2`（[G12](../../notes/go/12-client-go.md)）
  - <details><summary>提示</summary>map 存「值 → 在 slice 中的下标」；删除时把末尾元素挪到被删位置，再缩短 slice。</details>
- [ ] **528. 按权重随机选择**（Random Pick with Weight） · 中等 · [力扣](https://leetcode.cn/problems/random-pick-with-weight/) · [LeetCode](https://leetcode.com/problems/random-pick-with-weight/)
  - 运维场景：按权重分流：金丝雀发布 10%、加权轮询。Gateway API 的流量拆分就是按权重转发。
  - 练到的 Go：前缀和 + `sort.SearchInts`、`math/rand/v2`（[G12](../../notes/go/12-client-go.md)）
  - <details><summary>提示</summary>先算前缀和，随机取一个 [1, total] 的数，二分查找它落在哪一段。</details>

<a id="w19"></a>

### W19 · CKA · G12 watch / informer

本周 Go 知识点：[G12](../../notes/go/12-client-go.md)

- [ ] **743. 网络延迟时间**（Network Delay Time） · 中等 · [力扣](https://leetcode.cn/problems/network-delay-time/) · [LeetCode](https://leetcode.com/problems/network-delay-time/)
  - 运维场景：从一个节点发出的消息或配置推送，要多久才能到达所有节点。
  - 练到的 Go：Dijkstra + `container/heap`（[G12](../../notes/go/12-client-go.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>求出所有节点的最短路，取最大值；有节点不可达就返回 -1。</details>
- [ ] **547. 省份数量**（Number of Provinces） · 中等 · [力扣](https://leetcode.cn/problems/number-of-provinces/) · [LeetCode](https://leetcode.com/problems/number-of-provinces/)
  - 运维场景：网络分区以后，集群被切成了几块。
  - 练到的 Go：并查集：struct 封装 find/union，带路径压缩（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>相连的两点做 union，最后数一数有几个根节点。</details>
- [ ] **684. 冗余连接**（Redundant Connection） · 中等 · [力扣](https://leetcode.cn/problems/redundant-connection/) · [LeetCode](https://leetcode.com/problems/redundant-connection/)
  - 运维场景：在网络拓扑里找出造成环路的那根线，类似生成树协议要阻断的那条链路。
  - 练到的 Go：并查集（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>按顺序加边；如果一条边的两端已经在同一个集合里，它就是答案。</details>

<a id="w20"></a>

### W20 · CKA · G14 可观测性与 exporter

本周 Go 知识点：[G14](../../notes/go/14-observability-exporter.md)

- [ ] **1192. 查找集群内的关键连接**（Critical Connections in a Network） · 困难 · [力扣](https://leetcode.cn/problems/critical-connections-in-a-network/) · [LeetCode](https://leetcode.com/problems/critical-connections-in-a-network/)
  - 运维场景：找出集群里的单点故障链路：这根线一断，网络就会被分成两半。
  - 练到的 Go：Tarjan 求桥：DFS 时间戳、递归闭包（[G14](../../notes/go/14-observability-exporter.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>记录每个点的发现时间 disc 和能回溯到的最早时间 low；当 `low[v] > disc[u]` 时，边 (u, v) 是桥。</details>
- [ ] **1584. 连接所有点的最小费用**（Min Cost to Connect All Points） · 中等 · [力扣](https://leetcode.cn/problems/min-cost-to-connect-all-points/) · [LeetCode](https://leetcode.com/problems/min-cost-to-connect-all-points/)
  - 运维场景：用最小的总代价把所有机房或节点连通，也就是最小生成树。
  - 练到的 Go：Prim + 堆，或 Kruskal + 并查集 + `slices.SortFunc`（[G14](../../notes/go/14-observability-exporter.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>点数不超过 1000，完全图上用 O(n²) 的朴素 Prim 就足够。</details>

<a id="w21"></a>

### W21 · CKA · G13 Controller 与 Operator

本周 Go 知识点：[G13](../../notes/go/13-controller-operator.md)

- [ ] **875. 爱吃香蕉的珂珂**（Koko Eating Bananas） · 中等 · [力扣](https://leetcode.cn/problems/koko-eating-bananas/) · [LeetCode](https://leetcode.com/problems/koko-eating-bananas/)
  - 运维场景：每小时至少要处理多少个任务，才能在期限内处理完？这是处理速率的规划问题。
  - 练到的 Go：二分答案、整数向上取整 `(p+k-1)/k`（[G13](../../notes/go/13-controller-operator.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>对「速度」做二分，判断这个速度能不能在 h 小时内吃完。</details>
- [ ] **1011. 在 D 天内送达包裹的能力**（Capacity To Ship Packages Within D Days） · 中等 · [力扣](https://leetcode.cn/problems/capacity-to-ship-packages-within-d-days/) · [LeetCode](https://leetcode.com/problems/capacity-to-ship-packages-within-d-days/)
  - 运维场景：容量规划：每天的传输带宽或批处理容量至少要多大，才能在 D 天内按顺序处理完所有备份任务。
  - 练到的 Go：二分答案（[G13](../../notes/go/13-controller-operator.md)、[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>下界是 `max(weights)`，上界是 `sum(weights)`；对容量二分，贪心模拟需要几天。</details>

<a id="w22"></a>

### W22 · CKA · G13 kubebuilder

本周 Go 知识点：[G13](../../notes/go/13-controller-operator.md)

- [ ] **1396. 设计地铁系统**（Design Underground System） · 中等 · [力扣](https://leetcode.cn/problems/design-underground-system/) · [LeetCode](https://leetcode.com/problems/design-underground-system/)
  - 运维场景：统计请求在两个服务之间的平均耗时，类似链路追踪里两个 span 之间的平均延迟。
  - 练到的 Go：两个 map、用 struct 作 map 的 key（[G13](../../notes/go/13-controller-operator.md)）
  - <details><summary>提示</summary>checkIn 记录 `id → (站名, 时间)`；checkOut 时把 `(起点, 终点)` 的总耗时和次数累加。</details>
- [ ] **1472. 设计浏览器历史记录**（Design Browser History） · 中等 · [力扣](https://leetcode.cn/problems/design-browser-history/) · [LeetCode](https://leetcode.com/problems/design-browser-history/)
  - 运维场景：发布历史的「回滚 / 前进」：`kubectl rollout undo` 和 `helm rollback` 背后都是一个版本栈。
  - 练到的 Go：slice + 当前下标（[G13](../../notes/go/13-controller-operator.md)）
  - <details><summary>提示</summary>visit 时截掉当前位置之后的历史再追加；back / forward 只移动下标。</details>
- [ ] **460. LFU 缓存**（LFU Cache） · 困难 · [力扣](https://leetcode.cn/problems/lfu-cache/) · [LeetCode](https://leetcode.com/problems/lfu-cache/)
  - 运维场景：按访问频率淘汰的缓存，是 LRU 的升级版。（选做的难题）
  - 练到的 Go：map + 每个频次一条 `container/list` + minFreq（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>维护三样东西：key → 节点、freq → 链表、当前最小频次 minFreq。</details>

<a id="w23"></a>

### W23 · CKA · 复习

- [ ] **72. 编辑距离**（Edit Distance） · 中等 · [力扣](https://leetcode.cn/problems/edit-distance/) · [LeetCode](https://leetcode.com/problems/edit-distance/)
  - 运维场景：衡量两份配置「差了多少」；命令拼写纠错（kubectl 的 did you mean）也是这个算法。
  - 练到的 Go：二维 DP 切片（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>`dp[i][j]` 表示前 i 个字符变成前 j 个字符的最少操作数，由左、上、左上三个格子推出来。</details>
- [ ] **1143. 最长公共子序列**（Longest Common Subsequence） · 中等 · [力扣](https://leetcode.cn/problems/longest-common-subsequence/) · [LeetCode](https://leetcode.com/problems/longest-common-subsequence/)
  - 运维场景：diff 工具的核心：比较两版配置文件时，`diff` / `git diff` 就是靠它对齐相同的行。
  - 练到的 Go：二维 DP，可以用滚动数组优化空间（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>字符相等取 `dp[i-1][j-1]+1`，否则取上边和左边的较大值。</details>

<a id="w24"></a>

### W24 · CKA 考试周

暂停刷题，专心考试。考前一天可以挑一道做过的简单题热热手。

<a id="premium"></a>

## 可选会员题 🔒

以下题目需要 LeetCode / 力扣会员。场景都很贴近运维，有会员可以穿插着做，没有也不影响主线。

- [ ] **359. 日志速率限制器**（Logger Rate Limiter） 🔒 · 简单 · [力扣](https://leetcode.cn/problems/logger-rate-limiter/) · [LeetCode](https://leetcode.com/problems/logger-rate-limiter/)
  - 运维场景：同一条日志 10 秒内只打印一次：日志降噪、告警去重。
  - 练到的 Go：`map[string]int`（[G3](../../notes/go/03-composite-types.md)）
  - <details><summary>提示</summary>记录每条消息下次允许打印的时间。</details>
- [ ] **362. 敲击计数器**（Design Hit Counter） 🔒 · 中等 · [力扣](https://leetcode.cn/problems/design-hit-counter/) · [LeetCode](https://leetcode.com/problems/design-hit-counter/)
  - 运维场景：统计最近 5 分钟的请求数：限流、QPS 面板。
  - 练到的 Go：环形数组（300 个桶）（[G7](../../notes/go/07-concurrency-context.md)）
  - <details><summary>提示</summary>每个桶存（时间戳, 次数），时间戳过期就重置这个桶。</details>
- [ ] **588. 设计内存文件系统**（Design In-Memory File System） 🔒 · 困难 · [力扣](https://leetcode.cn/problems/design-in-memory-file-system/) · [LeetCode](https://leetcode.com/problems/design-in-memory-file-system/)
  - 运维场景：实现内存里的 ls / mkdir / 写文件，用前缀树表示目录树。
  - 练到的 Go：Trie、`slices.Sort`（[G5](../../notes/go/05-stdlib-files-text-exec.md)）
  - <details><summary>提示</summary>每个节点保存子节点 map 和文件内容；ls 时对子节点名排序。</details>
- [ ] **1166. 设计文件系统**（Design File System） 🔒 · 中等 · [力扣](https://leetcode.cn/problems/design-file-system/) · [LeetCode](https://leetcode.com/problems/design-file-system/)
  - 运维场景：类似 etcd / ZooKeeper 的层级 key：创建 `/a/b` 之前必须先有 `/a`。
  - 练到的 Go：`map[string]int` + `strings.LastIndexByte` 找父路径（[G5](../../notes/go/05-stdlib-files-text-exec.md)）
  - <details><summary>提示</summary>创建前检查父路径是否存在、自己是否已存在。</details>
- [ ] **253. 会议室 II**（Meeting Rooms II） 🔒 · 中等 · [力扣](https://leetcode.cn/problems/meeting-rooms-ii/) · [LeetCode](https://leetcode.com/problems/meeting-rooms-ii/)
  - 运维场景：同一时刻最多有多少个维护窗口重叠，就需要多少名值班人员或多少个并发槽位。
  - 练到的 Go：排序 + 小顶堆，或差分数组（[G15](../../notes/go/15-leetcode-in-go.md)）
  - <details><summary>提示</summary>按开始时间排序，堆里存各个会议的结束时间。</details>

## 按算法专题索引

| 专题 | 本计划里的题号 |
|---|---|
| 哈希表 | 1、49、347、811、929、609、692、706、380、981、1396 |
| 字符串处理 | 1108、14、929、71、165、468、8、394 |
| 栈 / 单调队列 | 20、155、232、71、150、224、394、239 |
| 链表 | 21、23、146、460 |
| 堆（container/heap） | 23、215、295、703、347、692、743 |
| 区间、排序、贪心 | 56、57、435、621、253 🔒 |
| 二分查找 / 二分答案 | 704、278、981、528、875、1011 |
| 滑动窗口 | 3、239 |
| BFS / DFS | 200、994、102 |
| 拓扑排序 | 207、210 |
| 并查集 | 547、684、1584 |
| 最短路与图论 | 743、1192、1584 |
| 设计题 | 155、232、706、622、146、460、981、380、1396、1472、359 🔒、362 🔒、588 🔒、1166 🔒 |
| 动态规划 | 72、1143 |
| 并发 | 1114 |

合计：主线 56 道（全部免费），可选会员题 5 道。
