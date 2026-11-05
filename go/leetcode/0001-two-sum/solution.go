// Package p0001：LeetCode 1. 两数之和（Two Sum）
//
// 难度：简单（Easy）
// 链接：https://leetcode.cn/problems/two-sum/
//
//	https://leetcode.com/problems/two-sum/
//
// 这是刷题目录的示范：一题一个 package，solution.go 写解法，solution_test.go 写表驱动测试。
// 提交到 LeetCode 时只复制 twoSum 函数，不要复制 package 这一行。
package p0001

// twoSum 返回两个下标 [i, j]（i < j），使 nums[i]+nums[j] == target。
//
// 思路：一次遍历，用 map 记录「已经见过的值 → 它的下标」。
// 对每个 x，先查 target-x 是否出现过：出现过就找到了答案；没有就把 x 记下来。
// 一定要「先查后存」，否则 nums=[3,...]、target=6 时会把同一个 3 用两次。
//
// 复杂度：时间 O(n)，空间 O(n)。暴力两层循环是 O(n²)，n=10⁴ 时也能过，但这里练的是 map。
func twoSum(nums []int, target int) []int {
	seen := make(map[int]int, len(nums)) // 预分配容量，避免扩容
	for i, x := range nums {
		if j, ok := seen[target-x]; ok { // comma-ok：区分「不存在」和「值为 0」
			return []int{j, i}
		}
		seen[x] = i
	}
	return nil // 题目保证有解；返回 nil 是为了让本地测试能覆盖「无解」的输入
}
