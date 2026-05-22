# 沉默60非学生短信召回CAC测算_MEMORY

## 1. 当前项目背景

当前任务来自 MT：需要给短信通道准备一批召回人群包，并评估“除学生外的沉默60+用户”是否适合短信投放。

原始需求核心是：

- 人群：除学生外的沉默60+用户。
- 通道：短信通道。
- 频次：一个月发2次。
- 成本约束：CAC 控制在 5 元以内。
- 参考历史：历史上这个沉默区间用户发过短信，需要拉长时间看人群成本、频次效果、召回回来用户特征。

本轮已经完成：

- 解释并明确了“测算”的业务含义：用历史数据评估当前方案是否能把 CAC 控制在 5 元以内。
- 写了历史测算 SQL：
  - `沉默60非学生短信召回CAC测算.sql`
  - `沉默60非学生短信召回CAC方案汇总.sql`
- 经过多次修正，最终口径改为“当日召回”，而不是 7 日召回。
- 根据历史结果初步判断：
  - 如果按“每月最多2次、召回后停发”的策略，看 `05_60天+ + 02_实际月发1-2次`。
  - 历史各月该方案 CAC 均低于 5 元。
  - 在最多2次频次约束下，`非学生沉默60+全量` 是召回量级最大的方案。

当前做到的阶段：

- 历史效果测算已完成。
- 方案汇总 SQL 已可跑出结果。
- 还未正式拉当前可投放人群包。

## 2. 已确认的关键口径

### 2.1 学生排除口径

已确认：

```text
dim.dim_user.five_class = '学生'
```

排除学生写法：

```sql
ifNull(nullIf(trimBoth(toString(u.five_class)), ''), '未知') != '学生'
```

### 2.2 沉默60+口径

历史测算中最终采用：

```sql
dws.dw_sms_di.d - dws.dw_sms_di.last_active_date >= 60
```

原因：

- 历史短信发送明细 `dws.dw_sms_di` 中有发送日期 `d` 和 `last_active_date`。
- 可用 `d - last_active_date` 还原“发送当天的沉默天数”。

当前人群包建议口径：

```sql
today() - dim.dim_user.last_active_date >= 60
```

### 2.3 召回口径

MT 后续明确：看“当日召回”。

最终采用：

```text
短信发送成功用户中，发送当天在 dws.dw_dau 出现，且 is_puppet = 0 的去重用户数。
```

SQL 逻辑：

```sql
ANY LEFT JOIN
(
    SELECT
        toUInt64(uid) AS uid,
        d AS send_date,
        1 AS has_day_active
    FROM dws.dw_dau
    WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
      AND is_puppet = 0
    GROUP BY uid, send_date
) AS active
    ON s.uid = active.uid
   AND s.send_date = active.send_date
```

召回人数：

```sql
uniqExactIf(s.uid, ifNull(active.has_day_active, 0) = 1) AS `当日活跃召回用户数`
```

### 2.4 时间口径

历史测算起始日期：

```sql
toDate('2026-01-01')
```

当日召回口径不需要等待 7 天观察窗口，所以结束日期使用：

```sql
yesterday()
```

曾经用过 `yesterday() - 6` 是为了 7 日召回窗口完整；改成当日召回后已不再需要。

### 2.5 主表和 JOIN 逻辑

历史测算主表：

```text
dws.dw_sms_di
```

主表筛选：

```sql
d BETWEEN toDate('2026-01-01') AND yesterday()
AND is_send_success = 1
AND (
       tag LIKE 'recall%'
    OR tag LIKE 'bonus%'
    OR tag LIKE '%mengwang%'
)
AND tag NOT LIKE 'recall_phone%'
AND tag NOT LIKE '%wechat%'
AND tag NOT LIKE 'recall_push%'
AND tag NOT LIKE '%fumeiti%'
AND tag NOT LIKE 'recall_today_1_send_msg%'
AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
AND d - last_active_date >= 60
```

用户标签 JOIN：

```sql
dim.dim_user
```

用于：

- 排除学生：`five_class != '学生'`
- 排除黑名单：`is_blocked = 0`

当日活跃 JOIN：

```sql
dws.dw_dau
```

用于判断发送当天是否活跃。

