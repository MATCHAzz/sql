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


/* 7.1 历史退款风险观察包：按召回前可识别特征分层，并回测覆盖量和误伤收入

操作方式：
1. 把下方 “这里放会员底表 SQL” 替换成当前会员底表 SQL。
2. 先跑本段评估表，看每个风险包的人数、占比、历史退款覆盖、误伤归因收入。
3. 如需给业务明细包，将本段最后一个 SELECT 替换成 7.2 注释中的明细 SELECT。

注意：
- 本段只使用召回日期之前可见的订单行为做分层，避免使用“召回后发生历史退款”这个结果标签。
- 当前正向支付按会员底表主口径 order_type IN (1, 3)。若确认线下订单 order_type = 2 应计入会员收入，需要同步纳入。
- 阈值是观察包，不建议直接上线排除；应先看覆盖量、命中率、历史退款金额覆盖率和误伤收入。
- 分层思路：结合当前回测结果，保留三层包。重点观察包覆盖主要历史退款风险，但不直接作为排除包；普通观察包仅用于监控；正常召回包正常投放。
*/
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,

base_raw AS
(
    SELECT *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

base AS
(
    SELECT
        b.*,
        ifNull(u.blocked_flag, 0) AS blocked_flag
    FROM base_raw AS b
    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON b.`用户ID` = u.uid
),

pre_feature AS
(
    SELECT
        b.`用户ID`,
        b.`召回日期`,
        b.`召回月份`,
        b.`平台`,
        b.`七类人群`,
        b.`沉默天数`,
        b.`召回标签`,
        b.`7日是否会员正向支付`,
        b.`7日历史订单退款金额_剔除黑产`,
        b.`7日会员净收入_召回归因口径_剔除黑产`,
        b.`召回后累计历史订单退款金额_剔除黑产`,
        b.`召回后累计会员净收入_召回归因口径_剔除黑产`,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
        ) AS pre_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_auto_renew = 1
        ) AS pre_auto_renew_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_old_pay = 1
        ) AS pre_old_pay_cnt,

        countIf(
            d.order_type IN (4, 5)
            AND d.is_minus = 1
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
        ) AS pre_refund_cnt_all,

        sumIf(
            0 - abs(d.cost_float),
            d.order_type IN (4, 5)
            AND d.is_minus = 1
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
        ) AS pre_refund_amount_all,

        countIf(
            d.order_type IN (4, 5)
            AND d.is_minus = 1
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 365 AND b.`召回日期` - 1
        ) AS pre_refund_cnt_365d,

        sumIf(
            0 - abs(d.cost_float),
            d.order_type IN (4, 5)
            AND d.is_minus = 1
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 365 AND b.`召回日期` - 1
        ) AS pre_refund_amount_365d
    FROM base AS b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            toDateOrNull(toString(income_ts)) AS income_date,
            order_type,
            is_minus,
            toFloat64(cost) AS cost_float,
            is_auto_renew,
            is_try_repay,
            is_old_pay,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) < end_date
          AND order_type IN (1, 3, 4, 5)
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS d
        ON b.`用户ID` = d.uid
    GROUP BY
        b.`用户ID`,
        b.`召回日期`,
        b.`召回月份`,
        b.`平台`,
        b.`七类人群`,
        b.`沉默天数`,
        b.`召回标签`,
        b.`7日是否会员正向支付`,
        b.`7日历史订单退款金额_剔除黑产`,
        b.`7日会员净收入_召回归因口径_剔除黑产`,
        b.`召回后累计历史订单退款金额_剔除黑产`,
        b.`召回后累计会员净收入_召回归因口径_剔除黑产`
),

risk_pack AS
(
    SELECT
        *,
        multiIf(
            pre_try_repay_pay_cnt > 0
            OR pre_refund_cnt_365d >= 2
            OR pre_auto_renew_pay_cnt >= 3
            OR pre_old_pay_cnt >= 3
            OR (
                pre_refund_cnt_365d >= 1
                AND (
                    pre_auto_renew_pay_cnt >= 2
                    OR pre_old_pay_cnt >= 2
                )
            ),
            '重点观察包',

            pre_refund_cnt_365d = 1
            OR pre_auto_renew_pay_cnt > 0
            OR pre_old_pay_cnt > 0
            OR pre_pay_cnt >= 3,
            '普通观察包',

            '正常召回包'
        ) AS risk_pack,

        multiIf(
            pre_try_repay_pay_cnt > 0, '召回前存在补扣支付',
            pre_refund_cnt_365d >= 2, '召回前365天退款/冲正>=2次',
            pre_auto_renew_pay_cnt >= 3, '召回前历史自动续费支付>=3次',
            pre_old_pay_cnt >= 3, '召回前历史老订单支付>=3次',
            pre_refund_cnt_365d >= 1 AND pre_auto_renew_pay_cnt >= 2, '召回前365天退款/冲正且历史自动续费>=2次',
            pre_refund_cnt_365d >= 1 AND pre_old_pay_cnt >= 2, '召回前365天退款/冲正且历史老订单>=2次',
            pre_refund_cnt_365d = 1, '召回前365天退款/冲正1次',
            pre_auto_renew_pay_cnt = 2, '召回前历史自动续费支付=2次',
            pre_old_pay_cnt = 2, '召回前历史老订单支付=2次',
            pre_pay_cnt >= 3 AND pre_auto_renew_pay_cnt >= 1, '召回前支付>=3次且有自动续费',
            pre_pay_cnt >= 3 AND pre_old_pay_cnt >= 1, '召回前支付>=3次且有老订单',
            pre_auto_renew_pay_cnt = 1, '召回前历史自动续费支付=1次',
            pre_old_pay_cnt = 1, '召回前历史老订单支付=1次',
            pre_pay_cnt >= 3, '召回前会员支付>=3次',
            '无明显召回前退款风险特征'
        ) AS risk_reason
    FROM pre_feature
)

