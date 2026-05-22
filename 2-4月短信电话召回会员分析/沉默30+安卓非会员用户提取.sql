/*
取数目标：
- 沉默 30+ 的全部 Android 用户。
- 排除小号：dim.dim_user.is_puppet = 0。
- 排除黑名单/黑产：dim.dim_user.is_blocked = 0。
- 排除当前仍是会员用户。

当前已确认：
- 全量沉默用户应以 dim.dim_user 为主表，用 today() - last_active_date >= 30。
- dim.dim_user 可直接排小号和黑名单。
- 不能用 yesterday() 的 dwm.dw_growth_user_active_di.is_member 排当前会员，
  因为 dim_user 沉默 30+ 用户与 yesterday() 的 active_di 快照关联结果为 0。
- 当前会员状态可改用 dim.dim_user_tag.is_current_member。
- Android 平台可使用 dim.dim_user.platform。

默认使用最近完整日 yesterday()。如需指定日期，修改 target_date。
*/

/*
全量用户口径：用 dim.dim_user.last_active_date 判断沉默 30+。
当前这版不再关联 dwm.dw_growth_user_active_di，因为排查结果显示沉默 30+ 用户关联不到昨日 active 快照。

当前可稳定限制：
- 沉默 30+：today() - last_active_date >= 30。
- Android：dim.dim_user.platform 归一后为 android。
- 排除黑名单/黑产：is_blocked = 0。
- 排除小号：is_puppet = 0。
- 排除当前会员：dim.dim_user_tag.is_current_member = 0。
*/

SELECT
    count() AS `全量用户口径_沉默30+安卓非会员排黑排小号用户数`
FROM
(
    SELECT
        toUInt64(u.uid) AS uid,
        multiIf(
            lowerUTF8(toString(u.platform)) IN ('android', '安卓'), 'android',
            lowerUTF8(toString(u.platform)) IN ('ios', 'iphone'), 'ios',
            'other'
        ) AS platform_type,
        ifNull(u.is_blocked, 0) AS is_blocked,
        ifNull(u.is_puppet, 0) AS is_puppet,
        ifNull(t.is_current_member, 0) AS is_current_member
    FROM dim.dim_user AS u
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            any(ifNull(is_current_member, 0)) AS is_current_member
        FROM dim.dim_user_tag
        GROUP BY uid
    ) AS t
        ON toUInt64(u.uid) = t.uid
    WHERE today() - u.last_active_date >= 30
) AS b
WHERE b.platform_type = 'android'
  AND b.is_blocked = 0
  AND b.is_puppet = 0
  AND b.is_current_member = 0;

/*
全量用户口径明细版：

SELECT
    toUInt64(u.uid) AS `用户ID`,
    u.last_active_date AS `最近活跃日期`,
    today() - u.last_active_date AS `沉默天数`,
    multiIf(
        lowerUTF8(toString(u.platform)) IN ('android', '安卓'), 'android',
        lowerUTF8(toString(u.platform)) IN ('ios', 'iphone'), 'ios',
        'other'
    ) AS `平台`,
    ifNull(nullIf(trimBoth(toString(u.seven_class)), ''), '未知') AS `七类人群`,
    ifNull(u.is_blocked, 0) AS `是否黑名单`,
    ifNull(u.is_puppet, 0) AS `是否小号`,
    ifNull(t.is_current_member, 0) AS `是否当前会员`
FROM dim.dim_user AS u
ANY LEFT JOIN
(
    SELECT
        toUInt64(uid) AS uid,
        any(ifNull(is_current_member, 0)) AS is_current_member
    FROM dim.dim_user_tag
    GROUP BY uid
) AS t
    ON toUInt64(u.uid) = t.uid
WHERE today() - u.last_active_date >= 30
  AND multiIf(
        lowerUTF8(toString(u.platform)) IN ('android', '安卓'), 'android',
        lowerUTF8(toString(u.platform)) IN ('ios', 'iphone'), 'ios',
        'other'
      ) = 'android'
  AND ifNull(u.is_blocked, 0) = 0
  AND ifNull(u.is_puppet, 0) = 0
  AND ifNull(t.is_current_member, 0) = 0
ORDER BY
    `沉默天数` DESC,
    `用户ID`;
*/

