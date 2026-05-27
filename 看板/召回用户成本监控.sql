/*
看板2：召回用户成本监控

口径：
1. 业务日期取 toDate('2026-01-01') 到 yesterday()。
2. 召回用户、渠道互斥归因、人群拆分与「看板/召回量级监控.sql」保持一致。
3. 召回成本按当天全量发送成功触达明细汇总，不按 uid 去重；
   短信/Push/视频短信成本来自 dws.dw_sms_di，智能电话成本来自 dwd.dw_growth_sms_smartphone_call_di。
4. CAC = 召回成本 / 召回用户数；分母为 0 时返回 NULL。
5. 人群来自 dim.dim_user.seven_class：
   - 新经济尾部兼容历史命名 '新经济腰尾'。
   - 其他用户 = 非新经济头部、非新经济尾部/腰尾、非传统主流一线。

说明：
看板权限解析会把命名 CTE 误判成真实表，所以这里不用命名 CTE。
*/

SELECT
    d,
    round(sum(recall_fee) / nullIf(sum(recall_user_cnt), 0), 2) AS `当天召回总cac`,
    round(sum(sms_recall_fee) / nullIf(sum(sms_recall_user_cnt), 0), 2) AS `短信当天cac`,
    round(sum(phone_recall_fee) / nullIf(sum(phone_recall_user_cnt), 0), 2) AS `电话当天cac`,
    round(sum(special_push_recall_fee) / nullIf(sum(special_push_recall_user_cnt), 0), 2) AS `特殊push当天cac`,
    round(sum(new_economy_head_recall_fee) / nullIf(sum(new_economy_head_user_cnt), 0), 2) AS `新经济头部召回cac`,
    round(sum(new_economy_tail_recall_fee) / nullIf(sum(new_economy_tail_user_cnt), 0), 2) AS `新经济尾部召回cac`,
    round(sum(traditional_first_tier_recall_fee) / nullIf(sum(traditional_first_tier_user_cnt), 0), 2) AS `传统主流一线召回cac`,
    round(sum(other_recall_fee) / nullIf(sum(other_user_cnt), 0), 2) AS `其他用户召回cac`
