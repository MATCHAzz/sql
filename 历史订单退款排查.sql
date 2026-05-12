/* 
历史订单退款/冲正排查 SQL

订单类型口径：
1 = 线上订单（st >= 1）
2 = 线下订单
3 = 叠加包订单（st >= 1）
4 = 线上退款订单（st = 2）
5 = 叠加包退款订单（st = 2）

说明：
- 本文件全部为 SELECT 查询。
- ClickHouse 21.3 不支持 JOIN ON 里的非等值条件，所以所有 JOIN ON 只保留等值条件。
- 如需只排查召回用户，请使用第 4 段以后带 base 的 SQL。
*/


/* 1. 退款明细关联原支付订单：判断退款对应的原支付时间 */
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,

refund_detail AS
(
    SELECT
        r.uid,
        r.order_id,
        r.deal_id AS refund_deal_id,
        r.income_ts AS refund_ts,
        toDate(r.income_ts) AS refund_date,
        r.create_ts AS refund_create_ts,
        r.update_ts AS refund_update_ts,
        r.order_type AS refund_order_type,
        r.mem_id AS refund_mem_id,
        r.cost AS refund_cost,
        r.is_minus AS refund_is_minus,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        r.channel AS refund_channel,
        r.channel_type AS refund_channel_type,
        r.is_auto_renew AS refund_is_auto_renew,
        r.is_try_repay AS refund_is_try_repay,
        r.is_old_pay AS refund_is_old_pay,
        r.currency AS refund_currency,
        r.is_ios AS refund_is_ios,

        p.origin_pay_ts,
        p.origin_pay_date,
        p.origin_order_type,
        p.origin_deal_id,
        p.origin_cost,
        p.origin_channel,
        p.origin_channel_type,
        p.origin_is_auto_renew,
        p.origin_is_try_repay,
        p.origin_is_old_pay,
        p.origin_pay_cnt
    FROM
    (
        SELECT
            uid,
            order_id,
            deal_id,
            income_ts,
            create_ts,
            update_ts,
            order_type,
            mem_id,
            cost,
            is_minus,
            channel,
            channel_type,
            is_auto_renew,
            is_try_repay,
            is_old_pay,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDate(income_ts) BETWEEN start_date AND end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
    ) AS r
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(income_ts) AS origin_pay_ts,
            min(toDate(income_ts)) AS origin_pay_date,
            argMin(order_type, income_ts) AS origin_order_type,
            argMin(deal_id, income_ts) AS origin_deal_id,
            argMin(cost, income_ts) AS origin_cost,
            argMin(channel, income_ts) AS origin_channel,
            argMin(channel_type, income_ts) AS origin_channel_type,
            argMin(is_auto_renew, income_ts) AS origin_is_auto_renew,
            argMin(is_try_repay, income_ts) AS origin_is_try_repay,
            argMin(is_old_pay, income_ts) AS origin_is_old_pay,
            count() AS origin_pay_cnt
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND (
                (order_type IN (1, 3) AND st >= 1)
                OR order_type = 2
              )
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
)

SELECT
    uid,
    order_id,
    refund_deal_id,
    refund_ts,
    refund_order_type,
    refund_mem_id,
    refund_cost,
    refund_signed_cost,
    refund_channel,
    refund_is_auto_renew,
    refund_is_try_repay,
    refund_update_ts,
    origin_pay_ts,
    origin_order_type,
    origin_deal_id,
    origin_cost,
    origin_channel,
    origin_is_auto_renew,
    origin_is_try_repay,
    origin_pay_cnt,
    multiIf(
        origin_pay_ts IS NULL, '找不到原支付',
        origin_pay_date < refund_date, '历史订单退款',
        origin_pay_date = refund_date, '当天支付当天退款',
        '异常：原支付晚于退款'
    ) AS refund_type
FROM refund_detail
ORDER BY
    refund_signed_cost ASC,
    refund_ts DESC
LIMIT 1000;


/* 2. 汇总：历史订单退款 / 当天退款 / 找不到原支付 */
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,