SELECT
    risk_pack AS `人群包`,
    count() AS `人群包用户数`,
    round(`人群包用户数` / (SELECT count() FROM risk_pack), 6) AS `占召回用户比例`,
    uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0) AS `命中7日历史退款用户数`,
    round(`命中7日历史退款用户数` / (SELECT uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0) FROM risk_pack), 4) AS `覆盖7日历史退款用户比例`,
    sum(`7日历史订单退款金额_剔除黑产`) AS `覆盖7日历史退款金额`,
    round(abs(`覆盖7日历史退款金额`) / abs((SELECT sum(`7日历史订单退款金额_剔除黑产`) FROM risk_pack)), 4) AS `覆盖7日历史退款金额比例`,
    uniqExactIf(`用户ID`, `召回后累计历史订单退款金额_剔除黑产` < 0) AS `命中累计历史退款用户数`,
    round(`命中累计历史退款用户数` / (SELECT uniqExactIf(`用户ID`, `召回后累计历史订单退款金额_剔除黑产` < 0) FROM risk_pack), 4) AS `覆盖累计历史退款用户比例`,
    sum(`召回后累计历史订单退款金额_剔除黑产`) AS `覆盖累计历史退款金额`,
    round(abs(`覆盖累计历史退款金额`) / abs((SELECT sum(`召回后累计历史订单退款金额_剔除黑产`) FROM risk_pack)), 4) AS `覆盖累计历史退款金额比例`,
    uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS `可能误伤7日支付用户数`,
    sum(`7日会员净收入_召回归因口径_剔除黑产`) AS `可能误伤7日归因净收入`,
    sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS `可能误伤累计归因净收入`,
    uniqExactIf(`用户ID`, pre_refund_cnt_365d = 1) AS `召回前365天单次退款用户数`,
    uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0 AND pre_refund_cnt_365d = 1) AS `命中7日历史退款且单次退款用户数`,
    uniqExactIf(`用户ID`, pre_refund_cnt_365d >= 2) AS `召回前365天多次退款用户数`,
    uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0 AND pre_refund_cnt_365d >= 2) AS `命中7日历史退款且多次退款用户数`,
    uniqExactIf(`用户ID`, pre_try_repay_pay_cnt > 0) AS `召回前存在补扣支付用户数`,
    uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0 AND pre_try_repay_pay_cnt > 0) AS `命中7日历史退款且存在补扣支付用户数`,
    uniqExactIf(`用户ID`, pre_auto_renew_pay_cnt >= 3) AS `召回前自动续费支付大于等于3次用户数`,
    uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0 AND pre_auto_renew_pay_cnt >= 3) AS `命中7日历史退款且自动续费大于等于3次用户数`,
    uniqExactIf(`用户ID`, pre_old_pay_cnt >= 3) AS `召回前老订单支付大于等于3次用户数`,
    uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0 AND pre_old_pay_cnt >= 3) AS `命中7日历史退款且老订单大于等于3次用户数`
FROM risk_pack
GROUP BY risk_pack
ORDER BY
    multiIf(
        `人群包` = '重点观察包', 1,
        `人群包` = '普通观察包', 2,
        3
    );


/* 7.2 如果需要导出人群包明细，把 7.1 最后的 SELECT 替换为下面这段

SELECT
    `用户ID`,
    `召回日期`,
    `平台`,
    `七类人群`,
    `沉默天数`,
    risk_pack AS `人群包`,
    risk_reason AS `入包原因`,
    pre_refund_cnt_365d AS `召回前365天退款冲正次数`,
    pre_refund_amount_365d AS `召回前365天退款冲正金额`,
    pre_auto_renew_pay_cnt AS `召回前历史自动续费支付次数`,
    pre_try_repay_pay_cnt AS `召回前历史补扣支付次数`,
    pre_old_pay_cnt AS `召回前历史老订单支付次数`,
    `7日历史订单退款金额_剔除黑产`,
    `召回后累计历史订单退款金额_剔除黑产`,
    `7日会员净收入_召回归因口径_剔除黑产`,
    `召回后累计会员净收入_召回归因口径_剔除黑产`
FROM risk_pack
WHERE risk_pack IN ('重点观察包', '普通观察包')
ORDER BY
    multiIf(
        risk_pack = '重点观察包', 1,
        risk_pack = '普通观察包', 2,
        3
    ),
    pre_refund_amount_365d ASC,
    `召回日期` DESC
LIMIT 100000;
*/


/* 7.3 直接排除候选规则扫描：低内存版，用于从重点观察包里继续收窄

使用方式：
- 复制 7.1 的 WITH 到 risk_pack AS (...) 为止。
- 将 7.1 最后的 SELECT 替换为下面这段。
- 低内存版只扫描一次 risk_pack，避免 ClickHouse 21.3 把大 CTE 在多段 UNION ALL 和标量子查询里反复展开。
- 因 risk_pack 是用户粒度，一行一个用户，这里用 countIf 代替 uniqExactIf，降低聚合内存。
- 目标不是覆盖全部历史退款，而是寻找“人群足够小、历史退款覆盖较高、误伤收入可接受”的直接排除候选规则。
- 建议优先看：候选包用户数、覆盖7日历史退款金额比例、可能误伤累计归因净收入。
*/

