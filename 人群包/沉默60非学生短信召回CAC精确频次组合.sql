/*
目标：
在总 CAC <= 5 元约束下，按“沉默区间 × 实际月发次数”拆分历史效果，
用于组合选择不同人群和不同发送次数，最大化当日召回人数。

核心口径：
1. 学生排除：dim.dim_user.five_class != '学生'。
2. 沉默60+：发送当天 dws.dw_sms_di.d - dws.dw_sms_di.last_active_date >= 60。
3. 发送成功：dws.dw_sms_di.is_send_success = 1。
4. 文本短信：tag LIKE 'recall_recent%'，并排除电话、微信、push、视频短信/富媒体等非文本短信。
5. 召回口径：使用周报口径的 dwm.dw_growth_user_sms_recall_di 召回明细。
   - 召回用户需在 dwm.dw_growth_user_active_di 当天满足 is_sms_touch = 1。
   - 只看当日召回：召回明细日期 = 短信发送日期。
   - 当日口径不需要等待观察窗口，发送明细和召回明细都截止到 yesterday()。
6. 实际月发次数：用户当月实际收到的召回短信成功次数，精确拆为 1-12 次和 13 次及以上。
7. 用户当月只归属一个沉默区间：按当月第一次发送时的沉默天数归属，避免月内跨区间重复计数。
8. CAC = 短信成本 / 当日召回用户数。

组合选择方法：
1. 先纳入 CAC <= 5 的组合；这些组合单独和合并后都不会拉高总 CAC 到 5 以上。
2. 如果还要继续扩大召回量，再评估 CAC > 5 的组合。
3. CAC5元盈余 = 5 * 当日召回用户数 - 短信成本。
   多个组合合并时，只要 sum(CAC5元盈余) >= 0，总 CAC 就仍然 <= 5。
4. 对 CAC > 5 的组合，优先考虑 CAC 更低、召回量更大的组合。
*/

SELECT
    silent_bucket AS `沉默区间`,
    send_cnt_bucket AS `实际月发次数`,
    count() AS `覆盖月份数`,
    sum(month_user_cnt) AS `发送成功用户数`,
    sum(month_msg_cnt) AS `发送成功消息数`,
    sum(month_sms_cnt) AS `计费短信条数`,
    round(sum(month_msg_cnt) / nullIf(sum(month_user_cnt), 0), 2) AS `人均月发送次数`,
    sum(month_recall_cnt) AS `当日召回用户数`,
    round(sum(month_recall_cnt) / nullIf(sum(month_user_cnt), 0), 4) AS `当日召回率`,
    round(sum(month_fee), 2) AS `短信成本`,
    round(sum(month_fee) / nullIf(sum(month_recall_cnt), 0), 2) AS `CAC`,
    if(round(sum(month_fee) / nullIf(sum(month_recall_cnt), 0), 2) <= 5, '是', '否') AS `是否单组满足CAC5元`,
    round(5 * sum(month_recall_cnt) - sum(month_fee), 2) AS `CAC5元盈余`,
    round(max(month_cac), 2) AS `最高月CAC`,
    countIf(month_cac > 5) AS `超5月份数`
