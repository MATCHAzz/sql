/*
口径：
1. t 日期默认取最近 30 个已完整观察到 t+6 的日期：
   - start_dt = yesterday() - 35
   - end_dt = yesterday() - 6
   如需看其他时间段，调整下面 WITH 里的 start_dt / end_dt。
2. 分母：t-1 注册完成的新用户，并排除管理层 / HR / 猎头等人群。
3. 好友申请：
   - 来自 dwd.dw_network_add_friend_di。
   - uid2 为收到好友申请的新用户，uid 为发起好友申请的用户。
   - 统计 req_date 在 t 或 t+6 当天的好友申请。
   - 排除官方账号 / 小助手 / 会员服务 / IM 助手发起的好友申请。
4. 输出：
   - t 天好友申请数量 >= 1 的用户数及占比。
   - t+6 天好友申请数量 >= 1 的用户数及占比。
*/

WITH
    addDays(yesterday(), -35) AS start_dt,
    addDays(yesterday(), -6) AS end_dt,

exclude_sender AS (
    SELECT DISTINCT uid
    FROM
    (
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
            OR positionUTF8(ifNull(real_name, ''), '小脉同学') > 0
            
        UNION ALL

        SELECT
            toUInt64(uid) AS uid
        FROM dim.dim_im_assistant
    )
),

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

new_user_base AS (
    SELECT
        toUInt64(u.uid) AS uid,
        addDays(toDate(u.register_complete_date), 1) AS t_date
    FROM dim.dim_user u
    GLOBAL LEFT JOIN exclude_new_user e
        ON toUInt64(u.uid) = e.uid
    WHERE toDate(u.register_complete_date) BETWEEN addDays(start_dt, -1) AND addDays(end_dt, -1)
      AND ifNull(e.uid, 0) = 0
    GROUP BY
        uid,
        t_date
),

friend_request_user AS (
    SELECT
        toDate(req.req_date) AS request_date,
        toUInt64(req.uid2) AS uid,
        count() AS friend_request_cnt
    FROM dwd.dw_network_add_friend_di req
    GLOBAL LEFT JOIN exclude_sender e
        ON toUInt64(req.uid) = e.uid
    PREWHERE req.d BETWEEN start_dt AND addDays(end_dt, 6)
    WHERE toDate(req.req_date) BETWEEN start_dt AND addDays(end_dt, 6)
       -- 排除无效用户
      AND toUInt64(req.uid) != 0  
      AND toUInt64(req.uid2) != 0
      AND toUInt64(req.uid) != toUInt64(req.uid2)
      AND ifNull(e.uid, 0) = 0
    GROUP BY
        request_date,
        uid
)

SELECT
    t_date AS `t日期`,
    addDays(t_date, -1) AS `t-1新增日期`,
    addDays(t_date, 6) AS `t+6日期`,
    base_user_cnt AS `t-1新增用户数`,
    t_request_user_cnt AS `t天好友申请>=1用户数`,
    round(t_request_user_cnt / nullIf(base_user_cnt, 0), 4) AS `t天好友申请>=1用户占比`,
    t_plus_6_request_user_cnt AS `t+6天好友申请>=1用户数`,
    round(t_plus_6_request_user_cnt / nullIf(base_user_cnt, 0), 4) AS `t+6天好友申请>=1用户占比`
FROM
(
    SELECT
        base.t_date AS t_date,
        uniqExact(base.uid) AS base_user_cnt,
        uniqExactIf(base.uid, ifNull(req_t.friend_request_cnt, 0) >= 1) AS t_request_user_cnt,
        uniqExactIf(base.uid, ifNull(req_t6.friend_request_cnt, 0) >= 1) AS t_plus_6_request_user_cnt
    FROM new_user_base base
    ANY LEFT JOIN friend_request_user req_t
        ON base.uid = req_t.uid
       AND base.t_date = req_t.request_date
    ANY LEFT JOIN friend_request_user req_t6
        ON base.uid = req_t6.uid
       AND addDays(base.t_date, 6) = req_t6.request_date
    GROUP BY base.t_date
)
ORDER BY `t日期` DESC;