/*
, candidate_scan AS
(
    SELECT
        count() AS total_recall_user_cnt,
        countIf(`7日历史订单退款金额_剔除黑产` < 0) AS total_hist_user_7d,
        abs(sum(`7日历史订单退款金额_剔除黑产`)) AS total_hist_amount_7d_abs,
        countIf(`召回后累计历史订单退款金额_剔除黑产` < 0) AS total_hist_user_after_recall,
        abs(sum(`召回后累计历史订单退款金额_剔除黑产`)) AS total_hist_amount_after_recall_abs,

        countIf(pre_try_repay_pay_cnt > 0) AS rule_user_cnt_01,
        countIf(pre_try_repay_pay_cnt > 0 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_01,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_try_repay_pay_cnt > 0) AS hit_hist_amount_7d_01,
        countIf(pre_try_repay_pay_cnt > 0 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_01,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_try_repay_pay_cnt > 0) AS hit_hist_amount_after_recall_01,
        countIf(pre_try_repay_pay_cnt > 0 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_01,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_try_repay_pay_cnt > 0) AS hurt_attr_income_7d_01,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_try_repay_pay_cnt > 0) AS hurt_attr_income_after_recall_01,

        countIf(pre_auto_renew_pay_cnt >= 10) AS rule_user_cnt_02,
        countIf(pre_auto_renew_pay_cnt >= 10 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_02,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_auto_renew_pay_cnt >= 10) AS hit_hist_amount_7d_02,
        countIf(pre_auto_renew_pay_cnt >= 10 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_02,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_auto_renew_pay_cnt >= 10) AS hit_hist_amount_after_recall_02,
        countIf(pre_auto_renew_pay_cnt >= 10 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_02,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_auto_renew_pay_cnt >= 10) AS hurt_attr_income_7d_02,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_auto_renew_pay_cnt >= 10) AS hurt_attr_income_after_recall_02,

        countIf(pre_auto_renew_pay_cnt >= 5) AS rule_user_cnt_03,
        countIf(pre_auto_renew_pay_cnt >= 5 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_03,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_auto_renew_pay_cnt >= 5) AS hit_hist_amount_7d_03,
        countIf(pre_auto_renew_pay_cnt >= 5 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_03,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_auto_renew_pay_cnt >= 5) AS hit_hist_amount_after_recall_03,
        countIf(pre_auto_renew_pay_cnt >= 5 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_03,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_auto_renew_pay_cnt >= 5) AS hurt_attr_income_7d_03,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_auto_renew_pay_cnt >= 5) AS hurt_attr_income_after_recall_03,

        countIf(pre_auto_renew_pay_cnt >= 3) AS rule_user_cnt_04,
        countIf(pre_auto_renew_pay_cnt >= 3 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_04,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_auto_renew_pay_cnt >= 3) AS hit_hist_amount_7d_04,
        countIf(pre_auto_renew_pay_cnt >= 3 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_04,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_auto_renew_pay_cnt >= 3) AS hit_hist_amount_after_recall_04,
        countIf(pre_auto_renew_pay_cnt >= 3 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_04,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_auto_renew_pay_cnt >= 3) AS hurt_attr_income_7d_04,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_auto_renew_pay_cnt >= 3) AS hurt_attr_income_after_recall_04,

        countIf(pre_old_pay_cnt >= 10) AS rule_user_cnt_05,
        countIf(pre_old_pay_cnt >= 10 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_05,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_old_pay_cnt >= 10) AS hit_hist_amount_7d_05,
        countIf(pre_old_pay_cnt >= 10 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_05,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_old_pay_cnt >= 10) AS hit_hist_amount_after_recall_05,
        countIf(pre_old_pay_cnt >= 10 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_05,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_old_pay_cnt >= 10) AS hurt_attr_income_7d_05,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_old_pay_cnt >= 10) AS hurt_attr_income_after_recall_05,

        countIf(pre_old_pay_cnt >= 5) AS rule_user_cnt_06,
        countIf(pre_old_pay_cnt >= 5 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_06,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_old_pay_cnt >= 5) AS hit_hist_amount_7d_06,
        countIf(pre_old_pay_cnt >= 5 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_06,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_old_pay_cnt >= 5) AS hit_hist_amount_after_recall_06,
        countIf(pre_old_pay_cnt >= 5 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_06,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_old_pay_cnt >= 5) AS hurt_attr_income_7d_06,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_old_pay_cnt >= 5) AS hurt_attr_income_after_recall_06,

        countIf(pre_old_pay_cnt >= 3) AS rule_user_cnt_07,
        countIf(pre_old_pay_cnt >= 3 AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_07,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_old_pay_cnt >= 3) AS hit_hist_amount_7d_07,
        countIf(pre_old_pay_cnt >= 3 AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_07,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_old_pay_cnt >= 3) AS hit_hist_amount_after_recall_07,
        countIf(pre_old_pay_cnt >= 3 AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_07,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_old_pay_cnt >= 3) AS hurt_attr_income_7d_07,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_old_pay_cnt >= 3) AS hurt_attr_income_after_recall_07,

        countIf(pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AS rule_user_cnt_08,
        countIf((pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_08,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AS hit_hist_amount_7d_08,
        countIf((pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_08,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AS hit_hist_amount_after_recall_08,
        countIf((pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_08,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AS hurt_attr_income_7d_08,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 5 OR pre_old_pay_cnt >= 5) AS hurt_attr_income_after_recall_08,

        countIf(pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AS rule_user_cnt_09,
        countIf((pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_09,
        sumIf(`7日历史订单退款金额_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AS hit_hist_amount_7d_09,
        countIf((pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_09,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AS hit_hist_amount_after_recall_09,
        countIf((pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_09,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AS hurt_attr_income_7d_09,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, pre_try_repay_pay_cnt > 0 OR pre_auto_renew_pay_cnt >= 3 OR pre_old_pay_cnt >= 3) AS hurt_attr_income_after_recall_09,

        countIf(risk_pack = '重点观察包') AS rule_user_cnt_10,
        countIf(risk_pack = '重点观察包' AND `7日历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_7d_10,
        sumIf(`7日历史订单退款金额_剔除黑产`, risk_pack = '重点观察包') AS hit_hist_amount_7d_10,
        countIf(risk_pack = '重点观察包' AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS hit_hist_user_after_recall_10,
        sumIf(`召回后累计历史订单退款金额_剔除黑产`, risk_pack = '重点观察包') AS hit_hist_amount_after_recall_10,
        countIf(risk_pack = '重点观察包' AND `7日是否会员正向支付` = 1) AS hurt_pay_user_7d_10,
        sumIf(`7日会员净收入_召回归因口径_剔除黑产`, risk_pack = '重点观察包') AS hurt_attr_income_7d_10,
        sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, risk_pack = '重点观察包') AS hurt_attr_income_after_recall_10
    FROM risk_pack
)

SELECT
    tupleElement(rule, 2) AS `候选排除规则`,
    tupleElement(rule, 3) AS `候选包用户数`,
    round(tupleElement(rule, 3) / total_recall_user_cnt, 6) AS `占召回用户比例`,
    tupleElement(rule, 4) AS `命中7日历史退款用户数`,
    if(total_hist_user_7d = 0, 0, round(tupleElement(rule, 4) / total_hist_user_7d, 4)) AS `覆盖7日历史退款用户比例`,
    tupleElement(rule, 5) AS `覆盖7日历史退款金额`,
    if(total_hist_amount_7d_abs = 0, 0, round(abs(tupleElement(rule, 5)) / total_hist_amount_7d_abs, 4)) AS `覆盖7日历史退款金额比例`,
    tupleElement(rule, 6) AS `命中累计历史退款用户数`,
    if(total_hist_user_after_recall = 0, 0, round(tupleElement(rule, 6) / total_hist_user_after_recall, 4)) AS `覆盖累计历史退款用户比例`,
    tupleElement(rule, 7) AS `覆盖累计历史退款金额`,
    if(total_hist_amount_after_recall_abs = 0, 0, round(abs(tupleElement(rule, 7)) / total_hist_amount_after_recall_abs, 4)) AS `覆盖累计历史退款金额比例`,
    tupleElement(rule, 8) AS `可能误伤7日支付用户数`,
    tupleElement(rule, 9) AS `可能误伤7日归因净收入`,
    tupleElement(rule, 10) AS `可能误伤累计归因净收入`
FROM candidate_scan
ARRAY JOIN arrayZip(
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    ['补扣支付', '自动续费>=10次', '自动续费>=5次', '自动续费>=3次', '老订单>=10次', '老订单>=5次', '老订单>=3次', '补扣或自动续费>=5或老订单>=5', '补扣或自动续费>=3或老订单>=3', '当前重点观察包规则'],
    [rule_user_cnt_01, rule_user_cnt_02, rule_user_cnt_03, rule_user_cnt_04, rule_user_cnt_05, rule_user_cnt_06, rule_user_cnt_07, rule_user_cnt_08, rule_user_cnt_09, rule_user_cnt_10],
    [hit_hist_user_7d_01, hit_hist_user_7d_02, hit_hist_user_7d_03, hit_hist_user_7d_04, hit_hist_user_7d_05, hit_hist_user_7d_06, hit_hist_user_7d_07, hit_hist_user_7d_08, hit_hist_user_7d_09, hit_hist_user_7d_10],
    [hit_hist_amount_7d_01, hit_hist_amount_7d_02, hit_hist_amount_7d_03, hit_hist_amount_7d_04, hit_hist_amount_7d_05, hit_hist_amount_7d_06, hit_hist_amount_7d_07, hit_hist_amount_7d_08, hit_hist_amount_7d_09, hit_hist_amount_7d_10],
    [hit_hist_user_after_recall_01, hit_hist_user_after_recall_02, hit_hist_user_after_recall_03, hit_hist_user_after_recall_04, hit_hist_user_after_recall_05, hit_hist_user_after_recall_06, hit_hist_user_after_recall_07, hit_hist_user_after_recall_08, hit_hist_user_after_recall_09, hit_hist_user_after_recall_10],
    [hit_hist_amount_after_recall_01, hit_hist_amount_after_recall_02, hit_hist_amount_after_recall_03, hit_hist_amount_after_recall_04, hit_hist_amount_after_recall_05, hit_hist_amount_after_recall_06, hit_hist_amount_after_recall_07, hit_hist_amount_after_recall_08, hit_hist_amount_after_recall_09, hit_hist_amount_after_recall_10],
    [hurt_pay_user_7d_01, hurt_pay_user_7d_02, hurt_pay_user_7d_03, hurt_pay_user_7d_04, hurt_pay_user_7d_05, hurt_pay_user_7d_06, hurt_pay_user_7d_07, hurt_pay_user_7d_08, hurt_pay_user_7d_09, hurt_pay_user_7d_10],
    [hurt_attr_income_7d_01, hurt_attr_income_7d_02, hurt_attr_income_7d_03, hurt_attr_income_7d_04, hurt_attr_income_7d_05, hurt_attr_income_7d_06, hurt_attr_income_7d_07, hurt_attr_income_7d_08, hurt_attr_income_7d_09, hurt_attr_income_7d_10],
    [hurt_attr_income_after_recall_01, hurt_attr_income_after_recall_02, hurt_attr_income_after_recall_03, hurt_attr_income_after_recall_04, hurt_attr_income_after_recall_05, hurt_attr_income_after_recall_06, hurt_attr_income_after_recall_07, hurt_attr_income_after_recall_08, hurt_attr_income_after_recall_09, hurt_attr_income_after_recall_10]
) AS rule
ORDER BY
    `占召回用户比例` ASC,
    `覆盖7日历史退款金额比例` DESC,
    tupleElement(rule, 1);
*/


