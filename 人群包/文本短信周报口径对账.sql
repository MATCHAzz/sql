/*
目标：
对账周报里的“文本短信”花费，确认当前 recall_recent + 沉默60+ + 非学生口径为什么比周报小。

对账周：
- 2026-05-04 ~ 2026-05-10
- 2026-05-11 ~ 2026-05-17

输出口径：
1. 周报可能口径：文本召回tag全量，包含 recall%、bonus%、%mengwang%。
2. recall_recent文本：只看 tag LIKE 'recall_recent%'。
3. recall_recent文本_沉默60+：在2基础上加 d - last_active_date >= 60。
4. recall_recent文本_沉默60+非学生：在3基础上排除学生和 blocked 用户。

说明：
这份 SQL 用于排查口径差异，不替代正式 CAC 组合测算。
*/

SELECT
    concat(toString(toMonday(s.d)), ' ~ ', toString(toMonday(s.d) + 6)) AS `周`,
    arrayJoin(
        arrayConcat(
            if(
                   s.tag LIKE 'recall%'
                OR s.tag LIKE 'bonus%'
                OR s.tag LIKE '%mengwang%',
                ['01_周报可能口径_文本召回tag全量'],
                emptyArrayString()
            ),
            if(
                s.tag LIKE 'recall_recent%',
                ['02_recall_recent文本_全部用户'],
                emptyArrayString()
            ),
            if(
                s.tag LIKE 'recall_recent%' AND s.silent_days >= 60,
                ['03_recall_recent文本_沉默60+'],
                emptyArrayString()
            ),
            if(
                    s.tag LIKE 'recall_recent%'
                AND s.silent_days >= 60
                AND ifNull(nullIf(trimBoth(toString(u.five_class)), ''), '未知') != '学生'
                AND ifNull(u.is_blocked, 0) = 0,
                ['04_recall_recent文本_沉默60+非学生'],
                emptyArrayString()
            )
        )
    ) AS `口径`,
    count() AS `发送量`,
    countIf(s.is_send_success = 1) AS `发送成功消息数`,
    round(countIf(s.is_send_success = 1) / nullIf(count(), 0), 4) AS `通道成功率`,
    sumIf(s.msg_cnt, s.is_send_success = 1) AS `计费短信条数`,
    round(sumIf(s.fee, s.is_send_success = 1), 2) AS `短信成本`,
    uniqExactIf(s.uid, s.is_send_success = 1) AS `发送成功用户数`,
    uniqExactIf(s.uid, s.is_send_success = 1 AND ifNull(active.has_day_active, 0) = 1) AS `当日活跃召回用户数`,
    round(
        uniqExactIf(s.uid, s.is_send_success = 1 AND ifNull(active.has_day_active, 0) = 1)
        / nullIf(uniqExactIf(s.uid, s.is_send_success = 1), 0),
        4
    ) AS `当日活跃召回率`,
    round(
        sumIf(s.fee, s.is_send_success = 1)
        / nullIf(uniqExactIf(s.uid, s.is_send_success = 1 AND ifNull(active.has_day_active, 0) = 1), 0),
        2
    ) AS `CAC`