refund_detail AS
(
    SELECT
        r.uid,
        r.order_id,
        r.income_ts AS refund_ts,
        toDate(r.income_ts) AS refund_date,
        r.cost AS refund_cost,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        p.origin_pay_ts,
        p.origin_pay_date
    FROM
    (
        SELECT
            uid,
            order_id,
            income_ts,
            cost,
            is_minus
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDate(income_ts) BETWEEN start_date AND end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
    ) AS r
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(income_ts) AS origin_pay_ts,
            min(toDate(income_ts)) AS origin_pay_date
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND (
                (order_type IN (1, 3) AND st >= 1)
                OR order_type = 2
              )
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
)

SELECT
    multiIf(
        origin_pay_ts IS NULL, '找不到原支付',
        origin_pay_date < refund_date, '历史订单退款',
        origin_pay_date = refund_date, '当天支付当天退款',
        '异常：原支付晚于退款'
    ) AS `退款类型`,
    count() AS `退款笔数`,
    uniqExact(uid) AS `退款用户数`,
    sum(refund_signed_cost) AS `退款金额`
FROM refund_detail
GROUP BY `退款类型`
ORDER BY `退款金额`;


/* 3. 历史订单退款是否集中在某些退款入账日期 */
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,

refund_detail AS
(
    SELECT
        r.uid,
        r.order_id,
        toDate(r.income_ts) AS refund_date,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        p.origin_pay_date
    FROM
    (
        SELECT
            uid,
            order_id,
            income_ts,
            cost,
            is_minus
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDate(income_ts) BETWEEN start_date AND end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
    ) AS r
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(toDate(income_ts)) AS origin_pay_date
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND (
                (order_type IN (1, 3) AND st >= 1)
                OR order_type = 2
              )
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
)

SELECT
    refund_date AS `退款入账日期`,
    count() AS `历史退款笔数`,
    uniqExact(uid) AS `历史退款用户数`,
    sum(refund_signed_cost) AS `历史退款金额`
FROM refund_detail
WHERE origin_pay_date < refund_date
GROUP BY `退款入账日期`
ORDER BY `历史退款金额`;


/* 4. 只看召回用户：召回后 7 日内退款按原支付时间归类 */
WITH
base AS
(
    /* 这里放会员底表 SQL */
),

refund_detail AS
(
    SELECT
        b.`用户ID`,
        b.`召回日期`,
        b.`平台`,
        b.`七类人群`,
        b.`7日是否会员正向支付`,
        r.order_id,
        r.deal_id AS refund_deal_id,
        r.income_ts AS refund_ts,
        toDate(r.income_ts) AS refund_date,
        r.order_type AS refund_order_type,
        r.cost AS refund_cost,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        r.channel AS refund_channel,
        r.is_auto_renew AS refund_is_auto_renew,
        r.is_try_repay AS refund_is_try_repay,
        p.origin_pay_ts,
        p.origin_pay_date,
        p.origin_order_type,
        p.origin_channel,
        p.origin_is_auto_renew,
        p.origin_is_try_repay
    FROM base b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            deal_id,
            income_ts,
            order_type,
            cost,
            is_minus,
            channel,
            is_auto_renew,
            is_try_repay
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDate(income_ts) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
    ) AS r
        ON b.uid = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(income_ts) AS origin_pay_ts,
            min(toDate(income_ts)) AS origin_pay_date,
            argMin(order_type, income_ts) AS origin_order_type,
            argMin(channel, income_ts) AS origin_channel,
            argMin(is_auto_renew, income_ts) AS origin_is_auto_renew,
            argMin(is_try_repay, income_ts) AS origin_is_try_repay
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND (
                (order_type IN (1, 3) AND st >= 1)
                OR order_type = 2
              )
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTime(income_ts) <= '2024-06-01'
          )
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
    WHERE r.income_ts IS NOT NULL
)