/* 7.4 补扣支付细拆候选规则扫描：继续寻找更小、更准的直接排除包

操作方式：
1. 把下方 “这里放会员底表 SQL” 替换成当前会员底表 SQL。
2. 选中本段单独运行，不要直接运行整个 SQL 文件。

说明：
- 7.3 已确认 `补扣支付` 能覆盖全部 7 日历史订单退款，但人群包过大，不能直接排除。
- 本段只使用召回日期之前可见的订单特征，继续细拆补扣支付：
  补扣次数、最近补扣时间、是否叠加高频自动续费、历史支付次数、老订单、历史退款等。
- 因候选规则是在用户粒度展开，使用 countIf 即可，不使用 uniqExactIf，降低 ClickHouse 21.3 内存压力。
- 判断直接排除候选规则时优先看：
  候选包用户数及占召回比例、覆盖 7 日历史退款金额比例、可能误伤累计归因净收入。
*/
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,

base_raw AS
(
    SELECT *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

base AS
(
    SELECT
        b.*,
        ifNull(u.blocked_flag, 0) AS blocked_flag
    FROM base_raw AS b
    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON b.`用户ID` = u.uid
),

pre_feature AS
(
    SELECT
        b.`用户ID`,
        b.`召回日期`,
        b.`召回月份`,
        b.`平台`,
        b.`七类人群`,
        b.`沉默天数`,
        b.`召回标签`,
        b.`7日是否会员正向支付`,
        b.`7日历史订单退款金额_剔除黑产`,
        b.`7日会员净收入_召回归因口径_剔除黑产`,
        b.`召回后累计历史订单退款金额_剔除黑产`,
        b.`召回后累计会员净收入_召回归因口径_剔除黑产`,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
        ) AS pre_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_auto_renew = 1
        ) AS pre_auto_renew_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_old_pay = 1
        ) AS pre_old_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_cnt,

        sumIf(
            d.cost_float,
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_amount,

        maxIf(
            d.income_date,
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_try_repay = 1
        ) AS pre_try_repay_last_date,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 30 AND b.`召回日期` - 1
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_cnt_30d,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 90 AND b.`召回日期` - 1
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_cnt_90d,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 180 AND b.`召回日期` - 1
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_cnt_180d,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 365 AND b.`召回日期` - 1
            AND d.is_try_repay = 1
        ) AS pre_try_repay_pay_cnt_365d,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_try_repay = 1
            AND d.is_auto_renew = 1
        ) AS pre_try_repay_auto_renew_pay_cnt,

        countIf(
            d.order_type IN (1, 3)
            AND d.is_minus = 0
            AND d.cost_float > 0
            AND d.income_date < b.`召回日期`
            AND d.is_try_repay = 1
            AND d.is_old_pay = 1
        ) AS pre_try_repay_old_pay_cnt,

        countIf(
            d.order_type IN (4, 5)
            AND d.is_minus = 1
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 365 AND b.`召回日期` - 1
        ) AS pre_refund_cnt_365d,

        sumIf(
            0 - abs(d.cost_float),
            d.order_type IN (4, 5)
            AND d.is_minus = 1
            AND d.cost_float > 0
            AND d.income_date BETWEEN b.`召回日期` - 365 AND b.`召回日期` - 1
        ) AS pre_refund_amount_365d
    FROM base AS b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            toDateOrNull(toString(income_ts)) AS income_date,
            order_type,
            is_minus,
            toFloat64(cost) AS cost_float,
            is_auto_renew,
            is_try_repay,
            is_old_pay,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) < end_date
          AND order_type IN (1, 3, 4, 5)
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS d
        ON b.`用户ID` = d.uid
    GROUP BY
        b.`用户ID`,
        b.`召回日期`,
        b.`召回月份`,
        b.`平台`,
        b.`七类人群`,
        b.`沉默天数`,
        b.`召回标签`,
        b.`7日是否会员正向支付`,
        b.`7日历史订单退款金额_剔除黑产`,
        b.`7日会员净收入_召回归因口径_剔除黑产`,
        b.`召回后累计历史订单退款金额_剔除黑产`,
        b.`召回后累计会员净收入_召回归因口径_剔除黑产`
),

