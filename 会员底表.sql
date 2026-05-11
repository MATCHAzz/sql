WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,
    7 AS attr_days,
    end_date AS pay_end_date


SELECT
    b.base_uid AS `用户ID`,
    b.recall_date AS `召回日期`,
    b.recall_month AS `召回月份`,
    b.platform_type AS `平台`,
    b.seven_class AS `七类人群`,
    b.silent_days AS `沉默天数`,
    b.recall_tags AS `召回标签`,

    maxIf(
        p.member_pay_flag,
        b.blocked_flag = 0
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日是否会员正向支付`,

    nullIf(
        minIf(
            p.pay_date,
            b.blocked_flag = 0
            AND p.member_pay_flag = 1
            AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
        ),
        toDate('1970-01-01')
    ) AS `7日首次会员支付日期`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.member_pay_flag = 1
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日会员正向支付收入_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日退款金额_现金流口径_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.origin_pay_cnt > 0
        AND p.origin_pay_date < b.recall_date
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日历史订单退款金额_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.origin_pay_cnt > 0
        AND p.origin_pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日召回后新订单退款金额_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.origin_pay_cnt = 0
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日未知原支付订单退款金额_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
    ) AS `7日会员净收入_现金流口径_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
        AND (
            p.member_pay_flag = 1
            OR (
                p.order_type IN (4, 5)
                AND p.origin_pay_cnt > 0
                AND p.origin_pay_date BETWEEN b.recall_date AND b.recall_date + attr_days - 1
            )
        )
    ) AS `7日会员净收入_召回归因口径_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.member_pay_flag = 1
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
    ) AS `召回后累计会员正向支付收入_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
    ) AS `召回后累计退款金额_现金流口径_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.origin_pay_cnt > 0
        AND p.origin_pay_date < b.recall_date
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
    ) AS `召回后累计历史订单退款金额_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.origin_pay_cnt > 0
        AND p.origin_pay_date BETWEEN b.recall_date AND pay_end_date
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
    ) AS `召回后累计新订单退款金额_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.order_type IN (4, 5)
        AND p.origin_pay_cnt = 0
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
    ) AS `召回后累计未知原支付订单退款金额_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
    ) AS `召回后累计会员净收入_现金流口径_剔除黑产`,

    sumIf(
        p.cost_1,
        b.blocked_flag = 0
        AND p.pay_date BETWEEN b.recall_date AND pay_end_date
        AND (
            p.member_pay_flag = 1
            OR (
                p.order_type IN (4, 5)
                AND p.origin_pay_cnt > 0
                AND p.origin_pay_date BETWEEN b.recall_date AND pay_end_date
            )
        )
    ) AS `召回后累计会员净收入_召回归因口径_剔除黑产`

FROM
(
    SELECT
        e.uid AS base_uid,
        e.recall_date AS recall_date,
        toStartOfMonth(e.recall_date) AS recall_month,
        e.recall_tags AS recall_tags,
        e.silent_days AS silent_days,

        multiIf(
            lowerUTF8(toString(e.platform_type)) IN ('android', '安卓'), 'android',
            lowerUTF8(toString(e.platform_type)) IN ('ios', 'iphone'), 'ios',
            'other'
        ) AS platform_type,

        ifNull(nullIf(trimBoth(toString(u.seven_class)), ''), '未知') AS seven_class,
        ifNull(u.blocked_flag, 0) AS blocked_flag

    FROM
    (
        SELECT
            uid,
            min(d) AS recall_date,
            argMin(recall_tags, d) AS recall_tags,
            argMin(silent_days, d) AS silent_days,
            argMin(platform_type, d) AS platform_type
        FROM
        (
            SELECT
                r.uid AS uid,
                r.d AS d,
                any(r.recall_tags) AS recall_tags,
                any(a.silent_days) AS silent_days,
                any(a.platform) AS platform_type
            FROM dwm.dw_growth_user_active_di AS a
            ANY INNER JOIN
            (
                SELECT
                    uid,
                    d,
                    groupUniqArray(tag) AS recall_tags
                FROM dwm.dw_growth_user_sms_recall_di
                WHERE d BETWEEN start_date AND end_date
                GROUP BY
                    uid,
                    d
            ) AS r
                ON r.uid = a.uid
               AND r.d = a.d
            WHERE a.d BETWEEN start_date AND end_date
              AND a.silent_days >= 30
              AND a.is_member = 0
            GROUP BY
                r.uid,
                r.d
        ) AS recall_daily
        GROUP BY uid
    ) AS e


    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(nullIf(trimBoth(toString(seven_class)), ''), '未知')) AS seven_class,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON e.uid = u.uid

) AS b

LEFT JOIN
(
    SELECT
        d.uid AS uid,
        d.order_id AS order_id,
        toDate(d.income_ts) AS pay_date,
        d.order_type AS order_type,

        if(
            d.is_minus = 1,
            0 - abs(toFloat64(d.cost)),
            abs(toFloat64(d.cost))
        ) AS cost_1,

        if(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND toFloat64(d.cost) > 0,
            1,
            0
        ) AS member_pay_flag,

        if(
            d.order_type IN (1, 3),
            toDate(d.income_ts),
            ifNull(op.origin_pay_date, toDate('1970-01-01'))
        ) AS origin_pay_date,

        if(
            d.order_type IN (1, 3),
            1,
            ifNull(op.origin_pay_cnt, 0)
        ) AS origin_pay_cnt

    FROM
    (
        SELECT
            uid,
            order_id,
            income_ts,
            order_type,
            cost,
            is_minus,
            is_ios,
            currency
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDate(income_ts) BETWEEN start_date AND pay_end_date
          AND mem_id NOT IN (6, 10)
          AND (
                (order_type IN (1, 3) AND cost >= 0)
                OR order_type IN (4, 5)
              )
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
    ) AS d
    LEFT JOIN
    (
        SELECT
            order_id,
            uid,
            min(toDate(income_ts)) AS origin_pay_date,
            count() AS origin_pay_cnt
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND order_type IN (1, 3)
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
        GROUP BY
            order_id,
            uid
    ) AS op
        ON d.uid = op.uid
       AND d.order_id = op.order_id
) AS p
    ON p.uid = b.base_uid

GROUP BY
    b.base_uid,
    b.recall_date,
    b.recall_month,
    b.platform_type,
    b.seven_class,
    b.silent_days,
    b.recall_tags