/*
下面开始是旧版：基于 dwm.dw_growth_user_active_di 的日快照口径。
如果要和前面短信电话召回分析保持一致，可以继续使用；如果要全量用户口径，优先用上面的 dim.dim_user 版本。
*/

WITH
    yesterday() AS target_date

SELECT
    b.uid AS `用户ID`,
    b.d AS `快照日期`,
    b.platform_type AS `平台`,
    b.silent_days AS `沉默天数`,
    b.seven_class AS `七类人群`
FROM
(
    SELECT
        a.d AS d,
        toUInt64(a.uid) AS uid,
        multiIf(
            lowerUTF8(toString(a.platform)) IN ('android', '安卓'), 'android',
            lowerUTF8(toString(a.platform)) IN ('ios', 'iphone'), 'ios',
            'other'
        ) AS platform_type,
        a.silent_days AS silent_days,
        a.is_member AS is_member,
        ifNull(u.is_blocked, 0) AS is_blocked,
        ifNull(u.is_puppet, 0) AS is_puppet,
        ifNull(nullIf(trimBoth(toString(u.seven_class)), ''), '未知') AS seven_class
    FROM dwm.dw_growth_user_active_di AS a
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            any(ifNull(is_blocked, 0)) AS is_blocked,
            any(ifNull(is_puppet, 0)) AS is_puppet,
            any(ifNull(nullIf(trimBoth(toString(seven_class)), ''), '未知')) AS seven_class
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON toUInt64(a.uid) = u.uid
    WHERE a.d = target_date
      AND a.silent_days >= 30
      AND a.is_member = 0
) AS b
WHERE b.platform_type = 'android'
  AND b.is_blocked = 0
  AND b.is_puppet = 0
ORDER BY
    b.silent_days DESC,
    b.uid;

/*
如果只需要量级，可以跑下面这段：

WITH
    yesterday() AS target_date

SELECT
    count() AS `沉默30+安卓非会员用户数`
FROM
(
    SELECT
        toUInt64(a.uid) AS uid,
        multiIf(
            lowerUTF8(toString(a.platform)) IN ('android', '安卓'), 'android',
            lowerUTF8(toString(a.platform)) IN ('ios', 'iphone'), 'ios',
            'other'
        ) AS platform_type,
        a.silent_days AS silent_days,
        a.is_member AS is_member,
        ifNull(u.is_blocked, 0) AS is_blocked,
        ifNull(u.is_puppet, 0) AS is_puppet
    FROM dwm.dw_growth_user_active_di AS a
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            any(ifNull(is_blocked, 0)) AS is_blocked,
            any(ifNull(is_puppet, 0)) AS is_puppet
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON toUInt64(a.uid) = u.uid
    WHERE a.d = target_date
      AND a.silent_days >= 30
      AND a.is_member = 0
) AS b
WHERE b.platform_type = 'android'
  AND b.is_blocked = 0
  AND b.is_puppet = 0;
*/

/*
如果沉默 30+ 想改用 dim.dim_user.last_active_date 口径，下面这段只用于验证：
- 沉默判断：today() - last_active_date >= 30。
- 安卓平台、当前会员状态仍取最近完整日 active 快照。
- 小号、黑名单取 dim.dim_user。
- 注意：如果这些沉默用户关联不到 yesterday() 的 dwm.dw_growth_user_active_di，
  说明这张表不是当前场景可用的全量用户状态表，不能用它补安卓/会员状态。

WITH
    yesterday() AS target_date

SELECT
    count() AS `last_active_date口径_沉默30+安卓非会员用户数`
FROM dim.dim_user AS u
ANY INNER JOIN
(
    SELECT
        toUInt64(uid) AS uid,
        multiIf(
            lowerUTF8(toString(platform)) IN ('android', '安卓'), 'android',
            lowerUTF8(toString(platform)) IN ('ios', 'iphone'), 'ios',
            'other'
        ) AS platform_type,
        is_member
    FROM dwm.dw_growth_user_active_di
    WHERE d = target_date
) AS a
    ON toUInt64(u.uid) = a.uid
WHERE today() - u.last_active_date >= 30
  AND a.platform_type = 'android'
  AND a.is_member = 0
  AND ifNull(u.is_blocked, 0) = 0
  AND ifNull(u.is_puppet, 0) = 0;
*/

