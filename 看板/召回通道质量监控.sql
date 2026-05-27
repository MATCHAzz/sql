/*
看板3：召回通道质量监控

口径：
1. 业务日期取 toDate('2026-01-01') 到 yesterday()。
2. 短信通道成功率 = 文本短信发送成功用户数 / 文本短信下发用户数。
3. 短信通道召回率 = 短信通道召回用户数 / 文本短信发送成功用户数。
4. 电话通道成功率 = 电话成功用户数 / 电话下发用户数。
   - 电话成功规则与看板1一致：
     容联 reason = 0，百应/泰迪/一知/jumeng/aliyun_ai reason = 1，
     智齿 reason = 2，中通天鸿 reason = 201。
   - 次日复呼/复播任务按 d - 1 归因成功量，电话下发量只统计非次日复呼/复播任务。
5. 电话通道召回率 = 电话通道召回用户数 / 电话成功用户数。
   - 电话通道召回用户数只统计能按 uid + 原始电话日期匹配到成功外呼明细的智能电话召回用户。
6. 召回用户数沿用「看板/召回量级监控.sql」的有效召回归因和渠道互斥口径。

说明：
看板权限解析会把命名 CTE 误判成真实表，所以这里不用命名 CTE。
*/

SELECT
    d,
    round(sum(sms_send_success_user_cnt) / nullIf(sum(sms_send_user_cnt), 0), 4) AS `短信通道成功率`,
    round(sum(sms_recall_user_cnt) / nullIf(sum(sms_send_success_user_cnt), 0), 4) AS `短信通道召回率`,
    round(sum(phone_send_success_user_cnt) / nullIf(sum(phone_send_user_cnt), 0), 4) AS `电话通道成功率`,
    round(sum(phone_recall_user_cnt) / nullIf(sum(phone_send_success_user_cnt), 0), 4) AS `电话通道召回率`
FROM
(
    /* 1. 文本短信下发用户数、发送成功用户数 */
    SELECT
        d,
        uniqExact(uid) AS sms_send_user_cnt,
        uniqExactIf(uid, is_send_success = 1) AS sms_send_success_user_cnt,
        toUInt64(0) AS sms_recall_user_cnt,
        toUInt64(0) AS phone_send_user_cnt,
        toUInt64(0) AS phone_send_success_user_cnt,
        toUInt64(0) AS phone_recall_user_cnt
    FROM
    (
        SELECT
            toUInt64(uid) AS uid,
            d,
            is_send_success,
            multiIf(
                tag LIKE 'recall_phone%', '智能电话',
                tag LIKE '%wechat%', '微信',
                tag LIKE 'recall_push%', '特殊push',
                tag LIKE '%push%', '普通push',
                tag LIKE '%fumeiti%', '视频短信',
                tag LIKE 'recall_%', '文本短信',
                '其他'
            ) AS channel
        FROM dws.dw_sms_di
        WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
          AND toUInt64(uid) != 0
          AND (
                 tag LIKE 'recall%'
              OR tag LIKE 'bonus%'
              OR tag LIKE '%mengwang%'
          )
          AND tag NOT LIKE 'recall_today_1_send_msg%'
          AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
    ) AS sms_send
    WHERE channel = '文本短信'
    GROUP BY d

    UNION ALL

    /* 2. 电话下发用户数、成功用户数 */
    SELECT
        d,
        toUInt64(0) AS sms_send_user_cnt,
        toUInt64(0) AS sms_send_success_user_cnt,
        toUInt64(0) AS sms_recall_user_cnt,
        uniqExactIf(uid, nextdaycall = 0) AS phone_send_user_cnt,
        uniqExactIf(uid, success = 1) AS phone_send_success_user_cnt,
        toUInt64(0) AS phone_recall_user_cnt
    FROM
    (
        SELECT
            toUInt64(uid) AS uid,
            if(
                task_name LIKE '%复播' OR task_name LIKE '%次日复%',
                d - 1,
                d
            ) AS d,
            (
                   (type = '容联' AND reason = 0)
                OR (type = '百应' AND reason = 1)
                OR (type = '智齿' AND reason = 2)
                OR (type = '中通天鸿' AND reason = 201)
                OR (type = '泰迪' AND reason = 1)
                OR (type = '一知' AND reason = 1)
                OR (type = 'jumeng' AND reason = 1)
                OR (type = 'aliyun_ai' AND reason = 1)
            ) AS success,
            if(task_name LIKE '%复播' OR task_name LIKE '%次日复%', 1, 0) AS nextdaycall
        FROM dwd.dw_growth_sms_smartphone_call_di
        WHERE d BETWEEN toDate('2026-01-01') AND yesterday() + 1
          AND toUInt64(uid) != 0
    ) AS phone_send
    WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
    GROUP BY d

    UNION ALL

    /* 3. 有效召回用户数：短信通道、电话通道 */
    SELECT
        r.biz_date AS d,
        toUInt64(0) AS sms_send_user_cnt,
        toUInt64(0) AS sms_send_success_user_cnt,
        countIf(
            r.channel = '文本短信'
            AND (
                ifNull(sms_by_msg.has_sms_record, 0) = 1
                OR ifNull(sms_success_fallback.has_sms_record, 0) = 1
            )
        ) AS sms_recall_user_cnt,
        toUInt64(0) AS phone_send_user_cnt,
        toUInt64(0) AS phone_send_success_user_cnt,
        countIf(
            r.channel = '智能电话'
            AND ifNull(phone_success.has_phone_success, 0) = 1
        ) AS phone_recall_user_cnt
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
    ) AS sms_by_msg
        ON r.emobile = sms_by_msg.emobile
       AND r.touch_msg_id = sms_by_msg.touch_msg_id
    ANY LEFT JOIN
    (
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
    ) AS sms_success_fallback
        ON r.emobile = sms_success_fallback.emobile
       AND r.tag = sms_success_fallback.tag
       AND r.recall_date = sms_success_fallback.recall_date
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            d AS recall_date,
            1 AS has_phone_success
        FROM dwd.dw_growth_sms_smartphone_call_di
        WHERE d BETWEEN toDate('2026-01-01') AND yesterday() + 1
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
        GROUP BY
            uid,
            recall_date
    ) AS phone_success
        ON r.uid = phone_success.uid
       AND r.recall_date = phone_success.recall_date
    GROUP BY r.biz_date
) AS metrics
GROUP BY d
ORDER BY d DESC;