rule_rows AS
(
    SELECT
        *,
        tupleElement(rule, 1) AS rule_priority,
        tupleElement(rule, 2) AS rule_name,
        tupleElement(rule, 3) AS is_hit_rule
    FROM pre_feature
    ARRAY JOIN arrayZip(
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
        [
            '补扣次数>=2',
            '补扣次数>=3',
            '补扣次数>=5',
            '补扣次数>=10',
            '近30天有补扣',
            '近90天有补扣',
            '近180天有补扣',
            '近365天有补扣',
            '补扣且自动续费>=10次',
            '补扣且自动续费>=5次',
            '补扣且自动续费>=3次',
            '补扣>=2且自动续费>=3次',
            '补扣>=2且自动续费>=5次',
            '补扣且历史支付>=10次',
            '补扣且历史支付>=5次',
            '补扣且老订单>=3次',
            '补扣且召回前365天退款>=1次',
            '补扣金额>=300',
            '补扣金额>=500',
            '补扣>=2且近180天有补扣'
        ],
        [
            pre_try_repay_pay_cnt >= 2,
            pre_try_repay_pay_cnt >= 3,
            pre_try_repay_pay_cnt >= 5,
            pre_try_repay_pay_cnt >= 10,
            pre_try_repay_pay_cnt_30d > 0,
            pre_try_repay_pay_cnt_90d > 0,
            pre_try_repay_pay_cnt_180d > 0,
            pre_try_repay_pay_cnt_365d > 0,
            pre_try_repay_pay_cnt > 0 AND pre_auto_renew_pay_cnt >= 10,
            pre_try_repay_pay_cnt > 0 AND pre_auto_renew_pay_cnt >= 5,
            pre_try_repay_pay_cnt > 0 AND pre_auto_renew_pay_cnt >= 3,
            pre_try_repay_pay_cnt >= 2 AND pre_auto_renew_pay_cnt >= 3,
            pre_try_repay_pay_cnt >= 2 AND pre_auto_renew_pay_cnt >= 5,
            pre_try_repay_pay_cnt > 0 AND pre_pay_cnt >= 10,
            pre_try_repay_pay_cnt > 0 AND pre_pay_cnt >= 5,
            pre_try_repay_pay_cnt > 0 AND pre_old_pay_cnt >= 3,
            pre_try_repay_pay_cnt > 0 AND pre_refund_cnt_365d >= 1,
            pre_try_repay_pay_amount >= 300,
            pre_try_repay_pay_amount >= 500,
            pre_try_repay_pay_cnt >= 2 AND pre_try_repay_pay_cnt_180d > 0
        ]
    ) AS rule
)

SELECT
    rule_name AS `候选排除规则`,
    countIf(is_hit_rule) AS `候选包用户数`,
    round(`候选包用户数` / count(), 6) AS `占召回用户比例`,
    countIf(is_hit_rule AND `7日历史订单退款金额_剔除黑产` < 0) AS `命中7日历史退款用户数`,
    if(
        countIf(`7日历史订单退款金额_剔除黑产` < 0) = 0,
        0,
        round(`命中7日历史退款用户数` / countIf(`7日历史订单退款金额_剔除黑产` < 0), 4)
    ) AS `覆盖7日历史退款用户比例`,
    sumIf(`7日历史订单退款金额_剔除黑产`, is_hit_rule) AS `覆盖7日历史退款金额`,
    if(
        abs(sum(`7日历史订单退款金额_剔除黑产`)) = 0,
        0,
        round(abs(`覆盖7日历史退款金额`) / abs(sum(`7日历史订单退款金额_剔除黑产`)), 4)
    ) AS `覆盖7日历史退款金额比例`,
    countIf(is_hit_rule AND `召回后累计历史订单退款金额_剔除黑产` < 0) AS `命中累计历史退款用户数`,
    sumIf(`召回后累计历史订单退款金额_剔除黑产`, is_hit_rule) AS `覆盖累计历史退款金额`,
    if(
        abs(sum(`召回后累计历史订单退款金额_剔除黑产`)) = 0,
        0,
        round(abs(`覆盖累计历史退款金额`) / abs(sum(`召回后累计历史订单退款金额_剔除黑产`)), 4)
    ) AS `覆盖累计历史退款金额比例`,
    countIf(is_hit_rule AND `7日是否会员正向支付` = 1) AS `可能误伤7日支付用户数`,
    sumIf(`7日会员净收入_召回归因口径_剔除黑产`, is_hit_rule) AS `可能误伤7日归因净收入`,
    sumIf(`召回后累计会员净收入_召回归因口径_剔除黑产`, is_hit_rule) AS `可能误伤累计归因净收入`,
    if(
        `候选包用户数` = 0,
        0,
        round(`命中7日历史退款用户数` / `候选包用户数`, 6)
    ) AS `候选包7日历史退款用户率`
FROM rule_rows
GROUP BY
    rule_priority,
    rule_name
ORDER BY
    `占召回用户比例` ASC,
    `覆盖7日历史退款金额比例` DESC,
    rule_priority;


/* 6.5 召回用户：拉长窗口看历史订单退款量级（7日 / 14日 / 30日 / 召回后累计）

说明：
- 为对齐会员底表主口径，原支付订单只按 order_type IN (1, 3) 识别；如后续纳入线下订单 order_type = 2，需要同步修改。
- pay_end_date 当前沿用报告口径 2026-04-30；若要完整观察 4 月下旬召回用户的 14/30 日窗口，需要把 pay_end_date 延长。
- complete_window_recall_user_cnt 表示窗口完整覆盖的召回用户数，例如 30 日窗口要求 召回日期 <= pay_end_date - 29。
- 只统计实际负向金额明细，排除 0 元退款/冲正记录，避免抬高历史退款用户数。
*/
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,
    end_date AS pay_end_date,

base_raw AS
(
    SELECT *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

base AS
(
    SELECT
        b.*,
        ifNull(u.blocked_flag, 0) AS blocked_flag
    FROM base_raw AS b
    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON b.`用户ID` = u.uid
),

refund_detail AS
(
    SELECT
        b.`用户ID` AS uid,
        b.`召回日期` AS recall_date,
        b.`召回月份` AS recall_month,
        b.`平台` AS platform_type,
        b.`七类人群` AS seven_class,
        b.`沉默天数` AS silent_days,
        dateDiff('day', b.`召回日期`, r.income_date) AS refund_days_after_recall,
        r.order_id AS order_id,
        r.income_date AS refund_date,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost
    FROM base AS b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            income_ts,
            toDateOrNull(toString(income_ts)) AS income_date,
            order_type,
            cost,
            is_minus,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) BETWEEN start_date AND pay_end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND toFloat64(cost) > 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS r
        ON b.`用户ID` = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
            count() AS origin_pay_cnt
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND order_type IN (1, 3)
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
    WHERE b.blocked_flag = 0
      AND r.income_ts IS NOT NULL
      AND r.income_date BETWEEN b.`召回日期` AND pay_end_date
      AND p.origin_pay_cnt > 0
      AND p.origin_pay_date < b.`召回日期`
)

SELECT
    window_name AS `观察窗口`,
    total_recall_user_cnt AS `召回用户数`,
    complete_window_recall_user_cnt AS `窗口完整覆盖召回用户数`,
    hist_refund_user_cnt AS `历史退款用户数`,
    round(hist_refund_user_cnt / total_recall_user_cnt, 6) AS `占全量召回用户比例`,
    round(hist_refund_user_cnt / complete_window_recall_user_cnt, 6) AS `占窗口完整用户比例`,
    hist_refund_order_cnt AS `历史退款笔数`,
    hist_refund_amount AS `历史退款金额`,
    if(hist_refund_user_cnt = 0, 0, hist_refund_amount / hist_refund_user_cnt) AS `历史退款人均金额`
