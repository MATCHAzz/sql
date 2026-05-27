/*
看板4：召回用户次留情况监控

次留任务 tag：recall_remain%

口径：
1. 业务日期取 toDate('2026-01-01') 到 yesterday()。
2. 前一天召回用户数按周报四类渠道召回口径，按天去重 uid：
   - 召回明细来自 dwm.dw_growth_user_sms_recall_di。
   - 只计入文本短信、智能电话、特殊 push、微信模板消息。
   - 排除 recall_remain% 次留任务自身，避免把次留短信召回反算进前一天召回分母。
   - 智能电话召回 tag LIKE 'recall_phone%' 且命中次日复播/复呼成功明细时，业务日期按 d - 1 归因。
   - 只保留召回明细日期当天 is_silent_30d = 1 的用户。
   - 只保留归因业务日期当天 is_sms_touch = 1 的用户。
   - 不额外叠加普通 push 独立补充行。
   - 注意：这里是按天去重 uid；如果拿周报按通道/人群/运营商等多维行求和的结果对比，数值可能不一致。
3. 次留任务发送率 = recall_remain% SQL 用户数 / 前一天召回用户数。
   - SQL 用户数来自 dws.dw_sms_di 中 tag LIKE 'recall_remain%' 的去重 uid，只看短信明细。
4. 次留任务发送成功率 = recall_remain% 发送成功用户数 / recall_remain% 触达平台发送用户数。
   - 触达平台发送、发送成功来自 dws.dw_sms_di。
5. 当日召回率 = 当日召回用户数 / recall_remain% 发送成功用户数。
   - 当日召回用户来自 dws.dw_sms_di.is_recall = 1，并限定在 recall_remain% 发送成功用户内。
   - 已用「看板/召回用户次留活跃口径对比.sql」验证：recall_remain% 发送成功用户上，is_recall 与 uid + d 关联 dws.dw_dau 的活跃口径一致。
6. 人群来自 dim.dim_user：
   - 新经济尾部兼容历史命名 '新经济腰尾'。
   - 学生来自 five_class = '学生'。
   - 其他用户 = 非新经济头部、非新经济尾部/腰尾、非传统主流一线、非学生。

说明：
看板权限解析会把命名 CTE 误判成真实表，所以这里不用命名 CTE。
*/

SELECT
    date_data.d AS d,
    date_data.d - 1 AS `前一天召回归因日期`,
    ifNull(prev_recall.prev_recall_user_cnt, 0) AS `前一天召回用户数`,
    ifNull(task_sql.task_sql_user_cnt, 0) AS `recall_remain SQL用户数`,
    round(ifNull(task_sql.task_sql_user_cnt, 0) / nullIf(ifNull(prev_recall.prev_recall_user_cnt, 0), 0), 4) AS `次留任务发送率`,
    round(ifNull(sms_metrics.task_send_success_user_cnt, 0) / nullIf(ifNull(sms_metrics.task_send_user_cnt, 0), 0), 4) AS `次留任务发送成功率`,
    round(ifNull(sms_metrics.task_recall_user_cnt, 0) / nullIf(ifNull(sms_metrics.task_send_success_user_cnt, 0), 0), 4) AS `次留短信总召回率`,
    round(ifNull(sms_metrics.new_economy_head_recall_user_cnt, 0) / nullIf(ifNull(sms_metrics.new_economy_head_send_success_user_cnt, 0), 0), 4) AS `新经济头部用户召回率`,
    round(ifNull(sms_metrics.new_economy_tail_recall_user_cnt, 0) / nullIf(ifNull(sms_metrics.new_economy_tail_send_success_user_cnt, 0), 0), 4) AS `新经济尾部用户召回率`,
    round(ifNull(sms_metrics.traditional_first_tier_recall_user_cnt, 0) / nullIf(ifNull(sms_metrics.traditional_first_tier_send_success_user_cnt, 0), 0), 4) AS `传统主流一线召回率`,
    round(ifNull(sms_metrics.student_recall_user_cnt, 0) / nullIf(ifNull(sms_metrics.student_send_success_user_cnt, 0), 0), 4) AS `学生召回率`,
    round(ifNull(sms_metrics.other_recall_user_cnt, 0) / nullIf(ifNull(sms_metrics.other_send_success_user_cnt, 0), 0), 4) AS `其他用户召回率`