月发送次数 JOIN：

再次从 `dws.dw_sms_di` 按 `uid + send_month` 汇总：

```sql
count() AS send_success_cnt
```

用于判断用户当月实际收到短信次数。

### 2.6 用户去重口径

发送成功用户数：

```sql
uniqExact(s.uid)
```

当日活跃召回用户数：

```sql
uniqExactIf(s.uid, ifNull(active.has_day_active, 0) = 1)
```

同一个用户当月多次发送，只要某次发送当天活跃，在对应方案里召回人数只计 1 个去重用户。

### 2.7 成本口径

短信计费条数按文案长度折算：

```sql
multiIf(
    cnt_len < 71, 1,
    cnt_len >= 71 AND cnt_len <= 134, 2,
    cnt_len >= 135 AND cnt_len <= 201, 3,
    4
) AS msg_cnt
```

成本：

```sql
msg_cnt * unit_price AS fee
```

通道单价沿用现有看板/周报中已有规则，例如：

- `秒信HDHC`: 0.027
- `创蓝hdhc1`: 0.03
- `阿里云1`: 0.027
- `文本短信-3日前`: 0.03
- `视频短信`: 0.076
- `微信/特殊push`: 0

### 2.8 CAC 计算

当前最终口径：

```text
CAC = 短信成本 / 当日活跃召回用户数
```

SQL：

```sql
round(`短信成本` / nullIf(`当日活跃召回用户数`, 0), 2) AS `CAC`
```

`CAC5元所需召回用户数` 含义：

```text
在当前短信成本下，如果要把 CAC 控制在 5 元以内，至少需要召回多少用户。
```

SQL：

```sql
ceil(`短信成本` / 5) AS `CAC5元所需召回用户数`
```

`CAC5元所需召回率`：

```text
CAC5元所需召回用户数 / 发送成功用户数
```

### 2.9 频次方案含义

在 `沉默60非学生短信召回CAC方案汇总.sql` 中：

- `01_实际全频次`：不管用户当月实际收到几次短信，全部合并统计。
- `02_实际月发1-2次`：用户当月实际收到 1 次或 2 次短信。
- `03_实际月发1次`：用户当月实际收到 1 次短信。
- `04_实际月发2次`：用户当月实际收到 2 次短信。
- `05_实际月发3次及以上`：用户当月实际收到 3 次及以上短信。

业务解释：

- MT 原始要求是“一个月发2次”。
- 但业务机制是：如果用户被召回，就不会继续发。
- 所以更接近“每月最多2次、召回后停发”的历史效果的是：

```text
02_实际月发1-2次
```

不是单独看：

```text
04_实际月发2次
```

### 2.10 人群方案含义

在 `沉默60非学生短信召回CAC方案汇总.sql` 中：

- `01_60-89天`
- `02_90-179天`
- `03_180天+`
- `04_60-179天`
- `05_60天+`

主方案建议看：

```text
05_60天+ + 02_实际月发1-2次
```

含义：

```text
非学生沉默60+全量，历史实际月发1-2次，近似每月最多2次、召回后停发。
```

## 3. 已经踩过的坑和错误

### 3.1 ClickHouse 聚合别名被 WHERE 误解析

- 问题：

```text
Code: 184
Aggregate function any(silent_days) is found in WHERE
```

- 原因：

曾写过：

```sql
any(silent_days) AS silent_days
...
WHERE silent_days >= 60
```

ClickHouse 21.3 将 `WHERE` 中的 `silent_days` 误解析成聚合别名。

- 修正：

内层先过滤原始字段，外层再聚合：

```sql
SELECT
    uid,
    d,
    any(raw_silent_days) AS silent_days
FROM
(
    SELECT
        toUInt64(uid) AS uid,
        d,
        silent_days AS raw_silent_days
    FROM ...
    WHERE silent_days >= 60
)
GROUP BY uid, d
```

后来最终弃用了 `dwm.dw_growth_user_active_di.silent_days`，改用 `dws.dw_sms_di.d - last_active_date`。

### 3.2 ClickHouse 21.3 多层 CTE / 子查询别名解析失败

- 问题：

```text
Code: 47
Missing columns: 'msg_cnt' 'send_month' 'fee' 'send_date' 'uid'
```

