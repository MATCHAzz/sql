/*
用途：
把“非学生沉默60-179天 recall_recent 文本短信”加入 6 月发送人群逻辑。

对应测算结论：
- 只看 recall_recent% 文本短信。
- 排除微信、push、视频短信/富媒体。
- 只看非学生、非 blocked。
- 已将测算 SQL 中“5次及以上”继续拆细为 5/6/7/8/9/10/11/12/13次及以上。
- 按当前测算结果：
  - 60-89天：6月可发到12次，用周二、周四、周日并排除6月30日控制。
  - 90-179天：6月可发到6次，用周二 + 6月第一个周四控制。
- 180天+ 历史样本极少且无召回，不加入。

落地说明：
1. 这里用发送日控制频次，不增加 sent_cnt_this_month。
2. 该星期配置只针对 2026 年 6 月；如果下个月继续复用，需要重新按当月日历确认次数。
3. 下面给的是可直接嵌入你现有人群 SQL 的补充片段，不是独立完整 SQL。
*/

/*
一、在主表 a 的 SELECT 字段里补充 five_class：

select toUInt64(uid) as uid,
  real_name,
  five_class,
  case ...
*/

/*
二、把原 SQL 里的这段：

AND((
    today() - last_active_date between 30 and 35
    ...
  )
  or(
    today() - last_active_date between 36 and 59
    ...
  )
)

替换成下面这段。
*/

AND
(
    (
        today() - last_active_date between 30 and 35
        and total_duration not between 0 and 70
        and class in (
            '传统主流一线',
            '新经济头部',
            '新经济腰尾',
            '传统行业其他',
            '其他华为苹果中高端新一线',
            '其他主流行业',
            '其他其他'
        )
    )
    or
    (
        today() - last_active_date between 36 and 59
        and total_duration not between 0 and 70
        and class in (
            '传统主流一线',
            '新经济头部',
            '新经济腰尾',
            '传统行业其他',
            '其他华为苹果中高端新一线',
            '其他主流行业',
            '其他其他'
        )
        and toDayOfWeek(today()) in (2, 4, 7)
    )
    or
    (
        today() between toDate('2026-06-01') and toDate('2026-06-30')
        and (
            (
                today() - last_active_date between 60 and 89
                and toDayOfWeek(today()) in (2, 4, 7)
                and today() != toDate('2026-06-30')
            )
            or
            (
                today() - last_active_date between 90 and 179
                and (
                    toDayOfWeek(today()) = 2
                    or today() = toDate('2026-06-04')
                )
            )
        )
        and ifNull(nullIf(trimBoth(toString(five_class)), ''), '未知') != '学生'
        and class in (
            '传统主流一线',
            '新经济头部',
            '新经济腰尾',
            '传统行业其他',
            '其他华为苹果中高端新一线',
            '其他主流行业',
            '其他其他'
        )
    )
)