FROM
(
    SELECT
        '7日' AS window_name,
        (SELECT uniqExact(`用户ID`) FROM base WHERE `召回日期` <= pay_end_date - 6) AS complete_window_recall_user_cnt,
        uniqExactIf(uid, refund_days_after_recall BETWEEN 0 AND 6) AS hist_refund_user_cnt,
        countIf(refund_days_after_recall BETWEEN 0 AND 6) AS hist_refund_order_cnt,
        sumIf(refund_signed_cost, refund_days_after_recall BETWEEN 0 AND 6) AS hist_refund_amount,
        (SELECT uniqExact(`用户ID`) FROM base) AS total_recall_user_cnt
    FROM refund_detail

    UNION ALL

    SELECT
        '14日' AS window_name,
        (SELECT uniqExact(`用户ID`) FROM base WHERE `召回日期` <= pay_end_date - 13) AS complete_window_recall_user_cnt,
        uniqExactIf(uid, refund_days_after_recall BETWEEN 0 AND 13) AS hist_refund_user_cnt,
        countIf(refund_days_after_recall BETWEEN 0 AND 13) AS hist_refund_order_cnt,
        sumIf(refund_signed_cost, refund_days_after_recall BETWEEN 0 AND 13) AS hist_refund_amount,
        (SELECT uniqExact(`用户ID`) FROM base) AS total_recall_user_cnt
    FROM refund_detail

    UNION ALL

    SELECT
        '30日' AS window_name,
        (SELECT uniqExact(`用户ID`) FROM base WHERE `召回日期` <= pay_end_date - 29) AS complete_window_recall_user_cnt,
        uniqExactIf(uid, refund_days_after_recall BETWEEN 0 AND 29) AS hist_refund_user_cnt,
        countIf(refund_days_after_recall BETWEEN 0 AND 29) AS hist_refund_order_cnt,
        sumIf(refund_signed_cost, refund_days_after_recall BETWEEN 0 AND 29) AS hist_refund_amount,
        (SELECT uniqExact(`用户ID`) FROM base) AS total_recall_user_cnt
    FROM refund_detail

    UNION ALL

    SELECT
        '召回后累计至统计截止日' AS window_name,
        (SELECT uniqExact(`用户ID`) FROM base) AS complete_window_recall_user_cnt,
        uniqExact(uid) AS hist_refund_user_cnt,
        count() AS hist_refund_order_cnt,
        sum(refund_signed_cost) AS hist_refund_amount,
        (SELECT uniqExact(`用户ID`) FROM base) AS total_recall_user_cnt
    FROM refund_detail
) AS s
ORDER BY
    multiIf(
        `观察窗口` = '7日', 1,
        `观察窗口` = '14日', 2,
        `观察窗口` = '30日', 3,
        4
    );


/* 6.6 召回用户：历史订单退款发生时间分布（非累计分段） */
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,
    end_date AS pay_end_date,

base_raw AS
(
    SELECT *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

base AS
(
    SELECT
        b.*,
        ifNull(u.blocked_flag, 0) AS blocked_flag
    FROM base_raw AS b
    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON b.`用户ID` = u.uid
),

refund_detail AS
(
    SELECT
        b.`用户ID` AS uid,
        dateDiff('day', b.`召回日期`, r.income_date) AS refund_days_after_recall,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost
    FROM base AS b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            income_ts,
            toDateOrNull(toString(income_ts)) AS income_date,
            cost,
            is_minus,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) BETWEEN start_date AND pay_end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND toFloat64(cost) > 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS r
        ON b.`用户ID` = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
            count() AS origin_pay_cnt
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND order_type IN (1, 3)
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
    WHERE b.blocked_flag = 0
      AND r.income_ts IS NOT NULL
      AND r.income_date BETWEEN b.`召回日期` AND pay_end_date
      AND p.origin_pay_cnt > 0
      AND p.origin_pay_date < b.`召回日期`
)

SELECT
    multiIf(
        refund_days_after_recall BETWEEN 0 AND 6, '0-6天',
        refund_days_after_recall BETWEEN 7 AND 13, '7-13天',
        refund_days_after_recall BETWEEN 14 AND 29, '14-29天',
        '30天后至统计截止日'
    ) AS `退款距召回时间段`,
    uniqExact(uid) AS `历史退款用户数`,
    count() AS `历史退款笔数`,
    sum(refund_signed_cost) AS `历史退款金额`,
    if(`历史退款用户数` = 0, 0, `历史退款金额` / `历史退款用户数`) AS `历史退款人均金额`
FROM refund_detail
GROUP BY `退款距召回时间段`
ORDER BY
    multiIf(
        `退款距召回时间段` = '0-6天', 1,
        `退款距召回时间段` = '7-13天', 2,
        `退款距召回时间段` = '14-29天', 3,
        4
    );


/* 6.7 召回用户：历史订单退款用户首次出现窗口，用于判断 7 日后新增量级 */
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,
    end_date AS pay_end_date,

base_raw AS
(
    SELECT *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

base AS
(
    SELECT
        b.*,
        ifNull(u.blocked_flag, 0) AS blocked_flag
    FROM base_raw AS b
    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON b.`用户ID` = u.uid
),

refund_detail AS
(
    SELECT
        b.`用户ID` AS uid,
        dateDiff('day', b.`召回日期`, r.income_date) AS refund_days_after_recall,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost
    FROM base AS b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            income_ts,
            toDateOrNull(toString(income_ts)) AS income_date,
            cost,
            is_minus,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) BETWEEN start_date AND pay_end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND toFloat64(cost) > 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS r
        ON b.`用户ID` = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
            count() AS origin_pay_cnt
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND order_type IN (1, 3)
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
    WHERE b.blocked_flag = 0
      AND r.income_ts IS NOT NULL
      AND r.income_date BETWEEN b.`召回日期` AND pay_end_date
      AND p.origin_pay_cnt > 0
      AND p.origin_pay_date < b.`召回日期`
),

user_hist_refund AS
(
    SELECT
        uid,
        min(refund_days_after_recall) AS first_refund_days_after_recall,
        count() AS hist_refund_order_cnt,
        sum(refund_signed_cost) AS hist_refund_amount
    FROM refund_detail
    GROUP BY uid
)

SELECT
    multiIf(
        first_refund_days_after_recall BETWEEN 0 AND 6, '首次出现在0-6天',
        first_refund_days_after_recall BETWEEN 7 AND 13, '首次出现在7-13天',
        first_refund_days_after_recall BETWEEN 14 AND 29, '首次出现在14-29天',
        '首次出现在30天后至统计截止日'
    ) AS `历史退款用户首次出现窗口`,
    uniqExact(uid) AS `历史退款用户数`,
    sum(hist_refund_order_cnt) AS `历史退款笔数`,
    sum(hist_refund_amount) AS `历史退款金额`,
    if(`历史退款用户数` = 0, 0, `历史退款金额` / `历史退款用户数`) AS `历史退款人均金额`
