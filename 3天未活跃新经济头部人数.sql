/*
口径：
- 近 30 天，每天取当天 silent_days = 3 的用户。
- 七类人群 = 新经济头部。
- 限制当天在内容场：广场或同事圈。
  - 广场：dws.dw_content_core_dau.new_max_pos >= 4 且 is_puppet = 0。
  - 同事圈：dws.dw_content_core_dau.is_company_circle_dau = 1 且 is_puppet = 0。
- 排除机型/品牌：小米、华为、OPPO、vivo、荣耀。
- 排除短信黑名单：dim.dim_user.is_blocked = 0。
- 排除小号：dim.dim_user.is_puppet = 0。

默认取最近完整 30 天，即 yesterday() 往前 29 天。
如果要包含今天，把 end_date 改成 today()。
*/

WITH
    yesterday() AS end_date,
    end_date - 29 AS start_date

SELECT
    b.d,
    uniqExact(b.uid) AS `3天未活跃人数`
FROM
(
    SELECT
        a.d AS d,
        toUInt64(a.uid) AS uid,
        a.silent_days AS silent_days,
        u.brand_norm AS brand_norm,
        u.seven_class AS seven_class,
        u.is_blocked AS is_blocked,
        u.is_puppet AS is_puppet
    FROM dwm.dw_growth_user_active_di AS a
    ANY INNER JOIN
    (
        SELECT DISTINCT
            d,
            toUInt64(uid) AS content_uid
        FROM dws.dw_content_core_dau
        WHERE d BETWEEN start_date AND end_date
          AND is_puppet = 0
          AND (
                 new_max_pos >= 4
              OR is_company_circle_dau = 1
          )
    ) AS c
        ON a.d = c.d
       AND toUInt64(a.uid) = c.content_uid
    ANY LEFT JOIN
    (
        SELECT
            uid AS dim_uid,
            any(lowerUTF8(toString(brand))) AS brand_norm,
            any(ifNull(nullIf(trimBoth(toString(seven_class)), ''), '未知')) AS seven_class,
            any(ifNull(is_blocked, 0)) AS is_blocked,
            any(ifNull(is_puppet, 0)) AS is_puppet
        FROM dim.dim_user
        GROUP BY uid
    ) AS u
        ON toUInt64(a.uid) = toUInt64(u.dim_uid)
    WHERE a.d BETWEEN start_date AND end_date
      AND a.silent_days = 3
      AND u.seven_class = '新经济头部'
) AS b
WHERE b.is_blocked = 0
  AND b.is_puppet = 0
  AND NOT (
         b.brand_norm LIKE 'xiaomi'
      OR b.brand_norm LIKE 'redmi'
      OR b.brand_norm LIKE 'huawei'
      OR b.brand_norm LIKE 'honor'
      OR b.brand_norm LIKE 'oppo'
      OR b.brand_norm LIKE 'vivo'
  )
GROUP BY b.d
ORDER BY b.d;