FROM
(
    /* 1. 召回用户数分母：总量、渠道、人群 */
    SELECT
        r.biz_date AS d,
        count() AS recall_user_cnt,
        toFloat64(0) AS recall_fee,
        countIf(
            r.channel = '文本短信'
            AND (
                ifNull(sms_by_msg.has_sms_record, 0) = 1
                OR ifNull(sms_success_fallback.has_sms_record, 0) = 1
            )
        ) AS sms_recall_user_cnt,
        toFloat64(0) AS sms_recall_fee,
        countIf(r.channel = '智能电话') AS phone_recall_user_cnt,
        toFloat64(0) AS phone_recall_fee,
        countIf(r.channel = '特殊push') AS special_push_recall_user_cnt,
        toFloat64(0) AS special_push_recall_fee,
        countIf(u.seven_class = '新经济头部') AS new_economy_head_user_cnt,
        toFloat64(0) AS new_economy_head_recall_fee,
        countIf(u.seven_class IN ('新经济尾部', '新经济腰尾')) AS new_economy_tail_user_cnt,
        toFloat64(0) AS new_economy_tail_recall_fee,
        countIf(u.seven_class = '传统主流一线') AS traditional_first_tier_user_cnt,
        toFloat64(0) AS traditional_first_tier_recall_fee,
        countIf(ifNull(u.seven_class, '未知') NOT IN ('新经济头部', '新经济尾部', '新经济腰尾', '传统主流一线')) AS other_user_cnt,
        toFloat64(0) AS other_recall_fee
    FROM
    (
        SELECT
            uid,
            tag,
            recall_date,
            emobile,
            touch_msg_id,
            CASE
                WHEN tag LIKE 'recall_phone%' THEN '智能电话'
                WHEN tag LIKE '%wechat%' THEN '微信'
                WHEN tag LIKE 'recall_push%' THEN '特殊push'
                WHEN tag LIKE '%push%' THEN '普通push'
                WHEN tag LIKE '%fumeiti%' THEN '视频短信'
                WHEN tag LIKE 'recall_%' THEN '文本短信'
                ELSE '其他'
            END AS channel,
            biz_date
        FROM
        (
            SELECT
                uid,
                argMin(raw_tag, sort_key) AS tag,
                argMin(recall_dt, sort_key) AS recall_date,
                argMin(emobile, sort_key) AS emobile,
                argMin(touch_msg_id, sort_key) AS touch_msg_id,
                biz_date
            FROM
            (
                SELECT
                    recall_data.uid AS uid,
                    recall_data.tag AS raw_tag,
                    recall_data.d AS recall_dt,
                    recall_data.emobile AS emobile,
                    recall_data.touch_msg_id AS touch_msg_id,
                    concat(
                        toString(
                            multiIf(
                                recall_data.tag LIKE 'recall_phone%', 1,
                                recall_data.tag LIKE '%wechat%', 2,
                                recall_data.tag LIKE 'recall_push%', 3,
                                recall_data.tag LIKE '%push%', 4,
                                recall_data.tag LIKE '%fumeiti%', 5,
                                recall_data.tag LIKE 'recall_%', 6,
                                7
                            )
                        ),
                        '|',
                        toString(recall_data.d),
                        '|',
                        recall_data.tag
                    ) AS sort_key,
                    recall_data.biz_date AS biz_date
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
                        recall_base.tag AS tag,
                        recall_base.emobile AS emobile,
                        recall_base.touch_msg_id AS touch_msg_id,
                        recall_base.d AS d,
                        if(
                            recall_base.tag LIKE 'recall_phone%' AND ifNull(call_detail.nextdaycall, 0) = 1,
                            recall_base.d - 1,
                            recall_base.d
                        ) AS biz_date
                    FROM
                    (
                        SELECT
                            r.uid AS uid,
                            r.tag AS tag,
                            r.emobile AS emobile,
                            r.touch_msg_id AS touch_msg_id,
                            r.d AS d
                        FROM
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                d
                            FROM dwm.dw_growth_user_active_di
                            PREWHERE d BETWEEN toDate('2026-01-01') AND yesterday() + 1
                            WHERE is_silent_30d = 1
                        ) AS su
                        INNER JOIN
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                tag,
                                emobile,
                                touch_msg_id,
                                d
                            FROM dwm.dw_growth_user_sms_recall_di
                            WHERE d BETWEEN toDate('2026-01-01') AND yesterday() + 1
                              AND (
                                     tag LIKE 'recall%'
                                  OR tag LIKE 'bonus%'
                                  OR tag LIKE '%mengwang%'
                              )
                              AND tag NOT LIKE 'recall_today_1_send_msg%'
                              AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                        ) AS r
                            ON su.uid = r.uid
                           AND su.d = r.d
                    ) AS recall_base
                    ANY LEFT JOIN
                    (
                        SELECT
                            toUInt64(uid) AS uid,
                            d,
                            1 AS nextdaycall
                        FROM dwd.dw_growth_sms_smartphone_call_di
                        WHERE (task_name LIKE '%复播' OR task_name LIKE '%次日复%')
                          AND d BETWEEN toDate('2026-01-01') AND yesterday() + 1
                          AND (
                                 (type = '容联' AND reason = 0)
                              OR (type = '百应' AND reason = 1)
                              OR (type = '智齿' AND reason = 2)
                              OR (type = '中通天鸿' AND reason = 201)
                              OR (type = '泰迪' AND reason = 1)
                              OR (type = '一知' AND reason = 1)
                              OR (type = 'jumeng' AND reason = 1)
                              OR (type = 'aliyun_ai' AND reason = 1)
                          )
                        GROUP BY uid, d
                    ) AS call_detail
                        ON recall_base.uid = call_detail.uid
                       AND recall_base.d = call_detail.d
                ) AS recall_data
                ANY INNER JOIN
                (
                    SELECT
                        toUInt64(uid) AS uid,
                        d AS biz_date
                    FROM dwm.dw_growth_user_active_di
                    PREWHERE d BETWEEN toDate('2026-01-01') AND yesterday()
                    WHERE is_sms_touch = 1
                ) AS active_data
                    ON recall_data.uid = active_data.uid
                   AND recall_data.biz_date = active_data.biz_date
                WHERE recall_data.biz_date BETWEEN toDate('2026-01-01') AND yesterday()
            ) AS filtered_recall
            GROUP BY
                biz_date,
                uid
        ) AS dedup_recall
    ) AS r
    ANY LEFT JOIN
    (
        SELECT
            emobile,
            sms_id AS touch_msg_id,
            1 AS has_sms_record
        FROM dws.dw_sms_di
        WHERE d BETWEEN toDate('2026-01-01') - 30 AND yesterday()
        GROUP BY
            emobile,
            touch_msg_id
    ) AS sms_by_msg   -- 精确匹配
        ON r.emobile = sms_by_msg.emobile
       AND r.touch_msg_id = sms_by_msg.touch_msg_id
    ANY LEFT JOIN
    (
        -- 它用于 touch_msg_id 为空或对不上时，按手机号、tag、日期去找“近 3 日内的成功短信”
        SELECT
            emobile,
            tag,
            arrayJoin(arrayMap(x -> d + x, range(3))) AS recall_date,
            1 AS has_sms_record
        FROM dws.dw_sms_di
        WHERE d BETWEEN toDate('2026-01-01') - 3 AND yesterday()
          AND is_send_success = 1
          AND tag LIKE 'recall%'
        GROUP BY
            emobile,
            tag,
            recall_date
    ) AS sms_success_fallback   -- 兜底匹配
        ON r.emobile = sms_success_fallback.emobile
       AND r.tag = sms_success_fallback.tag
       AND r.recall_date = sms_success_fallback.recall_date
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            any(ifNull(nullIf(trimBoth(toString(seven_class)), ''), '未知')) AS seven_class
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON r.uid = u.uid
    GROUP BY r.biz_date

    UNION ALL

    /* 2. 召回成本分子：全量发送成功成本、渠道成本、人群成本 */
    SELECT
        s.biz_date AS d,
        toUInt64(0) AS recall_user_cnt,
        round(sum(s.fee), 2) AS recall_fee,
        toUInt64(0) AS sms_recall_user_cnt,
        round(sumIf(s.fee, s.channel = '文本短信'), 2) AS sms_recall_fee,
        toUInt64(0) AS phone_recall_user_cnt,
        round(sumIf(s.fee, s.channel = '智能电话'), 2) AS phone_recall_fee,
        toUInt64(0) AS special_push_recall_user_cnt,
        round(sumIf(s.fee, s.channel = '特殊push'), 2) AS special_push_recall_fee,
        toUInt64(0) AS new_economy_head_user_cnt,
        round(sumIf(s.fee, u.seven_class = '新经济头部'), 2) AS new_economy_head_recall_fee,
        toUInt64(0) AS new_economy_tail_user_cnt,
        round(sumIf(s.fee, u.seven_class IN ('新经济尾部', '新经济腰尾')), 2) AS new_economy_tail_recall_fee,
        toUInt64(0) AS traditional_first_tier_user_cnt,
        round(sumIf(s.fee, u.seven_class = '传统主流一线'), 2) AS traditional_first_tier_recall_fee,
        toUInt64(0) AS other_user_cnt,
        round(sumIf(s.fee, ifNull(u.seven_class, '未知') NOT IN ('新经济头部', '新经济尾部', '新经济腰尾', '传统主流一线')), 2) AS other_recall_fee
    FROM
    (
        /* 2.1 短信 / Push / 视频短信成本 */
        SELECT
            toUInt64(uid) AS uid,
            d AS biz_date,
            channel,
            if(
                is_send_success = 1,
                multiIf(
                    cnt_len < 71, 1,
                    cnt_len >= 71 AND cnt_len <= 134, 2,
                    cnt_len >= 135 AND cnt_len <= 201, 3,
                    4
                )
                *
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
                ),
                0
            ) AS fee
        FROM
        (
            SELECT
                toUInt64(uid) AS uid,
                d,
                tag,
                is_send_success,
                CASE
                    WHEN tag LIKE 'recall_phone%' THEN '智能电话'
                    WHEN tag LIKE '%wechat%' THEN '微信'
                    WHEN tag LIKE 'recall_push%' THEN '特殊push'
                    WHEN tag LIKE '%push%' THEN '普通push'
                    WHEN tag LIKE '%fumeiti%' THEN '视频短信'
                    WHEN tag LIKE 'recall_%' THEN '文本短信'
                    ELSE '其他'
                END AS channel,
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
            WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
              AND (
                     tag LIKE 'recall%'
                  OR tag LIKE 'bonus%'
                  OR tag LIKE '%mengwang%'
              )
              AND tag NOT LIKE 'recall_phone%'
              AND tag NOT LIKE 'recall_today_1_send_msg%'
              AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
        ) AS sms_with_price

        UNION ALL

        /* 2.2 智能电话成本 */
        SELECT
            uid,
            biz_date,
            '智能电话' AS channel,
            if(success = 1, unit_price, 0) AS fee
        FROM
        (
            SELECT
                toUInt64(uid) AS uid,
                if(
                    task_name LIKE '%复播' OR task_name LIKE '%次日复%',
                    d - 1,
                    d
                ) AS biz_date,
                if(
                       (type = '容联' AND reason = 0)
                    OR (type = '百应' AND reason = 1)
                    OR (type = '智齿' AND reason = 2)
                    OR (type = '中通天鸿' AND reason = 201)
                    OR (type = '泰迪' AND reason = 1)
                    OR (type = '一知' AND reason = 1)
                    OR (type = 'jumeng' AND reason = 1)
                    OR (type = 'aliyun_ai' AND reason = 1),
                    1,
                    0
                ) AS success,
                multiIf(
                    type = '一知' AND d < toDate('2025-07-16'), 0.13,
                    type = '一知' AND d >= toDate('2025-07-16'), 0.16,
                    type = 'aliyun_ai', 0.14,
                    type = '百应' AND d < toDate('2025-07-17'), 0.16,
                    type = '百应' AND d >= toDate('2025-07-17') AND d <= toDate('2025-08-31'), 0.17,
                    type = '百应' AND d >= toDate('2025-09-01'), 0.15,
                    type = '智齿', 0.12,
                    type = '泰迪', 0.12,
                    type = '展奎', 0.12,
                    0
                ) AS unit_price
            FROM dwd.dw_growth_sms_smartphone_call_di
            WHERE d BETWEEN toDate('2026-01-01') AND yesterday() + 1
              AND toUInt64(uid) != 0
        ) AS phone_with_price
        WHERE biz_date BETWEEN toDate('2026-01-01') AND yesterday()
    ) AS s
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            any(ifNull(nullIf(trimBoth(toString(seven_class)), ''), '未知')) AS seven_class
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON s.uid = u.uid
    GROUP BY s.biz_date
) AS metrics
GROUP BY d
ORDER BY d DESC;
