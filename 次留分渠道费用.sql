WITH
    toDate('{{start}}') AS start_date,
    toDate('{{end}}') AS end_date,


-- 1. recall_remain_opportunity_mc 任务下发明细
-- 这张表是主表：这个任务到底发给了哪些 uid

task_base AS (
    SELECT
        uid,
        task_date,
        tag,
        pay_channel,
        is_send_success,
        cost_pv,
        fee
    FROM (
        SELECT
            uid,
            task_date,
            tag,
            pay_channel,
            is_send_success,
            msg_cnt,

            -- 只有发送成功才计费
            if(is_send_success = 1, msg_cnt, 0) AS cost_pv,
            if(is_send_success = 1, msg_cnt, 0) * unit_price AS fee

        FROM (
            SELECT
                uid,
                task_date,
                tag,
                pay_channel,
                is_send_success,
                cnt_len,

                multiIf(
                    cnt_len < 71, 1,
                    cnt_len >= 71 AND cnt_len <= 134, 2,
                    cnt_len >= 135 AND cnt_len <= 201, 3,
                    4
                ) AS msg_cnt,

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

                    pay_channel = '一知' AND task_date < toDate('2025-07-16'), 0.13,
                    pay_channel = '一知' AND task_date >= toDate('2025-07-16'), 0.16,
                    pay_channel = 'aliyun_ai', 0.14,

                    pay_channel = '文本短信-3日前', 0.03,

                    pay_channel = '百应' AND task_date < toDate('2025-07-17'), 0.16,
                    pay_channel = '百应' AND task_date >= toDate('2025-07-17') AND task_date <= toDate('2025-08-31'), 0.17,
                    pay_channel = '百应' AND task_date >= toDate('2025-09-01'), 0.15,

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
                ) AS unit_price

            FROM (
                SELECT
                    toUInt64(uid) AS uid,
                    d AS task_date,
                    tag,
                    is_send_success,
                    provider_channel,

                    if(
                        substringUTF8(content, 1, 5) LIKE '【脉脉】%', 
                        lengthUTF8(content),
                        if(provider_channel LIKE '%阿里云%', lengthUTF8(content) + 2, lengthUTF8(content) + 4)
                    ) AS cnt_len,

                    -- 但是这里现在tag只有召回tag，没有别的
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
                WHERE d BETWEEN start_date AND end_date
                  AND tag LIKE '%recall_remain_opportunity_mc%'
            )
        )
    )
),



-- 2. 给 task_base 里的 uid 做来源归因
source_raw AS (

    /* 1）新增用户
       如果口径是“新增后第1天发次留任务”，用 d + 1 = task_date
       如果是新增当天发任务，把 d + 1 改成 d
    */
    SELECT
        toUInt64(uid) AS uid,
        d AS task_date,
        '新增用户' AS source_channel,
        1 AS priority
    FROM dws.dw_dau
    WHERE d BETWEEN start_date - 1 AND end_date - 1
      AND is_new_user = 1
    GROUP BY uid, task_date


    UNION ALL


    /* 2）信息流用户 */
    SELECT
        toUInt64(uid) AS uid,
        d + 1 AS task_date,
        '信息流用户' AS source_channel,
        2 AS priority
    FROM dwm.dw_growth_user_active_di
    WHERE d BETWEEN start_date - 1 AND end_date - 1
      AND is_silent_30d = 1
      AND is_info_stream_touch = 1
      AND is_new = 0
    GROUP BY uid, task_date


    UNION ALL


    /* 3）召回类渠道触达 */
    SELECT
        toUInt64(uid) AS uid,
        d + 1 AS task_date,
        '召回类渠道触达' AS source_channel,
        3 AS priority
    FROM dwm.dw_growth_user_sms_recall_di
    WHERE d BETWEEN start_date - 1 AND end_date - 1
      AND (
             tag LIKE 'recall%'
          OR tag LIKE 'bonus%'
          OR tag LIKE '%mengwang%'
          OR tag LIKE 'baiying%'
          OR tag LIKE 'zhichi%'
          OR tag LIKE '百应%'
          OR tag LIKE '智齿%'
          OR tag LIKE 'yizhi%'
          OR tag LIKE '高薪%'
          OR tag LIKE '阿里云%'
          OR tag LIKE '%机遇%'
          OR tag LIKE '%兜底%'
          OR tag LIKE '%首播%'
          OR tag LIKE '%复播%'
          OR tag LIKE '一知'
      )
      AND tag NOT LIKE 'recall_today_1_send_msg%'
      AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
    GROUP BY uid, task_date
),


/* 同一个 uid 同一天如果命中多个来源，按优先级归因 */
user_source AS (
    SELECT
        uid,
        task_date,
        argMin(source_channel, priority) AS source_channel
    FROM source_raw
    GROUP BY uid, task_date
),



-- 3. 次日活跃用户
-- 任务 D 天发，D+1 活跃算次留
-- 取 DAU 表里的活跃用户
active_user AS (
    SELECT
        toUInt64(uid) AS uid,
        d AS active_date
    FROM dws.dw_dau
    WHERE d BETWEEN start_date AND end_date + 1
    GROUP BY uid, active_date
),



-- 4. 最终结果
final_result AS (
    SELECT
        task_date AS d,
        source_channel,

        touch_uv,
        send_success_uv,
        next_day_active_uv,
        cost_pv,
        fee,

        round(send_success_uv / nullIf(touch_uv, 0), 4) AS send_success_rate,
        round(next_day_active_uv / nullIf(send_success_uv, 0), 4) AS next_day_active_rate

    FROM (
        SELECT
            t.task_date AS task_date,
            ifNull(u.source_channel, '其他/未归因') AS source_channel,

            uniqExact(t.uid) AS touch_uv,  -- 等于count(distinct uid)
            uniqExactIf(t.uid, t.is_send_success = 1) AS send_success_uv,
            -- 等于COUNT(DISTINCT CASE WHEN 条件 THEN uid END)
            uniqExactIf(
                t.uid,
                t.is_send_success = 1
                AND a.uid > 0
            ) AS next_day_active_uv,

            sum(t.cost_pv) AS cost_pv,
            round(sum(t.fee), 2) AS fee

        FROM task_base AS t

        ANY LEFT JOIN user_source AS u
            ON t.uid = u.uid
           AND t.task_date = u.task_date

        ANY LEFT JOIN active_user AS a
            ON t.uid = a.uid
           AND t.task_date + 1 = a.active_date  -- d+1 活跃算次留

        GROUP BY
            t.task_date,
            ifNull(u.source_channel, '其他/未归因')
    )
)


SELECT
    d,
    source_channel,
    touch_uv AS `触达uv`,
    send_success_uv AS `发送成功uv`,
    next_day_active_uv AS `次留活跃uv`,
    cost_pv AS `计费量`,
    fee AS `花费`,
    send_success_rate AS `发送成功率`,
    next_day_active_rate AS `次留活跃率`
FROM final_result
ORDER BY
    d ASC,
    multiIf(
        source_channel = '新增用户', 1,
        source_channel = '信息流用户', 2,
        source_channel = '召回类渠道触达', 3,
        source_channel = '其他/未归因', 4,
        99
    ) ASC;