以及：

```text
There's no column 'base.uid' in table 'base'
```

- 原因：

ClickHouse 21.3 对多层 CTE、复杂子查询别名、`base.uid` 这类前缀字段解析不稳定。

- 修正：

尽量避免：

```sql
WITH target_send AS (...), user_month AS (...)
```

以及避免在上一层使用：

```sql
base.uid
```

最终做法：

- 主查询直接 JOIN 后聚合。
- 方案汇总 SQL 中直接在主查询层用 `arrayJoin(...) AS 人群方案 / 频次方案`。

### 3.3 ClickHouse 21.3 对 WITH 日期别名下推失败

- 问题：

```text
Code: 10
Not found column and(greaterOrEquals(d, start_date), lessOrEquals(d, end_date)) in block.
```

- 原因：

ClickHouse 21.3 对：

```sql
WITH toDate('2026-01-01') AS start_date
WHERE d BETWEEN start_date AND end_date
```

下推到 MergeTree 时不稳定。

- 修正：

直接写原始日期表达式：

```sql
WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
```

### 3.4 一开始用 7 日召回，后来被 MT 改成当日召回

- 问题：

最初按“发送后 7 天内活跃”计算召回：

```text
发送日 d 到 d+6
```

- 原因：

起初用户认为可以看 7 日召回，后来 MT 明确说要看“当日召回”。

- 修正：

召回 JOIN 从 `d 到 d+6` 改成只按：

```sql
s.send_date = active.send_date
```

并将发送结束日期从：

```sql
yesterday() - 6
```

改为：

```sql
yesterday()
```

### 3.5 用 `dwm.dw_growth_user_active_di` 筛沉默导致召回率 100%

- 问题：

最初跑出的结果中：

```text
7日活跃召回用户数 = 发送成功用户数
7日活跃召回率 = 1
```

- 原因：

用 `dwm.dw_growth_user_active_di.silent_days >= 60` 去筛发送当天沉默用户，结果这张表更像活跃/召回用户行为表，不适合做历史发送人群底表。等于先筛到了活跃用户，再判断是否活跃。

- 修正：

改用短信发送明细表自己的历史沉默口径：

```sql
dws.dw_sms_di.d - dws.dw_sms_di.last_active_date >= 60
```

### 3.6 “月发2次”不能只看实际月发2次

- 问题：

一开始容易误解为只看：

```text
04_实际月发2次
```

- 原因：

业务机制是“如果第一次发后召回了，当月后续不会再发”。因此第 1 次就召回的人会落在“实际月发1次”里。

- 修正：

近似看“每月最多2次、召回后停发”的历史效果，应看：

```text
02_实际月发1-2次
```

## 4. 当前使用/讨论过的代码或 SQL 逻辑

### 4.1 明细测算 SQL

文件：

```text
沉默60非学生短信召回CAC测算.sql
```

作用：

- 按月份、沉默区间、实际月发送频次输出明细。
- 适合排查不同沉默区间、不同实际频次下的成本、召回率、CAC。

模块说明：

1. 主表 `s`
  - 来自 `dws.dw_sms_di`
  - 筛发送成功短信
  - 筛召回短信标签
  - 排除电话、微信、push、视频短信等非文本短信口径
  - 用 `d - last_active_date >= 60` 筛沉默60+
  - 计算 `msg_cnt`、`unit_price`、`fee`
2. 用户标签 `u`
  - 来自 `dim.dim_user`
  - 排除 `five_class = '学生'`
  - 排除 `is_blocked = 1`
3. 当日活跃 `active`
  - 来自 `dws.dw_dau`
  - 按 `uid + send_date` 判断是否当天活跃
  - 排除 `is_puppet = 1`
4. 月发送次数 `f`
  - 再次从 `dws.dw_sms_di` 按 `uid + send_month` 统计 `send_success_cnt`
  - 用于划分月发1次、2次、3次及以上

### 4.2 方案汇总 SQL

文件：

```text
沉默60非学生短信召回CAC方案汇总.sql
```

作用：

- 回答新命题：

```text
在 CAC <= 5 元约束下，非学生沉默60+以召回量级最大为目标，应该选择哪个方案。
```

