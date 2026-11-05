# 实验与练习（labs/）

知识点看懂不等于会做。三门考试都是**上机实操**，这里的每道题都要在自己的虚拟机上亲手敲一遍。

| 轨道 | 环境搭建 | 分知识点练习 | 模拟考 |
|---|---|---|---|
| RHCSA · EX200 | [00-lab-setup](rhcsa/00-lab-setup.md) | [practice-set-1](rhcsa/practice-set-1.md) | [mock-exam](rhcsa/mock-exam.md) |
| RHCE · EX294 | [00-lab-setup](rhce/00-lab-setup.md) | [practice-set-1](rhce/practice-set-1.md) | [mock-exam](rhce/mock-exam.md) |
| CKA | [00-lab-setup](cka/00-lab-setup.md) | [practice-set-1](cka/practice-set-1.md) | [mock-exam](cka/mock-exam.md) |

## 使用方法

1. 每学完一篇笔记，做 practice-set 里对应小节的题。提示和参考答案折叠在 `<details>` 里，**先自己做**。
2. 做之前给虚拟机打快照，做完用题目里的「验证」命令自查，然后**重启**再验证一次（RHCSA/RHCE 的配置必须重启后仍然生效）。
3. 做错或卡住的题，记到 [`../journal/mistakes.md`](../journal/mistakes.md)。
4. 每门考试前一到两周做模拟考：严格计时、只用考场允许的文档、做完对照评分表打分。

> 所有题目都是根据官方考纲原创的练习，不是真题，也不代表真实考试的题量和难度分布。
