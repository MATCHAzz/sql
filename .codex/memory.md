# Codex Memory

本文件记录当前项目中 ClickHouse / SQL / 数据分析相关的长期可复用记忆。

## 用户召回口径

- 来源：`人群包/沉默60非学生短信召回CAC精确频次组合.sql`。本次已按项目规则读取 `.codex/dim.dim_user.xlsx`；该表为有效注册用户维度表，主键 `uid`，相关字段包括 `five_class`（五类人群）和 `is_blocked`（是否封禁用户）。
- 沉默 60+ 非学生文本短信召回 / CAC 分析中，“当日召回用户”以 `dwm.dw_growth_user_sms_recall_di` 作为召回明细；召回明细需在 `dwm.dw_growth_user_active_di` 同一 `uid`、同一天满足 `is_sms_touch = 1`。
- 当日召回要求召回明细日期等于短信发送日期，并在发送明细关联时同时匹配 `uid`、`tag`、`send_date`；该口径不等待额外观察窗口。
- 发送侧使用 `dws.dw_sms_di` 的发送成功短信：`is_send_success = 1`、`tag LIKE 'recall_recent%'`，并排除电话、微信、push、视频短信/富媒体及 `recall_today_1_send_msg%`、`recall_after_3_send_msg_with_equity%` 等非本口径文本短信；沉默天数按发送日 `d - last_active_date >= 60` 判断。
- 人群侧关联 `dim.dim_user` 后排除学生和封禁用户：`five_class != '学生'`（空值按未知处理，不按学生排除）且 `ifNull(is_blocked, 0) = 0`。
- 计数粒度先按 `uid + send_month` 汇总，`has_recall = max(同月任一匹配发送日/标签是否召回)`，因此同一用户同月最多计 1 个当日召回；最终当日召回用户数为各分组 `sum(month_recall_cnt)`，同一用户跨月份可在对应月份重复计入。