FROM user_hist_refund
GROUP BY `历史退款用户首次出现窗口`
ORDER BY
    multiIf(
        `历史退款用户首次出现窗口` = '首次出现在0-6天', 1,
        `历史退款用户首次出现窗口` = '首次出现在7-13天', 2,
        `历史退款用户首次出现窗口` = '首次出现在14-29天', 3,
        4
    );


/* 6.8 召回用户：拉长到统计截止日后的历史退款用户画像分布 */
WITH
    toDate('2026-02-01') AS start_date,
    toDate('2026-04-30') AS end_date,
    end_date AS pay_end_date,

base_raw AS
(
    SELECT *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

base AS
(
    SELECT
        b.*,
        multiIf(
            b.`沉默天数` BETWEEN 30 AND 35, '30-35天',
            b.`沉默天数` BETWEEN 36 AND 59, '36-59天',
            b.`沉默天数` BETWEEN 60 AND 100, '60-100天',
            b.`沉默天数` > 100, '100天以上',
            '其他'
        ) AS silent_bucket,
        ifNull(u.blocked_flag, 0) AS blocked_flag
    FROM base_raw AS b
    ANY LEFT JOIN
    (
        SELECT
            uid,
            any(ifNull(is_blocked, 0)) AS blocked_flag
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON b.`用户ID` = u.uid
),

refund_detail AS
(
    SELECT
        b.`用户ID` AS uid,
        b.`召回月份` AS recall_month,
        b.`平台` AS platform_type,
        b.`七类人群` AS seven_class,
        b.silent_bucket AS silent_bucket,
        dateDiff('day', b.`召回日期`, r.income_date) AS refund_days_after_recall,
        if(r.is_minus = 1, 0 - abs(toFloat64(r.cost)), abs(toFloat64(r.cost))) AS refund_signed_cost
    FROM base AS b
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            income_ts,
            toDateOrNull(toString(income_ts)) AS income_date,
            cost,
            is_minus,
            currency,
            is_ios
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND toDateOrNull(toString(income_ts)) BETWEEN start_date AND pay_end_date
          AND order_type IN (4, 5)
          AND st = 2
          AND is_minus = 1
          AND toFloat64(cost) > 0
          AND mem_id NOT IN (6, 10)
          AND NOT (
              is_ios = 1
              AND currency NOT IN ('USD', 'CNY', '')
              AND toDateTimeOrNull(toString(income_ts)) <= toDateTime('2024-06-01 00:00:00')
          )
    ) AS r
        ON b.`用户ID` = r.uid
    LEFT JOIN
    (
        SELECT
            uid,
            order_id,
            min(toDateOrNull(toString(income_ts))) AS origin_pay_date,
            count() AS origin_pay_cnt
        FROM dwd.dw_member_deal_all_da
        WHERE d = yesterday()
          AND order_type IN (1, 3)
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
    WHERE b.blocked_flag = 0
      AND r.income_ts IS NOT NULL
      AND r.income_date BETWEEN b.`召回日期` AND pay_end_date
      AND p.origin_pay_cnt > 0
      AND p.origin_pay_date < b.`召回日期`
),

user_hist_refund AS
(
    SELECT
        uid,
        any(seven_class) AS seven_class,
        any(platform_type) AS platform_type,
        any(silent_bucket) AS silent_bucket,
        any(toString(recall_month)) AS recall_month,
        min(refund_days_after_recall) AS first_refund_days_after_recall,
        count() AS hist_refund_order_cnt,
        sum(refund_signed_cost) AS hist_refund_amount
    FROM refund_detail
    GROUP BY uid
)

SELECT
    dim_name AS `维度`,
    dim_value AS `维度值`,
    uniqExact(uid) AS `历史退款用户数`,
    sum(hist_refund_order_cnt) AS `历史退款笔数`,
    sum(hist_refund_amount) AS `历史退款金额`,
    avg(first_refund_days_after_recall) AS `平均首次退款距召回天数`
FROM
(
    SELECT
        uid,
        '七类人群' AS dim_name,
        toString(seven_class) AS dim_value,
        first_refund_days_after_recall,
        hist_refund_order_cnt,
        hist_refund_amount
    FROM user_hist_refund

    UNION ALL

    SELECT
        uid,
        '平台' AS dim_name,
        toString(platform_type) AS dim_value,
        first_refund_days_after_recall,
        hist_refund_order_cnt,
        hist_refund_amount
    FROM user_hist_refund

    UNION ALL

    SELECT
        uid,
        '沉默区间' AS dim_name,
        silent_bucket AS dim_value,
        first_refund_days_after_recall,
        hist_refund_order_cnt,
        hist_refund_amount
    FROM user_hist_refund

    UNION ALL

    SELECT
        uid,
        '召回月份' AS dim_name,
        recall_month AS dim_value,
        first_refund_days_after_recall,
        hist_refund_order_cnt,
        hist_refund_amount
    FROM user_hist_refund
) AS s
GROUP BY
    dim_name,
    dim_value
ORDER BY
    `维度`,
    `历史退款金额`;


/* 6.1 召回用户：召回后 7 日内退款类型人数和金额，对齐会员底表口径 */
WITH
base AS
(
    SELECT
        *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

total AS
(
    SELECT
        uniqExact(`用户ID`) AS total_recall_user_cnt
    FROM base
)

SELECT
    refund_type AS `召回后7日退款类型`,
    refund_user_cnt AS `退款用户数`,
    round(refund_user_cnt / total_recall_user_cnt, 6) AS `占召回用户比例`,
    refund_amount AS `退款金额`
FROM
(
    SELECT
        '召回前历史订单退款' AS refund_type,
        uniqExactIf(`用户ID`, `7日历史订单退款金额_剔除黑产` < 0) AS refund_user_cnt,
        sum(`7日历史订单退款金额_剔除黑产`) AS refund_amount
    FROM base

    UNION ALL

    SELECT
        '召回后7日新订单退款' AS refund_type,
        uniqExactIf(`用户ID`, `7日召回后新订单退款金额_剔除黑产` < 0) AS refund_user_cnt,
        sum(`7日召回后新订单退款金额_剔除黑产`) AS refund_amount
    FROM base

    UNION ALL

    SELECT
        '未知原支付订单退款' AS refund_type,
        uniqExactIf(`用户ID`, `7日未知原支付订单退款金额_剔除黑产` < 0) AS refund_user_cnt,
        sum(`7日未知原支付订单退款金额_剔除黑产`) AS refund_amount
    FROM base
) AS s
CROSS JOIN total
ORDER BY `退款金额`;


/* 6.2 召回用户：7 日历史订单退款用户的人群特征分布 */
WITH
base AS
(
    SELECT
        *,
        multiIf(
            `沉默天数` BETWEEN 30 AND 35, '30-35天',
            `沉默天数` BETWEEN 36 AND 59, '36-59天',
            `沉默天数` BETWEEN 60 AND 100, '60-100天',
            `沉默天数` > 100, '100天以上',
            '其他'
        ) AS silent_bucket
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

hist_users AS
(
    SELECT *
    FROM base
    WHERE `7日历史订单退款金额_剔除黑产` < 0
),

total AS
(
    SELECT
        uniqExact(`用户ID`) AS hist_refund_user_cnt
    FROM hist_users
)

SELECT
    dim_name AS `维度`,
    dim_value AS `维度值`,
    user_cnt AS `历史退款用户数`,
    round(user_cnt / hist_refund_user_cnt, 4) AS `占历史退款用户比例`,
    refund_amount AS `历史退款金额`,
    pay_user_cnt_7d AS `其中7日正向支付用户数`,
    pay_income_7d AS `其中7日正向支付收入`,
    attr_net_income_7d AS `其中7日召回归因净收入`,
    attr_net_income_after_recall AS `其中召回后累计归因净收入`
FROM
(
    SELECT
        '七类人群' AS dim_name,
        toString(`七类人群`) AS dim_value,
        uniqExact(`用户ID`) AS user_cnt,
        sum(`7日历史订单退款金额_剔除黑产`) AS refund_amount,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_after_recall
    FROM hist_users
    GROUP BY `七类人群`

    UNION ALL

    SELECT
        '平台' AS dim_name,
        toString(`平台`) AS dim_value,
        uniqExact(`用户ID`) AS user_cnt,
        sum(`7日历史订单退款金额_剔除黑产`) AS refund_amount,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_after_recall
    FROM hist_users
    GROUP BY `平台`

    UNION ALL

    SELECT
        '沉默区间' AS dim_name,
        silent_bucket AS dim_value,
        uniqExact(`用户ID`) AS user_cnt,
        sum(`7日历史订单退款金额_剔除黑产`) AS refund_amount,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_after_recall
    FROM hist_users
    GROUP BY silent_bucket

    UNION ALL

    SELECT
        '召回月份' AS dim_name,
        toString(`召回月份`) AS dim_value,
        uniqExact(`用户ID`) AS user_cnt,
        sum(`7日历史订单退款金额_剔除黑产`) AS refund_amount,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS attr_net_income_after_recall
    FROM hist_users
    GROUP BY `召回月份`
) AS s
CROSS JOIN total
ORDER BY
    `维度`,
    `历史退款金额`;


/* 6.3 召回用户：如果排除 7 日历史订单退款用户，召回量级和会员收入影响 */
WITH
base AS
(
    SELECT
        *
    FROM
    (
        /* 这里放会员底表 SQL */
    )
),

total AS
(
    SELECT
        uniqExact(`用户ID`) AS total_recall_user_cnt
    FROM base
)

SELECT
    cohort AS `人群`,
    recall_user_cnt AS `召回用户数`,
    round(recall_user_cnt / total_recall_user_cnt, 6) AS `占召回用户比例`,
    pay_user_cnt_7d AS `7日正向支付用户数`,
    pay_income_7d AS `7日正向支付收入`,
    refund_cash_7d AS `7日退款金额_现金流口径`,
    hist_refund_7d AS `7日历史订单退款金额`,
    new_order_refund_7d AS `7日召回后新订单退款金额`,
    net_cash_7d AS `7日现金流净收入`,
    net_attr_7d AS `7日召回归因净收入`,
    net_attr_after_recall AS `召回后累计归因净收入`
FROM
(
    SELECT
        '全量召回用户' AS cohort,
        uniqExact(`用户ID`) AS recall_user_cnt,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日退款金额_现金流口径_剔除黑产`) AS refund_cash_7d,
        sum(`7日历史订单退款金额_剔除黑产`) AS hist_refund_7d,
        sum(`7日召回后新订单退款金额_剔除黑产`) AS new_order_refund_7d,
        sum(`7日会员净收入_现金流口径_剔除黑产`) AS net_cash_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS net_attr_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS net_attr_after_recall
    FROM base

    UNION ALL

    SELECT
        '拟排除：7日历史订单退款用户' AS cohort,
        uniqExact(`用户ID`) AS recall_user_cnt,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日退款金额_现金流口径_剔除黑产`) AS refund_cash_7d,
        sum(`7日历史订单退款金额_剔除黑产`) AS hist_refund_7d,
        sum(`7日召回后新订单退款金额_剔除黑产`) AS new_order_refund_7d,
        sum(`7日会员净收入_现金流口径_剔除黑产`) AS net_cash_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS net_attr_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS net_attr_after_recall
    FROM base
    WHERE `7日历史订单退款金额_剔除黑产` < 0

    UNION ALL

    SELECT
        '排除后剩余召回用户' AS cohort,
        uniqExact(`用户ID`) AS recall_user_cnt,
        uniqExactIf(`用户ID`, `7日是否会员正向支付` = 1) AS pay_user_cnt_7d,
        sum(`7日会员正向支付收入_剔除黑产`) AS pay_income_7d,
        sum(`7日退款金额_现金流口径_剔除黑产`) AS refund_cash_7d,
        sum(`7日历史订单退款金额_剔除黑产`) AS hist_refund_7d,
        sum(`7日召回后新订单退款金额_剔除黑产`) AS new_order_refund_7d,
        sum(`7日会员净收入_现金流口径_剔除黑产`) AS net_cash_7d,
        sum(`7日会员净收入_召回归因口径_剔除黑产`) AS net_attr_7d,
        sum(`召回后累计会员净收入_召回归因口径_剔除黑产`) AS net_attr_after_recall
    FROM base
    WHERE `7日历史订单退款金额_剔除黑产` >= 0
) AS s
CROSS JOIN total
ORDER BY
    multiIf(
        `人群` = '全量召回用户', 1,
        `人群` = '拟排除：7日历史订单退款用户', 2,
        3
    );


/* 6.4 召回用户：拟排除的 7 日历史订单退款用户明细，对齐会员底表口径 */
WITH
base AS
(
    SELECT
        *,
        multiIf(
            `沉默天数` BETWEEN 30 AND 35, '30-35天',
            `沉默天数` BETWEEN 36 AND 59, '36-59天',
            `沉默天数` BETWEEN 60 AND 100, '60-100天',
            `沉默天数` > 100, '100天以上',
            '其他'
        ) AS silent_bucket
    FROM
    (
        /* 这里放会员底表 SQL */
    )
)

SELECT
    `用户ID`,
    `召回日期`,
    `召回月份`,
    `平台`,
    `七类人群`,
    `沉默天数`,
    silent_bucket AS `沉默区间`,
    `召回标签`,
    `7日是否会员正向支付`,
    `7日会员正向支付收入_剔除黑产`,
    `7日历史订单退款金额_剔除黑产`,
    `7日召回后新订单退款金额_剔除黑产`,
    `7日会员净收入_现金流口径_剔除黑产`,
    `7日会员净收入_召回归因口径_剔除黑产`,
    `召回后累计会员净收入_召回归因口径_剔除黑产`
FROM base
WHERE `7日历史订单退款金额_剔除黑产` < 0
ORDER BY
    `7日历史订单退款金额_剔除黑产` ASC,
    `召回日期` DESC
LIMIT 10000;


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
