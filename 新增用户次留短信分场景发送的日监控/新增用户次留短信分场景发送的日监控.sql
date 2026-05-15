WITH
    addDays(yesterday(), -29) AS start_dt,
    yesterday() AS end_dt

SELECT
    dt AS d,
    `sql量级`,

    `触达平台下发量级`,
    round(`触达平台下发量级` / nullIf(`sql量级`, 0), 4) AS `触达平台下发占比`,

    `触达平台返回成功量级`,
    round(`触达平台返回成功量级` / nullIf(`触达平台下发量级`, 0), 4) AS `触达平台成功率`,
    round(`触达平台返回成功活跃量级` / nullIf(`触达平台返回成功量级`, 0), 4) AS `触达平台返回成功活跃率`,

    `内推场景发送成功量级`,
    round(`内推场景发送成功量级` / nullIf(`触达平台返回成功量级`, 0), 4) AS `内推场景下发占比`,
    round(`内推场景活跃量级` / nullIf(`内推场景发送成功量级`, 0), 4) AS `内推场景活跃率`,

    `最近访客场景发送成功量级`,
    round(`最近访客场景发送成功量级` / nullIf(`触达平台返回成功量级`, 0), 4) AS `最近访客场景下发占比`,
    round(`最近访客场景活跃量级` / nullIf(`最近访客场景发送成功量级`, 0), 4) AS `最近访客场景活跃率`,

    `好友请求场景发送成功量级`,
    round(`好友请求场景发送成功量级` / nullIf(`触达平台返回成功量级`, 0), 4) AS `好友请求场景下发占比`,
    round(`好友请求场景活跃量级` / nullIf(`好友请求场景发送成功量级`, 0), 4) AS `好友请求场景活跃率`,

    `兜底文案发送成功量级`,
    round(`兜底文案发送成功量级` / nullIf(`触达平台返回成功量级`, 0), 4) AS `兜底文案下发占比`,
    round(`兜底文案活跃量级` / nullIf(`兜底文案发送成功量级`, 0), 4) AS `兜底文案活跃率`
FROM
(
    SELECT
        base.dt AS dt,
        uniqExact(base.uid) AS `sql量级`,

        uniqExactIf(base.uid, ifNull(sms.is_touched, 0) = 1) AS `触达平台下发量级`,
        uniqExactIf(base.uid, ifNull(sms.is_touched, 0) = 1 AND ifNull(active.is_active, 0) = 1) AS `触达平台下发活跃量级`,

        uniqExactIf(base.uid, ifNull(sms.is_send_success, 0) = 1) AS `触达平台返回成功量级`,
        uniqExactIf(base.uid, ifNull(sms.is_send_success, 0) = 1 AND ifNull(active.is_active, 0) = 1) AS `触达平台返回成功活跃量级`,

        uniqExactIf(base.uid, ifNull(sms.is_inner_success, 0) = 1) AS `内推场景发送成功量级`,
        uniqExactIf(base.uid, ifNull(sms.is_inner_success, 0) = 1 AND ifNull(active.is_active, 0) = 1) AS `内推场景活跃量级`,

        uniqExactIf(base.uid, ifNull(sms.is_recent_visitor_success, 0) = 1) AS `最近访客场景发送成功量级`,
        uniqExactIf(base.uid, ifNull(sms.is_recent_visitor_success, 0) = 1 AND ifNull(active.is_active, 0) = 1) AS `最近访客场景活跃量级`,

        uniqExactIf(base.uid, ifNull(sms.is_request_success, 0) = 1) AS `好友请求场景发送成功量级`,
        uniqExactIf(base.uid, ifNull(sms.is_request_success, 0) = 1 AND ifNull(active.is_active, 0) = 1) AS `好友请求场景活跃量级`,

        uniqExactIf(base.uid, ifNull(sms.is_default_success, 0) = 1) AS `兜底文案发送成功量级`,
        uniqExactIf(base.uid, ifNull(sms.is_default_success, 0) = 1 AND ifNull(active.is_active, 0) = 1) AS `兜底文案活跃量级`
    FROM
    (
        SELECT
            addDays(new_user.d, 1) AS dt,
            new_user.uid AS uid
        FROM
        (
            SELECT
                d,
                uid
            FROM dws.dw_dau
            WHERE d BETWEEN addDays(start_dt, -1) AND addDays(end_dt, -1)
              AND is_new_user = 1
            GROUP BY d, uid
        ) AS new_user
        LEFT JOIN
        (
            SELECT
                toDate(uptime) AS d,
                uid,
                1 AS is_delete
            FROM mysqldump.user_auth_deleted
            WHERE toDate(uptime) BETWEEN addDays(start_dt, -1) AND addDays(end_dt, -1)
            GROUP BY d, uid
        ) AS deleted_user
            ON new_user.d = deleted_user.d
           AND new_user.uid = deleted_user.uid
        WHERE ifNull(deleted_user.is_delete, 0) = 0
    ) AS base
    ANY LEFT JOIN
    (
        SELECT
            dt,
            uid,
            1 AS is_touched,
            max(raw_is_send_success = 1) AS is_send_success,
            max(if(raw_is_send_success = 1 AND scene = '内推场景', 1, 0)) AS is_inner_success,
            max(if(raw_is_send_success = 1 AND scene = '最近访客场景', 1, 0)) AS is_recent_visitor_success,
            max(if(raw_is_send_success = 1 AND scene = '好友请求场景', 1, 0)) AS is_request_success,
            max(if(raw_is_send_success = 1 AND scene = '兜底文案', 1, 0)) AS is_default_success
        FROM
        (
            SELECT
                dt,
                uid,
                raw_is_send_success,
                multiIf(
                    tag_l LIKE '%doudi%',
                    '兜底文案',

                    tag_l LIKE '%newuser%',
                    '内推场景',

                    tag_l LIKE '%real-visitor%' OR tag_l LIKE '%vistor%' OR tag_l LIKE '%visitor%',
                    '最近访客场景',

                    tag_l LIKE '%request%',
                    '好友请求场景',

                    ''
                ) AS scene
            FROM
            (
                SELECT
                    d AS dt,
                    uid,
                    is_send_success AS raw_is_send_success,
                    lowerUTF8(ifNull(tag, '')) AS tag_l
                FROM dws.dw_sms_di
                WHERE d BETWEEN start_dt AND end_dt
                  AND tag LIKE 'recall_1day%'
                  AND tag NOT LIKE '%opportunity%'
                GROUP BY dt, uid, raw_is_send_success, tag_l
            ) AS sms_detail
        ) AS sms_scene
        GROUP BY dt, uid
    ) AS sms
        ON base.dt = sms.dt
       AND base.uid = sms.uid
    ANY LEFT JOIN
    (
        SELECT
            d AS dt,
            uid,
            1 AS is_active
        FROM dws.dw_dau
        WHERE d BETWEEN start_dt AND end_dt
          AND is_puppet = 0
        GROUP BY dt, uid
    ) AS active
        ON base.dt = active.dt
       AND base.uid = active.uid
    GROUP BY base.dt
)
ORDER BY d DESC
