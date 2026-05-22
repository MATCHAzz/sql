/*
排查日期按截图先固定为 2026-05-17 ~ 2026-05-19。
如需换日期，替换所有 toDate('2026-05-17') 和 toDate('2026-05-19')。
*/

/* 1. 按天对比：当前互斥归属短信人数 vs 任意短信触达人数 */
SELECT
    biz_date AS d,
    count() AS dedup_user_cnt,
    countIf(selected_channel IN ('文本短信', '视频短信')) AS selected_sms_user_cnt,
    countIf(selected_channel = '文本短信') AS selected_text_sms_user_cnt,
    countIf(selected_channel = '视频短信') AS selected_video_sms_user_cnt,
    countIf(has_text_sms = 1 OR has_video_sms = 1) AS any_sms_user_cnt,
    countIf(has_text_sms = 1) AS any_text_sms_user_cnt,
    countIf(has_video_sms = 1) AS any_video_sms_user_cnt,
    countIf((has_text_sms = 1 OR has_video_sms = 1) AND has_phone = 1) AS sms_and_phone_user_cnt,
    countIf((has_text_sms = 1 OR has_video_sms = 1) AND (has_wechat = 1 OR has_push = 1)) AS sms_and_wechat_push_user_cnt
FROM
(
    SELECT
        biz_date,
        uid,
        argMin(raw_tag, sort_key) AS selected_tag,
        argMin(raw_channel, sort_key) AS selected_channel,
        max(raw_channel = '文本短信') AS has_text_sms,
        max(raw_channel = '视频短信') AS has_video_sms,
        max(raw_channel = '智能电话') AS has_phone,
        max(raw_channel = '微信') AS has_wechat,
        max(raw_channel IN ('特殊push', '普通push')) AS has_push
    FROM
    (
        SELECT
            uid,
            raw_tag,
            recall_dt,
            biz_date,
            raw_channel,
            concat(toString(channel_priority), '|', toString(recall_dt), '|', raw_tag) AS sort_key
        FROM
        (
            SELECT
                uid,
                raw_tag,
                recall_dt,
                biz_date,
                multiIf(
                    raw_tag LIKE 'recall_phone%', '智能电话',
                    raw_tag LIKE '%wechat%', '微信',
                    raw_tag LIKE 'recall_push%', '特殊push',
                    raw_tag LIKE '%push%', '普通push',
                    raw_tag LIKE '%fumeiti%', '视频短信',
                    raw_tag LIKE 'recall_%', '文本短信',
                    '其他'
                ) AS raw_channel,
                multiIf(
                    raw_tag LIKE 'recall_phone%', 1,
                    raw_tag LIKE '%wechat%', 2,
                    raw_tag LIKE 'recall_push%', 3,
                    raw_tag LIKE '%push%', 4,
                    raw_tag LIKE '%fumeiti%', 5,
                    raw_tag LIKE 'recall_%', 6,
                    7
                ) AS channel_priority
            FROM
            (
                SELECT
                    recall_data.uid AS uid,
                    recall_data.tag AS raw_tag,
                    recall_data.d AS recall_dt,
                    recall_data.biz_date AS biz_date
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
                        recall_base.tag AS tag,
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
                            r.d AS d
                        FROM
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                d
                            FROM dwm.dw_growth_user_active_di
                            PREWHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
                            WHERE is_silent_30d = 1
                        ) AS su
                        INNER JOIN
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                tag,
                                d
                            FROM dwm.dw_growth_user_sms_recall_di
                            WHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
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
                          AND d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
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
                    PREWHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
                    WHERE is_sms_touch = 1
                ) AS active_data
                    ON recall_data.uid = active_data.uid
                   AND recall_data.biz_date = active_data.biz_date
                WHERE recall_data.biz_date BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
            )
        )
    )
    GROUP BY
        biz_date,
        uid
)
GROUP BY biz_date
ORDER BY d;

/* 2. 当前被归到短信通道的 tag 明细 */
SELECT
    biz_date AS d,
    selected_channel AS channel,
    selected_tag AS tag,
    count() AS user_cnt
