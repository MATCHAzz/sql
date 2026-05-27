/*
召回用户次留发送率分渠道排查

目的：
拆分前一天全渠道有效召回用户的渠道来源，观察各渠道用户第二天是否进入 recall_remain% 短信任务。

解读：
1. 如果“智能电话”的 prev_recall_user_cnt 占比很高，但 task_sql_user_cnt 也高，
   说明电话召回用户第二天也大量进入了次留短信任务，整体发送率高是合理的。
2. 如果“智能电话”的 prev_recall_user_cnt 很低，说明当前前一天召回分母可能没有完整纳入电话召回。
3. 看板权限解析会把命名 CTE 误判成真实表，所以这里不用命名 CTE。
*/

SELECT
    r.d AS d,
    r.channel AS `前一天召回渠道`,
    r.prev_recall_user_cnt AS `前一天召回用户数`,
    ifNull(t.task_sql_user_cnt, 0) AS `次留短信SQL用户数`,
    round(ifNull(t.task_sql_user_cnt, 0) / nullIf(r.prev_recall_user_cnt, 0), 4) AS `次留任务发送率`
FROM
(
    SELECT
        prev_user.biz_date + 1 AS d,
        prev_user.channel AS channel,
        uniqExact(prev_user.uid) AS prev_recall_user_cnt
    FROM
    (
        SELECT
            recall_data.uid AS uid,
            recall_data.biz_date AS biz_date,
            multiIf(
                recall_data.tag LIKE 'recall_phone%', '智能电话',
                recall_data.tag LIKE '%wechat%', '微信',
                recall_data.tag LIKE 'recall_push%', '特殊push',
                recall_data.tag LIKE '%push%', '普通push',
                recall_data.tag LIKE '%fumeiti%', '视频短信',
                recall_data.tag LIKE 'recall_%', '文本短信',
                '其他'
            ) AS channel
        FROM
        (
            SELECT
                recall_base.uid AS uid,
                recall_base.tag AS tag,
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
                    PREWHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
                    WHERE is_silent_30d = 1
                ) AS su
                INNER JOIN
                (
                    SELECT
                        toUInt64(uid) AS uid,
                        tag,
                        d
                    FROM dwm.dw_growth_user_sms_recall_di
                    WHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
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
                  AND d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
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
            PREWHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday() - 1
            WHERE is_sms_touch = 1
        ) AS active_data
            ON recall_data.uid = active_data.uid
           AND recall_data.biz_date = active_data.biz_date
        WHERE recall_data.biz_date BETWEEN toDate('2026-01-01') - 1 AND yesterday() - 1
        GROUP BY
            recall_data.biz_date,
            recall_data.uid,
            channel
    ) AS prev_user
    GROUP BY
        d,
        channel
) AS r
ANY LEFT JOIN
(
    SELECT
        prev_user.biz_date + 1 AS d,
        prev_user.channel AS channel,
        uniqExact(sms_task.uid) AS task_sql_user_cnt
    FROM
    (
        SELECT
            toUInt64(uid) AS uid,
            d
        FROM dws.dw_sms_di
        WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
          AND tag LIKE 'recall_remain%'
          AND toUInt64(uid) != 0
        GROUP BY
            d,
            uid
    ) AS sms_task
    ANY INNER JOIN
    (
        SELECT
            recall_data.uid AS uid,
            recall_data.biz_date AS biz_date,
            multiIf(
                recall_data.tag LIKE 'recall_phone%', '智能电话',
                recall_data.tag LIKE '%wechat%', '微信',
                recall_data.tag LIKE 'recall_push%', '特殊push',
                recall_data.tag LIKE '%push%', '普通push',
                recall_data.tag LIKE '%fumeiti%', '视频短信',
                recall_data.tag LIKE 'recall_%', '文本短信',
                '其他'
            ) AS channel
        FROM
        (
            SELECT
                recall_base.uid AS uid,
                recall_base.tag AS tag,
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
                    PREWHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
                    WHERE is_silent_30d = 1
                ) AS su
                INNER JOIN
                (
                    SELECT
                        toUInt64(uid) AS uid,
                        tag,
                        d
                    FROM dwm.dw_growth_user_sms_recall_di
                    WHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
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
                  AND d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
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
            PREWHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday() - 1
            WHERE is_sms_touch = 1
        ) AS active_data
            ON recall_data.uid = active_data.uid
           AND recall_data.biz_date = active_data.biz_date
        WHERE recall_data.biz_date BETWEEN toDate('2026-01-01') - 1 AND yesterday() - 1
        GROUP BY
            recall_data.biz_date,
            recall_data.uid,
            channel
    ) AS prev_user
        ON sms_task.uid = prev_user.uid
       AND sms_task.d = prev_user.biz_date + 1
    GROUP BY
        d,
        channel
) AS t
    ON r.d = t.d
   AND r.channel = t.channel
ORDER BY
    r.d DESC,
    `前一天召回用户数` DESC;