SELECT
    multiIf(
        origin_pay_ts IS NULL, '找不到原支付',
        origin_pay_date < `召回日期`, '召回前历史订单退款',
        origin_pay_date BETWEEN `召回日期` AND `召回日期` + 6, '召回后7日新订单退款',
        origin_pay_date > `召回日期` + 6, '召回7日后新订单退款',
        '其他'
    ) AS `退款归因类型`,
    count() AS `退款笔数`,
    uniqExact(`用户ID`) AS `退款用户数`,
    sum(refund_signed_cost) AS `退款金额`
FROM refund_detail
WHERE refund_date BETWEEN `召回日期` AND `召回日期` + 6
GROUP BY `退款归因类型`
ORDER BY `退款金额`;


/* 4.1 只看召回用户：退款明细版，带召回日期、原支付时间、退款入账时间 */
WITH
base AS
(
    SELECT
        `用户ID` AS uid,
        `召回日期` AS recall_date,
        `平台` AS platform_type,
        `七类人群` AS seven_class,
        `7日是否会员正向支付` AS is_member_pay_7d
    FROM
    (
        /* 这里放会员底表 SQL */
    )
)

SELECT
    b.uid AS `用户ID`,
    b.platform_type AS `平台`,
    b.seven_class AS `七类人群`,
    b.is_member_pay_7d AS `7日是否会员正向支付`,
    b.recall_date AS `召回日期`,
    p.origin_pay_ts AS `原支付时间`,
    r.income_ts AS `退款入账时间`,
    r.update_ts AS `退款更新时间`,
    dateDiff('day', b.recall_date, toDate(r.income_ts)) AS `退款距召回天数`,
    if(
        p.origin_pay_ts IS NULL,
        NULL,
        dateDiff('day', p.origin_pay_date, b.recall_date)
    ) AS `召回距原支付天数`,
    multiIf(
        p.origin_pay_ts IS NULL, '找不到原支付',
        p.origin_pay_date < b.recall_date, '召回前历史订单退款',
        p.origin_pay_date BETWEEN b.recall_date AND b.recall_date + 6, '召回后7日新订单退款',
        p.origin_pay_date > b.recall_date + 6, '召回7日后新订单退款',
        '其他'
    ) AS `退款归因类型`,
    r.order_id AS order_id,
    r.deal_id AS `退款deal_id`,
    p.origin_deal_id AS `原支付deal_id`,
    r.order_type AS `退款订单类型`,
    p.origin_order_type AS `原支付订单类型`,
    r.mem_id AS `退款mem_id`,
    r.cost AS `退款原始金额`,
    if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS `退款有符号金额`,
    p.origin_cost AS `原支付金额`,
    r.channel AS `退款渠道`,
    p.origin_channel AS `原支付渠道`,
    r.is_auto_renew AS `退款是否自动续费`,
    p.origin_is_auto_renew AS `原支付是否自动续费`,
    r.is_try_repay AS `退款是否补扣`,
    p.origin_is_try_repay AS `原支付是否补扣`
FROM base b
LEFT JOIN
(
    SELECT
        uid,
        order_id,
        deal_id,
        income_ts,
        create_ts,
        update_ts,
        order_type,
        mem_id,
        cost,
        is_minus,
        channel,
        channel_type,
        is_auto_renew,
        is_try_repay,
        is_old_pay,
        currency,
        is_ios
    FROM dwd.dw_member_deal_all_da
    WHERE d = yesterday()
      AND toDate(income_ts) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
      AND order_type IN (4, 5)
      AND st = 2
      AND is_minus = 1
      AND mem_id NOT IN (6, 10)
      AND NOT (
          is_ios = 1
          AND currency NOT IN ('USD', 'CNY', '')
          AND toDateTime(income_ts) <= '2024-06-01'
      )
) AS r
    ON b.uid = r.uid