FROM
(
    SELECT
        biz_date,
        uid,
        argMin(raw_tag, sort_key) AS selected_tag,
        argMin(raw_channel, sort_key) AS selected_channel
    FROM
    (
        SELECT
            uid,
            raw_tag,
            recall_dt,
            biz_date,
            raw_channel,
            concat(toString(channel_priority), '|', toString(recall_dt), '|', raw_tag) AS sort_key
        FROM
        (
            SELECT
                uid,
                raw_tag,
                recall_dt,
                biz_date,
                multiIf(
                    raw_tag LIKE 'recall_phone%', '智能电话',
                    raw_tag LIKE '%wechat%', '微信',
                    raw_tag LIKE 'recall_push%', '特殊push',
                    raw_tag LIKE '%push%', '普通push',
                    raw_tag LIKE '%fumeiti%', '视频短信',
                    raw_tag LIKE 'recall_%', '文本短信',
                    '其他'
                ) AS raw_channel,
                multiIf(
                    raw_tag LIKE 'recall_phone%', 1,
                    raw_tag LIKE '%wechat%', 2,
                    raw_tag LIKE 'recall_push%', 3,
                    raw_tag LIKE '%push%', 4,
                    raw_tag LIKE '%fumeiti%', 5,
                    raw_tag LIKE 'recall_%', 6,
                    7
                ) AS channel_priority
            FROM
            (
                SELECT
                    recall_data.uid AS uid,
                    recall_data.tag AS raw_tag,
                    recall_data.d AS recall_dt,
                    recall_data.biz_date AS biz_date
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
                        recall_base.tag AS tag,
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
                            r.d AS d
                        FROM
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                d
                            FROM dwm.dw_growth_user_active_di
                            PREWHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
                            WHERE is_silent_30d = 1
                        ) AS su
                        INNER JOIN
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                tag,
                                d
                            FROM dwm.dw_growth_user_sms_recall_di
                            WHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
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
                          AND d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
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
                    PREWHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
                    WHERE is_sms_touch = 1
                ) AS active_data
                    ON recall_data.uid = active_data.uid
                   AND recall_data.biz_date = active_data.biz_date
                WHERE recall_data.biz_date BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
            )
        )
    )
    GROUP BY
        biz_date,
        uid
)
WHERE selected_channel = '文本短信'
GROUP BY
    d,
    channel,
    tag
ORDER BY
    d DESC,
    user_cnt DESC
LIMIT 200;

/* 3. 当前被归到短信通道的用户，和 dws.dw_sms_di 发送成功口径对比 */
SELECT
    r.biz_date AS d,
    count() AS selected_sms_user_cnt,
    countIf(ifNull(s.has_sms_record, 0) = 1) AS matched_sms_record_user_cnt,
    countIf(ifNull(s.is_send_success, 0) = 1) AS send_success_sms_user_cnt,
    countIf(ifNull(s.has_sms_record, 0) = 0) AS no_sms_record_user_cnt,
    countIf(ifNull(s.has_sms_record, 0) = 1 AND ifNull(s.is_send_success, 0) = 0) AS send_not_success_user_cnt
FROM
(
    SELECT
        biz_date,
        uid,
        argMin(raw_tag, sort_key) AS selected_tag,
        argMin(raw_channel, sort_key) AS selected_channel,
        argMin(recall_dt, sort_key) AS selected_recall_dt
    FROM
    (
        SELECT
            uid,
            raw_tag,
            recall_dt,
            biz_date,
            raw_channel,
            concat(toString(channel_priority), '|', toString(recall_dt), '|', raw_tag) AS sort_key
        FROM
        (
            SELECT
                uid,
                raw_tag,
                recall_dt,
                biz_date,
                multiIf(
                    raw_tag LIKE 'recall_phone%', '智能电话',
                    raw_tag LIKE '%wechat%', '微信',
                    raw_tag LIKE 'recall_push%', '特殊push',
                    raw_tag LIKE '%push%', '普通push',
                    raw_tag LIKE '%fumeiti%', '视频短信',
                    raw_tag LIKE 'recall_%', '文本短信',
                    '其他'
                ) AS raw_channel,
                multiIf(
                    raw_tag LIKE 'recall_phone%', 1,
                    raw_tag LIKE '%wechat%', 2,
                    raw_tag LIKE 'recall_push%', 3,
                    raw_tag LIKE '%push%', 4,
                    raw_tag LIKE '%fumeiti%', 5,
                    raw_tag LIKE 'recall_%', 6,
                    7
                ) AS channel_priority
            FROM
            (
                SELECT
                    recall_data.uid AS uid,
                    recall_data.tag AS raw_tag,
                    recall_data.d AS recall_dt,
                    recall_data.biz_date AS biz_date
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
                        recall_base.tag AS tag,
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
                            r.d AS d
                        FROM
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                d
                            FROM dwm.dw_growth_user_active_di
                            PREWHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
                            WHERE is_silent_30d = 1
                        ) AS su
                        INNER JOIN
                        (
                            SELECT
                                toUInt64(uid) AS uid,
                                tag,
                                d
                            FROM dwm.dw_growth_user_sms_recall_di
                            WHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
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
                          AND d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19') + 1
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
                    PREWHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
                    WHERE is_sms_touch = 1
                ) AS active_data
                    ON recall_data.uid = active_data.uid
                   AND recall_data.biz_date = active_data.biz_date
                WHERE recall_data.biz_date BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
            )
        )
    )
    GROUP BY
        biz_date,
        uid
) AS r
ANY LEFT JOIN
(
    SELECT
        toUInt64(uid) AS uid,
        d,
        tag,
        1 AS has_sms_record,
        max(is_send_success = 1) AS is_send_success
    FROM dws.dw_sms_di
    WHERE d BETWEEN toDate('2026-05-17') AND toDate('2026-05-19')
      AND (
             tag LIKE 'recall%'
          OR tag LIKE 'bonus%'
          OR tag LIKE '%mengwang%'
      )
      AND tag NOT LIKE 'recall_today_1_send_msg%'
      AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
    GROUP BY
        uid,
        d,
        tag
) AS s
    ON r.uid = s.uid
   AND r.selected_recall_dt = s.d
   AND r.selected_tag = s.tag
WHERE r.selected_channel = '文本短信'
GROUP BY r.biz_date
ORDER BY d;