核心逻辑：

1. 主查询直接用 `arrayJoin` 展开人群方案：

```sql
arrayJoin(
    arrayConcat(
        if(s.silent_bucket = '60-89天', ['01_60-89天'], emptyArrayString()),
        if(s.silent_bucket = '90-179天', ['02_90-179天'], emptyArrayString()),
        if(s.silent_bucket = '180天+', ['03_180天+'], emptyArrayString()),
        if(s.silent_bucket IN ('60-89天', '90-179天'), ['04_60-179天'], emptyArrayString()),
        ['05_60天+']
    )
) AS `人群方案`
```

1. 主查询直接用 `arrayJoin` 展开频次方案：

```sql
arrayJoin(
    arrayConcat(
        ['01_实际全频次'],
        if(ifNull(f.send_success_cnt, 1) <= 2, ['02_实际月发1-2次'], emptyArrayString()),
        if(ifNull(f.send_success_cnt, 1) = 1, ['03_实际月发1次'], emptyArrayString()),
        if(ifNull(f.send_success_cnt, 1) = 2, ['04_实际月发2次'], emptyArrayString()),
        if(ifNull(f.send_success_cnt, 1) >= 3, ['05_实际月发3次及以上'], emptyArrayString())
    )
) AS `频次方案`
```

1. 输出指标：

- `发送成功用户数`
- `发送成功消息数`
- `计费短信条数`
- `人均月发送次数`
- `当日活跃召回用户数`
- `当日活跃召回率`
- `短信成本`
- `CAC`
- `是否满足CAC5元`
- `CAC5元所需召回用户数`
- `CAC5元所需召回率`

### 4.3 当前关键结论

基于已跑出的方案汇总结果：

主方案：

```text
人群方案 = 05_60天+
频次方案 = 02_实际月发1-2次
```

历史表现：

```text
2026-01：召回 4,878，CAC 0.91
2026-02：召回 433，CAC 0.44
2026-03：召回 14,721，CAC 0.41
2026-04：召回 856，CAC 1.14
2026-05：召回 411，CAC 0.55
```

结论：

```text
在 CAC <= 5 元约束下，若频次限制为每月最多2次，则推荐覆盖非学生沉默60+全量用户。
历史1-5月该方案当日召回CAC均低于5元，且在最多2次频次约束下召回量最大。
```

补充：

- 如果不限制频次，历史上 `05_60天+ + 01_实际全频次` 通常召回量更大，且整体 CAC 多数也低于 5。
- 但这不符合“一个月发2次”的原始限制。
- `180天+` 高频容易出现 CAC 超 5 的风险，例如：
  - `03_180天+ + 01_实际全频次` 多个月份不满足 CAC 5 元。
  - `03_180天+ + 05_实际月发3次及以上` 多个月份不满足 CAC 5 元。

## 5. 当前未解决的问题

1. 当前可投放人群包还没有正式产出。
2. `dim.dim_user` 中用于短信通道投放的手机号字段未确认。
  - 历史表里有 `emobile`。
  - 当前用户表中手机号字段可能是 `emobile`，但未确认。
  - 如果跑人群包 SQL 报手机号字段不存在，需要查真实字段。
3. 是否还需要额外排除“短信黑名单/退订/不可触达”未确认。
  - 当前只明确排除了：
    - 学生
    - `is_blocked = 0`
    - `is_puppet = 0` 建议用于人群包
  - 是否有短信退订表、营销黑名单表，当前会话未确认。
4. 当前人群包是否要排除本月已发送达到2次的用户，需要按投放当天确认。
  - 建议排除：

```sql
ifNull(sent_cnt_this_month, 0) < 2
```

1. 是否要排除当天已活跃用户。
  - 理论上 `today() - last_active_date >= 60` 已经排除。
  - 如果当天实时活跃数据滞后，可能需要额外确认。
2. 是否需要按平台、会员、历史付费等特征继续细分，未完成。
  - MT 提过“召回回来用户的特征”，本轮主要完成了沉默区间和频次维度。

## 6. 下一步建议

1. 先确认人群包输出字段，尤其是短信触达字段：
  - `uid`
  - 手机号/加密手机号字段，字段名未确认
  - `silent_days`
  - `five_class`
  - `seven_class`
  - `sent_cnt_this_month`