FROM
(
    SELECT toDate(arrayJoin(range(toUInt32(toDate('2026-01-01')), toUInt32(yesterday()) + 1))) AS d
) AS date_data
ANY LEFT JOIN
(
    /* 前一天召回用户数：按周报四类渠道召回口径 */
    SELECT
        recall_data.biz_date + 1 AS d,
        uniqExact(recall_data.uid) AS prev_recall_user_cnt
    FROM
    (
        SELECT
            recall_base.uid AS uid,
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
            ) AS silent_user
            INNER JOIN
            (
                SELECT
                    toUInt64(uid) AS uid,
                    tag,
                    d
                FROM dwm.dw_growth_user_sms_recall_di
                WHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
                  AND (
                         tag LIKE 'recall_phone%'
                      OR tag LIKE '%wechat%'
                      OR tag LIKE 'recall_push%'
                      OR (
                             tag LIKE 'recall_%'
                         AND tag NOT LIKE 'recall_phone%'
                         AND tag NOT LIKE 'recall_push%'
                         AND tag NOT LIKE '%wechat%'
                         AND tag NOT LIKE '%fumeiti%'
                      )
                  )
                  AND tag NOT LIKE 'recall_today_1_send_msg%'
                  AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                  AND tag NOT LIKE 'recall_remain%'
            ) AS r
                ON silent_user.uid = r.uid
               AND silent_user.d = r.d
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
    GROUP BY recall_data.biz_date
) AS prev_recall
    ON date_data.d = prev_recall.d
ANY LEFT JOIN
(
    /* recall_remain 短信 SQL 用户数 */
    SELECT
        d,
        uniqExact(uid) AS task_sql_user_cnt
    FROM
    (
        SELECT
            sms_task.uid AS uid,
            sms_task.d AS d
        FROM
        (
            SELECT
                toUInt64(uid) AS uid,
                d
            FROM dws.dw_sms_di
            WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
              AND tag LIKE 'recall_remain%'
              AND toUInt64(uid) != 0
        ) AS sms_task
        ANY INNER JOIN
        (
            SELECT
                prev_user_detail.uid AS uid,
                prev_user_detail.d AS d
            FROM
            (
                SELECT
                    recall_data.uid AS uid,
                    recall_data.biz_date + 1 AS d
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
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
                            ) AS silent_user
                            INNER JOIN
                            (
                                SELECT
                                    toUInt64(uid) AS uid,
                                    tag,
                                d
                            FROM dwm.dw_growth_user_sms_recall_di
                            WHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
                              AND (
                                     tag LIKE 'recall_phone%'
                                  OR tag LIKE '%wechat%'
                                  OR tag LIKE 'recall_push%'
                                  OR (
                                         tag LIKE 'recall_%'
                                     AND tag NOT LIKE 'recall_phone%'
                                     AND tag NOT LIKE 'recall_push%'
                                     AND tag NOT LIKE '%wechat%'
                                     AND tag NOT LIKE '%fumeiti%'
                                  )
                              )
                              AND tag NOT LIKE 'recall_today_1_send_msg%'
                              AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                              AND tag NOT LIKE 'recall_remain%'
                        ) AS r
                            ON silent_user.uid = r.uid
                           AND silent_user.d = r.d
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
                    recall_data.uid
            ) AS prev_user_detail
            GROUP BY
                prev_user_detail.uid,
                prev_user_detail.d
        ) AS prev_user
            ON sms_task.uid = prev_user.uid
           AND sms_task.d = prev_user.d
        GROUP BY
            sms_task.d,
            sms_task.uid
    ) AS task_sql_detail
    GROUP BY d
) AS task_sql
    ON date_data.d = task_sql.d