FROM
(
    SELECT
        um.send_month AS send_month,
        multiIf(
            um.first_silent_days >= 60 AND um.first_silent_days < 90, '01_60-89天',
            um.first_silent_days >= 90 AND um.first_silent_days < 180, '02_90-179天',
            um.first_silent_days >= 180, '03_180天+',
            '其他'
        ) AS silent_bucket,
        multiIf(
            um.send_success_cnt = 1, '01_实际月发1次',
            um.send_success_cnt = 2, '02_实际月发2次',
            um.send_success_cnt = 3, '03_实际月发3次',
            um.send_success_cnt = 4, '04_实际月发4次',
            um.send_success_cnt = 5, '05_实际月发5次',
            um.send_success_cnt = 6, '06_实际月发6次',
            um.send_success_cnt = 7, '07_实际月发7次',
            um.send_success_cnt = 8, '08_实际月发8次',
            um.send_success_cnt = 9, '09_实际月发9次',
            um.send_success_cnt = 10, '10_实际月发10次',
            um.send_success_cnt = 11, '11_实际月发11次',
            um.send_success_cnt = 12, '12_实际月发12次',
            '13_实际月发13次及以上'
        ) AS send_cnt_bucket,
        count() AS month_user_cnt,
        sum(um.send_success_cnt) AS month_msg_cnt,
        sum(um.msg_cnt) AS month_sms_cnt,
        sum(um.has_recall) AS month_recall_cnt,
        sum(um.fee) AS month_fee,
        sum(um.fee) / nullIf(sum(um.has_recall), 0) AS month_cac
    FROM
    (
        SELECT
            s.uid AS uid,
            s.send_month AS send_month,
            argMin(s.silent_days, s.send_date) AS first_silent_days,
            count() AS send_success_cnt,
            sum(s.msg_cnt) AS msg_cnt,
            sum(s.fee) AS fee,
            max(ifNull(recall.has_recall, 0)) AS has_recall
        FROM
        (
            SELECT
                toUInt64(uid) AS uid,
                d AS send_date,
                toStartOfMonth(d) AS send_month,
                tag,
                d - last_active_date AS silent_days,
                msg_cnt,
                msg_cnt * unit_price AS fee
            FROM
            (
                SELECT
                    uid,
                    d,
                    last_active_date,
                    tag,
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
                        last_active_date,
                        if(
                            substringUTF8(content, 1, 5) LIKE '【脉脉】%',
                            lengthUTF8(content),
                            if(provider_channel LIKE '%阿里云%', lengthUTF8(content) + 2, lengthUTF8(content) + 4)
                        ) AS cnt_len,
                        multiIf(
                            tag LIKE '%wechat%' OR tag LIKE 'recall_push%', '微信/特殊push',
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
                    WHERE d BETWEEN toDate('2025-06-01') AND yesterday()
                      AND is_send_success = 1
                      AND tag LIKE 'recall_recent%'
                      AND tag NOT LIKE 'recall_phone%'
                      AND tag NOT LIKE '%wechat%'
                      AND tag NOT LIKE '%push%'
                      AND tag NOT LIKE '%fumeiti%'
                      AND tag NOT LIKE 'recall_today_1_send_msg%'
                      AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                      AND d - last_active_date >= 60
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
                uid,
                tag,
                send_date,
                1 AS has_recall
            FROM
            (
                SELECT
                    uid,
                    tag,
                    recall_date AS send_date
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
                        recall_base.tag AS tag,
                        recall_base.d AS recall_date
                    FROM
                    (
                        SELECT
                            toUInt64(uid) AS uid,
                            tag,
                            d
                        FROM dwm.dw_growth_user_sms_recall_di
                        WHERE d BETWEEN toDate('2025-06-01') AND yesterday()
                          AND tag LIKE 'recall_recent%'
                          AND tag NOT LIKE 'recall_phone%'
                          AND tag NOT LIKE '%wechat%'
                          AND tag NOT LIKE '%push%'
                          AND tag NOT LIKE '%fumeiti%'
                          AND tag NOT LIKE 'recall_today_1_send_msg%'
                          AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                    ) AS recall_base
                    ANY INNER JOIN
                    (
                        SELECT
                            toUInt64(uid) AS uid,
                            d
                        FROM dwm.dw_growth_user_active_di
                        WHERE d BETWEEN toDate('2025-06-01') AND yesterday()
                          AND is_sms_touch = 1
                        GROUP BY uid, d
                    ) AS active_touch
                        ON recall_base.uid = active_touch.uid
                       AND recall_base.d = active_touch.d
                    GROUP BY
                        recall_base.uid,
                        recall_base.tag,
                        recall_base.d
                )
            )
            WHERE send_date BETWEEN toDate('2025-06-01') AND yesterday()
            GROUP BY
                uid,
                tag,
                send_date
        ) AS recall
            ON s.uid = recall.uid
           AND s.tag = recall.tag
           AND s.send_date = recall.send_date
        WHERE ifNull(nullIf(trimBoth(toString(u.five_class)), ''), '未知') != '学生'
          AND ifNull(u.is_blocked, 0) = 0
        GROUP BY
            s.uid,
            s.send_month
    ) AS um
    GROUP BY
        um.send_month,
        silent_bucket,
        send_cnt_bucket
)
GROUP BY
    silent_bucket,
    send_cnt_bucket
ORDER BY
    `CAC` ASC,
    `当日召回用户数` DESC;