/*
last_active_date 口径跑出 0 时，用下面这段分步排查是哪一步过滤没了：

WITH
    yesterday() AS target_date,

user_base AS
(
    SELECT
        toUInt64(uid) AS uid,
        last_active_date,
        ifNull(is_blocked, 0) AS is_blocked,
        ifNull(is_puppet, 0) AS is_puppet
    FROM dim.dim_user
    WHERE today() - last_active_date >= 30
),

active_base AS
(
    SELECT
        toUInt64(uid) AS uid,
        multiIf(
            lowerUTF8(toString(platform)) IN ('android', '安卓'), 'android',
            lowerUTF8(toString(platform)) IN ('ios', 'iphone'), 'ios',
            'other'
        ) AS platform_type,
        is_member
    FROM dwm.dw_growth_user_active_di
    WHERE d = target_date
),

joined AS
(
    SELECT
        u.uid,
        u.is_blocked,
        u.is_puppet,
        a.platform_type,
        a.is_member
    FROM user_base AS u
    LEFT JOIN active_base AS a
        ON u.uid = a.uid
)

SELECT '01_dim_user_last_active_date沉默30+' AS `步骤`, count() AS `用户数` FROM user_base
UNION ALL
SELECT '01_1_昨日active快照总量', count() FROM active_base
UNION ALL
SELECT '02_能关联到昨日active快照', countIf(platform_type != '') FROM joined
UNION ALL
SELECT '03_关联后安卓', countIf(platform_type = 'android') FROM joined
UNION ALL
SELECT '04_关联后安卓且非会员', countIf(platform_type = 'android' AND is_member = 0) FROM joined
UNION ALL
SELECT '05_再排黑名单', countIf(platform_type = 'android' AND is_member = 0 AND is_blocked = 0) FROM joined
UNION ALL
SELECT '06_再排小号', countIf(platform_type = 'android' AND is_member = 0 AND is_blocked = 0 AND is_puppet = 0) FROM joined;
*/

/*
如果坚持以 dim.dim_user.last_active_date 为沉默口径，且只先排除黑名单/小号，
可以先跑这个，确认排黑和排小号后的基础量级：

SELECT
    count() AS `last_active_date口径_沉默30+排黑排小号用户数`
FROM dim.dim_user
WHERE today() - last_active_date >= 30
  AND ifNull(is_blocked, 0) = 0
  AND ifNull(is_puppet, 0) = 0;

注意：
- 这个版本不含安卓和当前非会员限制。
- 你的排查结果显示这批用户关联不到 yesterday() 的 dwm.dw_growth_user_active_di，
  所以不能继续用这张昨天快照表补 platform / is_member。
- 需要先确认 dim.dim_user 里是否有可用的平台字段和当前会员字段，或换一张全量用户状态表。
*/

/*
查 dim.dim_user 是否有可直接用于“安卓”和“当前会员”的字段：

SELECT
    name,
    type
FROM system.columns
WHERE database = 'dim'
  AND table = 'dim_user'
  AND (
       lowerUTF8(name) LIKE '%platform%'
    OR lowerUTF8(name) LIKE '%os%'
    OR lowerUTF8(name) LIKE '%android%'
    OR lowerUTF8(name) LIKE '%ios%'
    OR lowerUTF8(name) LIKE '%member%'
    OR lowerUTF8(name) LIKE '%vip%'
    OR lowerUTF8(name) LIKE '%mem%'
  )
ORDER BY name;
*/
