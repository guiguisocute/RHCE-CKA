# 错题本

| 日期 | 考试 | 知识节点 | 现象 / 做错了什么 | 正确做法 | 怎么验证 | 复习次数 |
|---|---|---|---|---|---|---|
| 2026-11-05 | 示例 | [RHCSA-05](../notes/rhcsa/05-file-systems-nfs-autofs.md) | 示例：/etc/fstab 写错 UUID，重启进了 emergency 模式 | 用 `blkid` 复制 UUID；改完先 `mount -a` 再重启 | `findmnt --verify`、`mount -a` 无报错 | 0 |
