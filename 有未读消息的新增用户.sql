WITH
-- 1. 排除官方账号 / 小助手 / 会员服务 / IM 助手
exclude_sender AS (
    SELECT DISTINCT uid
    FROM (
        SELECT
            toUInt64(uid) AS uid
        FROM dim.dim_user_tag_bak
        WHERE
            (
                ifNull(trimBoth(current_position), '') = '官方账号'
                AND positionUTF8(ifNull(real_name, ''), '小助手') > 0
            )
            OR (
                ifNull(trimBoth(current_position), '') = '官方账号'
                AND positionUTF8(ifNull(real_name, ''), '脉脉') > 0
            )
            OR positionUTF8(ifNull(real_name, ''), '会员服务') > 0
            OR (
                ifNull(trimBoth(current_position), '') = ''
                AND ifNull(trimBoth(real_name), '') = '脉脉'
            )

        UNION ALL

        -- IM 小助手
        SELECT
            toUInt64(uid) AS uid
        FROM dim.dim_im_assistant
    )
),

-- 2. 排除管理层 / HR / 猎头等新用户
exclude_new_user AS (
    SELECT DISTINCT
        toUInt64(uid) AS uid
    FROM dim.dim_user
    WHERE ifNull(company_id, 0) <> 1
      AND (
            arrayExists(
                x -> positionUTF8(lowerUTF8(ifNull(current_position, '')), x) > 0,
                [
                    '行长', '院长', '部长', '科长', '处长', '局长', '厅长', '市长', '省长',
                    '系长', '校长', '厂长', '会长', '所长', '理事长', '秘书长', '园长',
                    '总经办', '主编', '主任', '总编', '制片人', '导演', '店长',
                    '总裁', '总经理', '创始人', '首席', '董事', '董事总经理', '董事长',
                    '执行董事', '事业部总经理', '法人', '书记', '分总',
                    'hr', '人力资源', '招聘', '合伙人', '负责人',
                    'cbo', 'cdo', 'ceo', 'cfo', 'cho', 'cio', 'cso', 'cto',
                    'cxo', 'cmo', 'coo', 'director', 'gm', 'head', 'vp', 'svp', 'evp'
                ]
            )
            OR arrayExists(
                x -> positionUTF8(lowerUTF8(ifNull(lv3_major, '')), x) > 0,
                [
                    '行长', '院长', '部长', '科长', '处长', '局长', '厅长', '市长', '省长',
                    '系长', '校长', '厂长', '会长', '所长', '理事长', '秘书长', '园长',
                    '总经办', '主编', '主任', '总编', '制片人', '导演', '店长',
                    '总裁', '总经理', '创始人', '首席', '董事', '董事总经理', '董事长',
                    '执行董事', '事业部总经理', '法人', '书记', '分总',
                    'hr', '人力资源', '招聘', '合伙人', '负责人',
                    'cbo', 'cdo', 'ceo', 'cfo', 'cho', 'cio', 'cso', 'cto',
                    'cxo', 'cmo', 'coo', 'director', 'gm', 'head', 'vp', 'svp', 'evp'
                ]
            )
            OR ifNull(is_hr, 0) = 1
            OR ifNull(is_headhunting, 0) = 1
      )
),

-- 3. 昨天的 +1 新用户
new_user AS (
    SELECT
        toUInt64(u.uid) AS uid,
        yesterday() AS day
    FROM dim.dim_user u

    GLOBAL LEFT JOIN exclude_new_user e
        ON toUInt64(u.uid) = e.uid

    WHERE toDate(u.register_complete_date) = yesterday() - 1
      AND ifNull(e.uid, 0) = 0

    GROUP BY
        uid,
        day
),

-- 4. 今天有未读消息的用户，并取最新一条未读消息发送方
message_notify_user AS (
    SELECT
        toUInt64(m.dst_uid) AS uid,
        m.d AS day,

        uniqExact(m.mid) AS msg_notify_cnt,

        max(m.send_ts) AS latest_send_ts,

        argMax(toUInt64(m.src_uid), m.send_ts) AS max_ts_uid

    FROM dwm.dw_im_message_life_cycle_di m

    GLOBAL LEFT JOIN exclude_sender e
        ON toUInt64(m.src_uid) = e.uid

    WHERE m.d = yesterday()
      AND m.read_ts = toDateTime(0)
      AND toUInt64(m.src_uid) != 0
      AND ifNull(e.uid, 0) = 0

    GROUP BY
        uid,
        day

    HAVING uniqExact(m.mid) >= 1
)

SELECT
    n.uid,
    m.msg_notify_cnt AS `消息通知条数`,
    m.max_ts_uid AS `最新消息发送方uid`,
    sender.real_name AS `最新消息发送方姓名`,
    sender.current_company AS `最新消息发送方公司`,
    sender.current_position AS `最新消息发送方职位`
FROM new_user n

ANY INNER JOIN message_notify_user m
    ON n.uid = m.uid
   AND n.day = m.day

LEFT JOIN dim.dim_user sender
    ON m.max_ts_uid = toUInt64(sender.uid)

ORDER BY
    m.msg_notify_cnt DESC,
    n.uid;