2. 写并跑当前人群包 SQL：
  - 主表用 `dim.dim_user`
  - `today() - last_active_date >= 60`
  - `five_class != '学生'`
  - `is_blocked = 0`
  - `is_puppet = 0`
  - 本月短信召回发送成功次数 `< 2`
  - 手机号字段非空
3. 用当前人群包人数做本次投放测算：
  - 目标用户数 `N`
  - 预计月发送条数 `N * 2`
  - 预计成本 `N * 2 * 单条/计费短信成本`
  - 预计召回人数可参考历史 `05_60天+ + 02_实际月发1-2次` 的当日召回率
  - 预计 CAC = 预计成本 / 预计召回人数
4. 如果 MT 需要“最大召回量级”的正式结论，输出一张结果表：
  - 方案
  - 发送成功用户数
  - 当日召回用户数
  - 短信成本
  - CAC
  - 是否满足 CAC<=5
  - 推荐/不推荐
5. 如果 MT 继续追问“为什么不放开频次”，用 `180天+` 高频 CAC 超 5 的结果说明风险。
6. 如果 MT 要“召回用户特征”，继续补充维度：
  - 是否会员
  - 是否历史付费
  - 平台
  - `seven_class`
  - 沉默区间
  - 历史月发送频次

## 7. 给下一个窗口的启动提示词

请复制以下内容到下一个新窗口：

```text
我在做“非学生沉默60+用户短信召回 CAC 测算和人群包提取”。请先读取并理解这个交接文档：

/Users/matchalee/Desktop/sql/沉默60非学生短信召回CAC测算_memory.md

当前已经完成两份 SQL：

1. /Users/matchalee/Desktop/sql/沉默60非学生短信召回CAC测算.sql
   - 明细测算：按月份、沉默区间、实际月发送频次看当日召回、成本、CAC。

2. /Users/matchalee/Desktop/sql/沉默60非学生短信召回CAC方案汇总.sql
   - 方案汇总：在 CAC <= 5 元约束下，比较不同人群方案和频次方案的召回量级。

已确认口径：
- 学生排除：dim.dim_user.five_class = '学生'。
- 历史沉默60+：dws.dw_sms_di.d - dws.dw_sms_di.last_active_date >= 60。
- 当前人群包沉默60+建议：today() - dim.dim_user.last_active_date >= 60。
- 召回口径：当日召回，即发送当天 d 在 dws.dw_dau 出现且 is_puppet = 0。
- 历史测算主表：dws.dw_sms_di，筛 is_send_success = 1。
- 排除 tag：recall_phone%、%wechat%、recall_push%、%fumeiti%、recall_today_1_send_msg%、recall_after_3_send_msg_with_equity%。
- 排除学生和黑名单：five_class != '学生'，is_blocked = 0。

关键结论：
- 如果按“每月最多2次、召回后停发”，重点看方案：
  人群方案 = 05_60天+
  频次方案 = 02_实际月发1-2次
- 该方案 2026年1-5月历史 CAC 都低于5元，且在最多2次频次约束下召回量最大。
- 如果不限制频次，05_60天+ + 01_实际全频次通常召回量更大，但不符合原始“一个月发2次”的限制；且180天+高频存在 CAC 超5风险。

当前还没有正式拉当前可投放人群包。下一步请帮我写/修一个人群包 SQL：
- 主表用 dim.dim_user。
- 条件：today() - last_active_date >= 60。
- 排除：five_class = '学生'、is_blocked = 1、is_puppet = 1。
- 排除本月已短信召回发送成功次数 >= 2 的用户。
- 需要输出 uid、手机号/加密手机号字段（字段名未确认，请先基于本地 SQL 查找或让我确认）、沉默天数、five_class、seven_class、本月已发送次数。

注意：这个项目中 ClickHouse 是 21.3，之前踩过坑：
- 多层 CTE 和子查询别名容易解析失败。
- WITH 日期别名在 WHERE 下推时可能报错。
- 避免用 dwm.dw_growth_user_active_di 筛历史沉默用户，它会导致召回率异常接近100%；历史测算要用 dws.dw_sms_di.d - last_active_date。
```