LEFT JOIN
(
    SELECT
        uid,
        order_id,
        min(income_ts) AS origin_pay_ts,
        min(toDate(income_ts)) AS origin_pay_date,
        argMin(order_type, income_ts) AS origin_order_type,
        argMin(deal_id, income_ts) AS origin_deal_id,
        argMin(cost, income_ts) AS origin_cost,
        argMin(channel, income_ts) AS origin_channel,
        argMin(channel_type, income_ts) AS origin_channel_type,
        argMin(is_auto_renew, income_ts) AS origin_is_auto_renew,
        argMin(is_try_repay, income_ts) AS origin_is_try_repay,
        argMin(is_old_pay, income_ts) AS origin_is_old_pay
    FROM dwd.dw_member_deal_all_da
    WHERE d = yesterday()
      AND (
            (order_type IN (1, 3) AND st >= 1)
            OR order_type = 2
          )
      AND is_minus = 0
      AND cost >= 0
      AND mem_id NOT IN (6, 10)
      AND toDateOrNull(toString(income_ts)) IS NOT NULL
      AND NOT (
          is_ios = 1
          AND currency NOT IN ('USD', 'CNY', '')
          AND toDateTime(income_ts) <= '2024-06-01'
      )
    GROUP BY
        uid,
        order_id
) AS p
    ON r.uid = p.uid
   AND r.order_id = p.order_id
WHERE r.income_ts IS NOT NULL
  AND toDate(r.income_ts) BETWEEN b.recall_date AND b.recall_date + 6
ORDER BY
    `退款有符号金额` ASC,
    `退款入账时间` DESC
LIMIT 1000;


