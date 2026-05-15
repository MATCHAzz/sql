SELECT
    group_channel AS `渠道`,
    count() AS `召回用户数`,
    countIf(pending_request_cnt > 0) AS `有待处理好友请求用户数`,
    ifNull(
        round(
            countIf(pending_request_cnt > 0) / nullIf(count(), 0),
            4
        ),
        0
    ) AS `有待处理好友请求用户占比`,
    sum(pending_request_cnt) AS `待处理好友请求总数`
FROM
(
    SELECT
        uid,
        arrayJoin([channel, '整体']) AS group_channel,
        pending_request_cnt
    FROM
    (
        SELECT
            recalled_users.uid,
            recalled_users.channel,
            ifNull(pending_request_users.pending_request_cnt, 0) AS pending_request_cnt
        FROM
        (
            SELECT
                uid,
                CASE
                    WHEN tag LIKE 'recall_phone%' THEN '智能电话'
                    WHEN tag LIKE '%wechat%' THEN '微信'
                    WHEN tag LIKE 'recall_push%' THEN '特殊push'
                    WHEN tag LIKE '%fumeiti%' THEN '视频短信'
                    WHEN tag LIKE 'recall_%' THEN '文本短信'
                    ELSE '其他'
                END AS channel
            FROM
            (
                SELECT
                    uid,
                    tag,
                    if(
                        tag LIKE 'recall_phone%' AND nextdaycall = 1,
                        d - 1,
                        d
                    ) AS biz_date
                FROM
                (
                    SELECT
                        uid,
                        tag,
                        d
                    FROM dwm.dw_growth_user_sms_recall_di
                    WHERE d BETWEEN yesterday() AND today()
                        AND (d, uid) IN
                        (
                            SELECT
                                d,
                                uid
                            FROM dwm.dw_growth_user_active_di
                            PREWHERE d BETWEEN yesterday() AND today()
                                AND is_silent_30d = 1
                        )
                ) AS recall_base
                ANY LEFT JOIN
                (
                    SELECT
                        toUInt32(uid) AS uid,
                        d,
                        1 AS nextdaycall
                    FROM dwd.dw_growth_sms_smartphone_call_di
                    WHERE (task_name LIKE '%复播' OR task_name LIKE '%次日复%')
                        AND d >= yesterday() - 1
                        AND
                        (
                            (type = '容联' AND reason = 0)
                            OR (type = '百应' AND reason = 1)
                            OR (type = '智齿' AND reason = 2)
                            OR (type = '中通天鸿' AND reason = 201)
                            OR (type = '泰迪' AND reason = 1)
                            OR (type = '一知' AND reason = 1)
                            OR (type = 'jumeng' AND reason = 1)
                            OR (type = 'aliyun_ai' AND reason = 1)
                        )
                ) AS call_detail USING (uid, d)
            ) AS recall_data
            ANY INNER JOIN
            (
                SELECT
                    uid,
                    d AS biz_date
                FROM dwm.dw_growth_user_active_di
                WHERE d = yesterday()
                    AND is_sms_touch = 1
            ) AS active_data USING (uid, biz_date)
            WHERE biz_date = yesterday()
                AND
                (
                    tag LIKE 'recall%'
                    OR tag LIKE 'bonus%'
                    OR tag LIKE '%mengwang%'
                )
                AND tag NOT LIKE 'recall_today_1_send_msg%'
                AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
            LIMIT 1 BY uid
        ) AS recalled_users
        LEFT JOIN
        (
            SELECT
                toUInt32(uid2) AS uid,
                count() AS pending_request_cnt
            FROM dwd.dw_network_add_friend_di
            PREWHERE d BETWEEN today() - 180 AND today()
            WHERE accepted_type IN (0, 2)
                AND req_date BETWEEN today() - 180 AND today()
            GROUP BY uid
        ) AS pending_request_users USING (uid)
    ) AS user_result
) AS group_result
GROUP BY group_channel
ORDER BY
    group_channel = '整体' DESC,
    count() DESC
