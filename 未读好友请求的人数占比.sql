/*
逻辑说明：
1. 先取昨日业务日期的召回用户：
   - 召回明细来自 dwm.dw_growth_user_sms_recall_di，取 d 在 yesterday() 到 today() 的记录。
   - 只保留对应日期在 dwm.dw_growth_user_active_di 中 is_silent_30d = 1 的用户。
   - 智能电话召回 tag LIKE 'recall_phone%' 且命中次日复播/复呼成功明细时，业务日期按 d - 1 归因；其余召回按 d 归因。
   - 再和昨日 is_sms_touch = 1 的用户按 uid、biz_date 关联，只保留 biz_date = yesterday() 的召回触达用户。
   - 召回 tag 范围：tag LIKE 'recall%' OR tag LIKE 'bonus%' OR tag LIKE '%mengwang%'。
   - 排除 tag：recall_today_1_send_msg%、recall_after_3_send_msg_with_equity%。
   - LIMIT 1 BY uid，保证每个召回用户只保留一条召回记录；若同一用户有多条记录，渠道和好友请求短信标签按保留下来的那条记录判断。

2. 渠道口径：
   - tag LIKE 'recall_phone%'：智能电话
   - tag LIKE '%wechat%'：微信
   - tag LIKE 'recall_push%'：特殊push
   - tag LIKE '%fumeiti%'：视频短信
   - tag LIKE 'recall_%'：文本短信
   - 其他：其他
   - 最终同时输出各渠道和“整体”，通过 arrayJoin([channel, '整体']) 生成。

3. 好友请求召回短信口径：
   - 好友请求召回短信：tag LIKE '%friend_request%'。
   - 非好友请求召回短信：tag NOT LIKE '%friend_request%'，在 SQL 中用 is_friend_request_recall_sms = 0 表示。

4. 用户是否有好友请求口径：
   - 好友请求数据来自 dwd.dw_network_add_friend_di。
   - 统计近 180 天 d 和 req_date 范围内，accepted_type IN (0, 2) 的 uid2。
   - 按 uid2 聚合为 pending_request_cnt；pending_request_cnt > 0 即认为该召回用户有好友请求。

5. 输出指标：
   - 召回用户数：去重后的召回用户数。
   - 非好友请求召回短信的召回人数：召回 tag 不命中 %friend_request% 的用户数。
   - 召回人数中的有好友请求的人数：召回用户中 pending_request_cnt > 0 的用户数。
   - 非好友请求召回短信的召回人数中有好友请求的人数：非好友请求召回短信用户中 pending_request_cnt > 0 的用户数。
*/

SELECT
    group_channel AS `渠道`,
    count() AS `召回用户数`,
    countIf(is_friend_request_recall_sms = 0) AS `非好友请求召回短信的召回人数`,
    countIf(pending_request_cnt > 0) AS `召回人数中的有好友请求的人数`,
    countIf(is_friend_request_recall_sms = 0 AND pending_request_cnt > 0) AS `非好友请求召回短信的召回人数中有好友请求的人数`
FROM
(
    SELECT
        uid,
        arrayJoin([channel, '整体']) AS group_channel,
        is_friend_request_recall_sms,
        pending_request_cnt
    FROM
    (
        SELECT
            recalled_users.uid,
            recalled_users.channel,
            recalled_users.is_friend_request_recall_sms,
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
                END AS channel,
                tag LIKE '%friend_request%' AS is_friend_request_recall_sms  -- 判断是否是好友请求相关的召回短信
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
            -- accepted_type 未读tag 0是有通知的待处理，2是没有通知的待处理
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