ANY LEFT JOIN
(
    /* recall_remain 触达平台发送、发送成功、当日召回 */
    SELECT
        s.d AS d,
        uniqExact(s.uid) AS task_send_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1) AS task_send_success_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND s.recall_active_flag = 1) AS task_recall_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND user_info.seven_class = '新经济头部') AS new_economy_head_send_success_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND s.recall_active_flag = 1 AND user_info.seven_class = '新经济头部') AS new_economy_head_recall_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND user_info.seven_class IN ('新经济尾部', '新经济腰尾')) AS new_economy_tail_send_success_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND s.recall_active_flag = 1 AND user_info.seven_class IN ('新经济尾部', '新经济腰尾')) AS new_economy_tail_recall_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND user_info.seven_class = '传统主流一线') AS traditional_first_tier_send_success_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND s.recall_active_flag = 1 AND user_info.seven_class = '传统主流一线') AS traditional_first_tier_recall_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND user_info.five_class = '学生') AS student_send_success_user_cnt,
        uniqExactIf(s.uid, s.send_success_flag = 1 AND s.recall_active_flag = 1 AND user_info.five_class = '学生') AS student_recall_user_cnt,
        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND ifNull(user_info.seven_class, '未知') NOT IN ('新经济头部', '新经济尾部', '新经济腰尾', '传统主流一线')
            AND ifNull(user_info.five_class, '未知') != '学生'
        ) AS other_send_success_user_cnt,
        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND s.recall_active_flag = 1
            AND ifNull(user_info.seven_class, '未知') NOT IN ('新经济头部', '新经济尾部', '新经济腰尾', '传统主流一线')
            AND ifNull(user_info.five_class, '未知') != '学生'
        ) AS other_recall_user_cnt
    FROM
    (
        SELECT
            sms_send.uid AS uid,
            sms_send.d AS d,
            max(if(sms_send.is_send_success = 1, 1, 0)) AS send_success_flag,
            max(if(sms_send.is_send_success = 1 AND ifNull(sms_send.is_recall, 0) = 1, 1, 0)) AS recall_active_flag
        FROM
        (
            SELECT
                toUInt64(uid) AS uid,
                d,
                is_send_success,
                is_recall
            FROM dws.dw_sms_di
            WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
              AND tag LIKE 'recall_remain%'
              AND toUInt64(uid) != 0
        ) AS sms_send
        ANY INNER JOIN
        (
            SELECT
                prev_user_detail.uid AS uid,
                prev_user_detail.d AS d
            FROM
            (
                SELECT
                    recall_data.uid AS uid,
                    recall_data.biz_date + 1 AS d
                FROM
                (
                    SELECT
                        recall_base.uid AS uid,
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
                            ) AS silent_user
                            INNER JOIN
                            (
                                SELECT
                                    toUInt64(uid) AS uid,
                                    tag,
                                d
                            FROM dwm.dw_growth_user_sms_recall_di
                            WHERE d BETWEEN toDate('2026-01-01') - 1 AND yesterday()
                              AND (
                                     tag LIKE 'recall_phone%'
                                  OR tag LIKE '%wechat%'
                                  OR tag LIKE 'recall_push%'
                                  OR (
                                         tag LIKE 'recall_%'
                                     AND tag NOT LIKE 'recall_phone%'
                                     AND tag NOT LIKE 'recall_push%'
                                     AND tag NOT LIKE '%wechat%'
                                     AND tag NOT LIKE '%fumeiti%'
                                  )
                              )
                              AND tag NOT LIKE 'recall_today_1_send_msg%'
                              AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                              AND tag NOT LIKE 'recall_remain%'
                        ) AS r
                            ON silent_user.uid = r.uid
                           AND silent_user.d = r.d
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
                    recall_data.uid
            ) AS prev_user_detail
            GROUP BY
                prev_user_detail.uid,
                prev_user_detail.d
        ) AS prev_user
            ON sms_send.uid = prev_user.uid
           AND sms_send.d = prev_user.d
        GROUP BY
            sms_send.d,
            sms_send.uid
    ) AS s
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            any(ifNull(nullIf(trimBoth(toString(seven_class)), ''), '未知')) AS seven_class,
            any(ifNull(nullIf(trimBoth(toString(five_class)), ''), '未知')) AS five_class
        FROM dim.dim_user
        GROUP BY uid
    ) AS user_info
        ON s.uid = user_info.uid
    GROUP BY s.d
) AS sms_metrics
    ON date_data.d = sms_metrics.d
ORDER BY date_data.d DESC;