/* 4.2 只看召回用户：召回后 7 日内退款归因类型占比 */
WITH
base AS
(
    SELECT
        `用户ID` AS uid,
        `召回日期` AS recall_date
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

refund_detail AS
(
    SELECT
        b.uid,
        b.recall_date,
        r.order_id,
        r.income_date AS refund_date,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        p.origin_pay_ts,
        p.origin_pay_date
    FROM base b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            income_ts,
            toDateOrNull(toString(income_ts)) AS income_date,
            cost,
            is_minus
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS r
        ON b.uid = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(income_ts) AS origin_pay_ts,
            min(toDateOrNull(toString(income_ts))) AS origin_pay_date
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND (
                (order_type IN (1, 3) AND st >= 1)
                OR order_type = 2
              )
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
          AND toDateOrNull(toString(income_ts)) IS NOT NULL
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
    WHERE r.income_ts IS NOT NULL
      AND r.income_date BETWEEN b.recall_date AND b.recall_date + 6
),

type_summary AS
(
    SELECT
        multiIf(
            origin_pay_ts IS NULL, '找不到原支付',
            origin_pay_date < recall_date, '召回前历史订单退款',
            origin_pay_date BETWEEN recall_date AND recall_date + 6, '召回后7日新订单退款',
            origin_pay_date > recall_date + 6, '召回7日后新订单退款',
            '其他'
        ) AS refund_attr_type,
        count() AS refund_order_cnt,
        uniqExact(uid) AS refund_user_cnt,
        sum(refund_signed_cost) AS refund_amount
    FROM refund_detail
    GROUP BY refund_attr_type
),

total_summary AS
(
    SELECT
        count() AS total_refund_order_cnt,
        uniqExact(uid) AS total_refund_user_cnt,
        sum(refund_signed_cost) AS total_refund_amount
    FROM refund_detail
)

SELECT
    s.refund_attr_type AS `退款归因类型`,
    s.refund_order_cnt AS `退款笔数`,
    round(s.refund_order_cnt / t.total_refund_order_cnt, 4) AS `退款笔数占比`,
    s.refund_user_cnt AS `退款用户数`,
    round(s.refund_user_cnt / t.total_refund_user_cnt, 4) AS `退款用户占比`,
    s.refund_amount AS `退款金额`,
    round(abs(s.refund_amount) / abs(t.total_refund_amount), 4) AS `退款金额占比`
FROM type_summary AS s
CROSS JOIN total_summary AS t
ORDER BY `退款金额` ASC;


/* 4.3 只看召回用户：召回后 7 日内历史订单退款明细 */
WITH
base AS
(
    SELECT
        `用户ID` AS uid,
        `召回日期` AS recall_date,
        `平台` AS platform_type,
        `七类人群` AS seven_class,
        `沉默天数` AS silent_days,
        `召回标签` AS recall_tags,
        `7日是否会员正向支付` AS is_member_pay_7d
    FROM
    (
        /* 这里放会员底表 SQL */
    )
)

SELECT
    b.uid AS `用户ID`,
    b.recall_date AS `召回日期`,
    b.platform_type AS `平台`,
    b.seven_class AS `七类人群`,
    b.silent_days AS `沉默天数`,
    b.recall_tags AS `召回标签`,
    b.is_member_pay_7d AS `7日是否会员正向支付`,

    p.origin_pay_ts AS `历史订单购买时间`,
    p.origin_pay_date AS `历史订单购买日期`,
    r.income_ts AS `退款入账时间`,
    r.income_date AS `退款入账日期`,
    r.update_ts AS `退款更新时间`,

    dateDiff('day', p.origin_pay_date, b.recall_date) AS `召回距历史购买天数`,
    dateDiff('day', b.recall_date, r.income_date) AS `退款距召回天数`,
    dateDiff('day', p.origin_pay_date, r.income_date) AS `退款距历史购买天数`,

    r.order_id AS `订单ID`,
    p.origin_deal_id AS `历史购买deal_id`,
    r.deal_id AS `退款deal_id`,
    p.origin_order_type AS `历史购买订单类型`,
    r.order_type AS `退款订单类型`,
    r.mem_id AS `退款mem_id`,

    p.origin_cost AS `历史购买金额`,
    r.cost AS `退款原始金额`,
    if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS `退款有符号金额`,

    p.origin_channel AS `历史购买渠道`,
    p.origin_channel_type AS `历史购买渠道类型`,
    r.channel AS `退款渠道`,
    r.channel_type AS `退款渠道类型`,

    p.origin_is_auto_renew AS `历史购买是否自动续费`,
    r.is_auto_renew AS `退款是否自动续费`,
    p.origin_is_try_repay AS `历史购买是否补扣`,
    r.is_try_repay AS `退款是否补扣`,
    p.origin_is_old_pay AS `历史购买是否老订单`,
    r.is_old_pay AS `退款是否老订单`
FROM base b
LEFT JOIN
(
    SELECT
        uid,
        order_id,
        deal_id,
        income_ts,
        toDateOrNull(toString(income_ts)) AS income_date,
        update_ts,
        order_type,
        mem_id,
        cost,
        is_minus,
        channel,
        channel_type,
        is_auto_renew,
        is_try_repay,
        is_old_pay,
        currency,
        is_ios
    FROM dwd.dw_member_deal_all_da
    WHERE d = yesterday()
      AND toDateOrNull(toString(income_ts)) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
      AND order_type IN (4, 5)
      AND st = 2
      AND is_minus = 1
      AND mem_id NOT IN (6, 10)
      AND NOT (
          is_ios = 1
          AND currency NOT IN ('USD', 'CNY', '')
          AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
      )
) AS r
    ON b.uid = r.uid
LEFT JOIN
(
    SELECT
        uid,
        order_id,
        min(income_ts) AS origin_pay_ts,
        min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
        argMin(order_type, income_ts) AS origin_order_type,
        argMin(deal_id, income_ts) AS origin_deal_id,
        argMin(cost, income_ts) AS origin_cost,
        argMin(channel, income_ts) AS origin_channel,
        argMin(channel_type, income_ts) AS origin_channel_type,
        argMin(is_auto_renew, income_ts) AS origin_is_auto_renew,
        argMin(is_try_repay, income_ts) AS origin_is_try_repay,
        argMin(is_old_pay, income_ts) AS origin_is_old_pay
    FROM dwd.dw_member_deal_all_da
    WHERE d = yesterday()
      AND (
            (order_type IN (1, 3) AND st >= 1)
            OR order_type = 2
          )
      AND is_minus = 0
      AND cost >= 0
      AND mem_id NOT IN (6, 10)
      AND toDateOrNull(toString(income_ts)) IS NOT NULL
      AND NOT (
          is_ios = 1
          AND currency NOT IN ('USD', 'CNY', '')
          AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
      )
    GROUP BY
        uid,
        order_id
) AS p
    ON r.uid = p.uid
   AND r.order_id = p.order_id
WHERE r.income_ts IS NOT NULL
  AND r.income_date BETWEEN b.recall_date AND b.recall_date + 6
  AND p.origin_pay_ts IS NOT NULL
  AND p.origin_pay_date < b.recall_date
ORDER BY
    `退款有符号金额` ASC,
    `退款入账时间` DESC
LIMIT 10000;


/* 4.4 只看召回用户：召回后 7 日内正向付费后又退款的新订单规模 */
WITH
base AS
(
    SELECT
        `用户ID` AS uid,
        `召回日期` AS recall_date,
        `7日是否会员正向支付` AS is_member_pay_7d
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

new_order_refund_detail AS
(
    SELECT
        b.uid,
        b.recall_date,
        b.is_member_pay_7d,
        r.order_id,
        r.deal_id AS refund_deal_id,
        r.income_ts AS refund_ts,
        r.income_date AS refund_date,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        p.origin_pay_ts,
        p.origin_pay_date,
        p.origin_deal_id,
        p.origin_cost
    FROM base b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            deal_id,
            income_ts,
            toDateOrNull(toString(income_ts)) AS income_date,
            cost,
            is_minus
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS r
        ON b.uid = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(income_ts) AS origin_pay_ts,
            min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
            argMin(deal_id, income_ts) AS origin_deal_id,
            argMin(cost, income_ts) AS origin_cost
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND order_type IN (1, 3)
          AND st >= 1
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
          AND toDateOrNull(toString(income_ts)) IS NOT NULL
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
    WHERE r.income_ts IS NOT NULL
      AND r.income_date BETWEEN b.recall_date AND b.recall_date + 6
      AND p.origin_pay_ts IS NOT NULL
      AND p.origin_pay_date BETWEEN b.recall_date AND b.recall_date + 6
)

SELECT
    uniqExact(uid) AS `7日正向付费后退款用户数`,
    uniqExactIf(uid, is_member_pay_7d = 1) AS `其中属于7日会员支付用户数`,
    count() AS `7日正向付费后退款订单数`,
    sum(origin_cost) AS `对应正向购买金额`,
    sum(refund_signed_cost) AS `对应退款金额`
FROM new_order_refund_detail;


/* 4.5 只看召回用户：召回后 7 日内正向付费后又退款的新订单明细 */
WITH
base AS
(
    SELECT
        `用户ID` AS uid,
        `召回日期` AS recall_date,
        `平台` AS platform_type,
        `七类人群` AS seven_class,
        `7日是否会员正向支付` AS is_member_pay_7d
    FROM
    (
        /* 这里放会员底表 SQL */
    )
)

SELECT
    b.uid AS `用户ID`,
    b.recall_date AS `召回日期`,
    b.platform_type AS `平台`,
    b.seven_class AS `七类人群`,
    b.is_member_pay_7d AS `7日是否会员正向支付`,
    p.origin_pay_ts AS `正向购买时间`,
    p.origin_pay_date AS `正向购买日期`,
    r.income_ts AS `退款入账时间`,
    r.income_date AS `退款入账日期`,
    dateDiff('day', b.recall_date, p.origin_pay_date) AS `购买距召回天数`,
    dateDiff('day', b.recall_date, r.income_date) AS `退款距召回天数`,
    dateDiff('day', p.origin_pay_date, r.income_date) AS `退款距购买天数`,
    r.order_id AS `订单ID`,
    p.origin_deal_id AS `正向购买deal_id`,
    r.deal_id AS `退款deal_id`,
    p.origin_cost AS `正向购买金额`,
    r.cost AS `退款原始金额`,
    if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS `退款有符号金额`
FROM base b
LEFT JOIN
(
    SELECT
        uid,
        order_id,
        deal_id,
        income_ts,
        toDateOrNull(toString(income_ts)) AS income_date,
        cost,
        is_minus
    FROM dwd.dw_member_deal_all_da
    WHERE d = yesterday()
      AND toDateOrNull(toString(income_ts)) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
      AND order_type IN (4, 5)
      AND st = 2
      AND is_minus = 1
      AND mem_id NOT IN (6, 10)
      AND NOT (
          is_ios = 1
          AND currency NOT IN ('USD', 'CNY', '')
          AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
      )
) AS r
    ON b.uid = r.uid
LEFT JOIN
(
    SELECT
        uid,
        order_id,
        min(income_ts) AS origin_pay_ts,
        min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
        argMin(deal_id, income_ts) AS origin_deal_id,
        argMin(cost, income_ts) AS origin_cost
    FROM dwd.dw_member_deal_all_da
    WHERE d = yesterday()
      AND order_type IN (1, 3)
      AND st >= 1
      AND is_minus = 0
      AND cost >= 0
      AND mem_id NOT IN (6, 10)
      AND toDateOrNull(toString(income_ts)) IS NOT NULL
      AND NOT (
          is_ios = 1
          AND currency NOT IN ('USD', 'CNY', '')
          AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
      )
    GROUP BY
        uid,
        order_id
) AS p
    ON r.uid = p.uid
   AND r.order_id = p.order_id
WHERE r.income_ts IS NOT NULL
  AND r.income_date BETWEEN b.recall_date AND b.recall_date + 6
  AND p.origin_pay_ts IS NOT NULL
  AND p.origin_pay_date BETWEEN b.recall_date AND b.recall_date + 6
ORDER BY
    `退款有符号金额` ASC,
    `退款入账时间` DESC
LIMIT 10000;


/* 5. 只看召回用户：历史订单退款是否集中在 auto_renew / try_repay */
WITH
base AS
(
    /* 这里放会员底表 SQL */
),

refund_detail AS
(
    SELECT
        b.`用户ID`,
        b.`召回日期`,
        r.order_id,
        toDate(r.income_ts) AS refund_date,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost,
        r.channel AS refund_channel,
        r.is_auto_renew AS refund_is_auto_renew,
        r.is_try_repay AS refund_is_try_repay,
        p.origin_pay_date,
        p.origin_channel,
        p.origin_is_auto_renew,
        p.origin_is_try_repay
    FROM base b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            income_ts,
            cost,
            is_minus,
            channel,
            is_auto_renew,
            is_try_repay
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDate(income_ts) BETWEEN toDate('2026-02-01') AND toDate('2026-04-30')
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND mem_id NOT IN (6, 10)
    ) AS r
        ON b.`用户ID` = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(toDate(income_ts)) AS origin_pay_date,
            argMin(channel, income_ts) AS origin_channel,
            argMin(is_auto_renew, income_ts) AS origin_is_auto_renew,
            argMin(is_try_repay, income_ts) AS origin_is_try_repay
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND (
                (order_type IN (1, 3) AND st >= 1)
                OR order_type = 2
              )
          AND is_minus = 0
          AND cost >= 0
          AND mem_id NOT IN (6, 10)
        GROUP BY
            uid,
            order_id
    ) AS p
        ON r.uid = p.uid
       AND r.order_id = p.order_id
    WHERE r.income_ts IS NOT NULL
)

SELECT
    origin_channel AS `原支付渠道`,
    origin_is_auto_renew AS `原支付是否自动续费`,
    origin_is_try_repay AS `原支付是否补扣`,
    refund_channel AS `退款渠道`,
    refund_is_auto_renew AS `退款是否自动续费`,
    refund_is_try_repay AS `退款是否补扣`,
    count() AS `历史退款笔数`,
    uniqExact(`用户ID`) AS `历史退款用户数`,
    sum(refund_signed_cost) AS `历史退款金额`
FROM refund_detail
WHERE refund_date BETWEEN `召回日期` AND `召回日期` + 6
  AND origin_pay_date < `召回日期`
GROUP BY
    `原支付渠道`,
    `原支付是否自动续费`,
    `原支付是否补扣`,
    `退款渠道`,
    `退款是否自动续费`,
    `退款是否补扣`
ORDER BY `历史退款金额`;