FROM
(
    SELECT
        toUInt64(uid) AS uid,
        d,
        tag,
        is_send_success,
        d - last_active_date AS silent_days,
        msg_cnt,
        msg_cnt * unit_price AS fee
    FROM
    (
        SELECT
            uid,
            d,
            tag,
            is_send_success,
            last_active_date,
            pay_channel,
            cnt_len,
            multiIf(
                cnt_len < 71, 1,
                cnt_len >= 71 AND cnt_len <= 134, 2,
                cnt_len >= 135 AND cnt_len <= 201, 3,
                4
            ) AS msg_cnt,
            multiIf(
                pay_channel = '泰迪熊TDX', 0.022,
                pay_channel = '秒信HDHC', 0.027,
                pay_channel = '创蓝hdhc1', 0.03,
                pay_channel = '中网讯通', 0.03,
                pay_channel = '聚梦', 0.027,
                pay_channel = '腾域HDHC', 0.029,
                pay_channel = '助通HDHC1', 0.0278,
                pay_channel = '阿里云HDLC', 0.027,
                pay_channel = '阿里云1', 0.027,
                pay_channel = '湖南云客', 0.027,
                pay_channel = '一知' AND d < toDate('2025-07-16'), 0.13,
                pay_channel = '一知' AND d >= toDate('2025-07-16'), 0.16,
                pay_channel = 'aliyun_ai', 0.14,
                pay_channel = '文本短信-3日前', 0.03,
                pay_channel = '百应' AND d < toDate('2025-07-17'), 0.16,
                pay_channel = '百应' AND d >= toDate('2025-07-17') AND d <= toDate('2025-08-31'), 0.17,
                pay_channel = '百应' AND d >= toDate('2025-09-01'), 0.15,
                pay_channel = '智齿', 0.12,
                pay_channel = '挂机短信-聚梦', 0.027,
                pay_channel = '挂机短信-秒信HDHC', 0.03,
                pay_channel = '挂机短信-中网讯通', 0.03,
                pay_channel = '挂机短信-阿里云1', 0.027,
                pay_channel = '泰迪', 0.12,
                pay_channel = '展奎', 0.12,
                pay_channel = '视频短信', 0.076,
                pay_channel = '微信/特殊push', 0,
                pay_channel = '华为营销', 0.032,
                pay_channel = 'BFSHHDHC', 0.022,
                0
            ) AS unit_price
        FROM
        (
            SELECT
                uid,
                d,
                tag,
                is_send_success,
                last_active_date,
                if(
                    substringUTF8(content, 1, 5) LIKE '【脉脉】%',
                    lengthUTF8(content),
                    if(provider_channel LIKE '%阿里云%', lengthUTF8(content) + 2, lengthUTF8(content) + 4)
                ) AS cnt_len,
                multiIf(
                    tag LIKE '%wechat%' OR tag LIKE '%push%', '微信/特殊push',
                    tag LIKE '%fumeiti%', '视频短信',
                    (
                           tag LIKE '%机遇%'
                        OR tag LIKE '%兜底%'
                        OR tag LIKE '%首播%'
                        OR tag LIKE '%复播%'
                        OR tag LIKE '机遇%'
                        OR tag LIKE 'zhichi%'
                        OR tag LIKE '百应%'
                        OR tag LIKE '智齿%'
                        OR tag LIKE 'yizhi%'
                        OR tag LIKE '高薪%'
                        OR tag LIKE '阿里云%'
                    ), concat('挂机短信-', provider_channel),
                    provider_channel
                ) AS pay_channel
            FROM dws.dw_sms_di
            WHERE d BETWEEN toDate('2026-05-04') AND toDate('2026-05-17')
              AND tag NOT LIKE 'recall_phone%'
              AND tag NOT LIKE '%wechat%'
              AND tag NOT LIKE '%push%'
              AND tag NOT LIKE '%fumeiti%'
              AND tag NOT LIKE 'recall_today_1_send_msg%'
              AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
        )
        WHERE pay_channel NOT IN ('微信/特殊push', '视频短信')
    )
) AS s
ANY LEFT JOIN
(
    SELECT
        toUInt64(uid) AS uid,
        any(five_class) AS five_class,
        any(is_blocked) AS is_blocked
    FROM dim.dim_user
    GROUP BY uid
) AS u
    ON s.uid = u.uid
ANY LEFT JOIN
(
    SELECT
        toUInt64(uid) AS uid,
        d AS send_date,
        1 AS has_day_active
    FROM dws.dw_dau
    WHERE d BETWEEN toDate('2026-05-04') AND toDate('2026-05-17')
      AND is_puppet = 0
    GROUP BY uid, send_date
) AS active
    ON s.uid = active.uid
   AND s.d = active.send_date
GROUP BY
    `周`,
    `口径`
ORDER BY
    `周` DESC,
    `口径` ASC;
