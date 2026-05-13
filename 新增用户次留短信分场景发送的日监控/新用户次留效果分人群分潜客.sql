SELECT
    sms.d,
    sms.seven_class                                                   AS class,
    sms.tag,
    sms.is_mem,                                                       -- ✅ 新增：输出 is_mem 列
    content_join.content,
    sms.provider_channel                                              AS `通道`,
    sms.`发送量`,
    sms.`发送成功`,
    sms.`活跃`,
    round(`活跃` / nullIf(`发送成功`, 0), 4)                         AS `活跃率`,
    sms.`返回成功*文案长度` * CASE
        WHEN sms.provider_channel = '泰迪熊TDX'              THEN 0.022
        WHEN sms.provider_channel = '秒信HDHC'               THEN 0.027
        WHEN sms.provider_channel = '创蓝hdhc1'              THEN 0.03
        WHEN sms.provider_channel = '中网讯通'               THEN 0.03
        WHEN sms.provider_channel = '聚梦'                   THEN 0.027
        WHEN sms.provider_channel = '腾域HDHC'               THEN 0.029
        WHEN sms.provider_channel = '助通HDHC1'              THEN 0.0278
        WHEN sms.provider_channel = '阿里云HDLC'             THEN 0.027
        WHEN sms.provider_channel = '阿里云1'                THEN 0.027
        WHEN sms.provider_channel = '湖南云客'               THEN 0.027
        WHEN sms.provider_channel = '一知' AND sms.d < '2025-07-16'  THEN 0.13
        WHEN sms.provider_channel = '一知' AND sms.d >= '2025-07-16' THEN 0.16
        WHEN sms.provider_channel = 'aliyun_ai'              THEN 0.14
        WHEN sms.provider_channel = '文本短信-3日前'          THEN 0.03
        WHEN sms.provider_channel = '百应' AND sms.d < '2025-07-17'                              THEN 0.16
        WHEN sms.provider_channel = '百应' AND sms.d >= '2025-07-17' AND sms.d <= '2025-08-31'   THEN 0.17
        WHEN sms.provider_channel = '百应' AND sms.d >= '2025-09-01'                             THEN 0.15
        WHEN sms.provider_channel = '智齿'                   THEN 0.12
        WHEN sms.provider_channel = '挂机短信-聚梦'           THEN 0.027
        WHEN sms.provider_channel = '挂机短信-秒信HDHC'       THEN 0.03
        WHEN sms.provider_channel = '挂机短信-中网讯通'       THEN 0.03
        WHEN sms.provider_channel = '挂机短信-阿里云1'        THEN 0.027
        WHEN sms.provider_channel = '泰迪'                   THEN 0.12
        WHEN sms.provider_channel = '展奎'                   THEN 0.12
        WHEN sms.provider_channel = '视频短信'               THEN 0.076
        WHEN sms.provider_channel = '微信/特殊push'          THEN 0
        WHEN sms.provider_channel = '华为营销'               THEN 0.032
        WHEN sms.provider_channel = 'BFSHHDHC'               THEN 0.022
        ELSE 0
    END AS fee

FROM (
    SELECT
        d, seven_class, tag,
        is_mem,                                                       -- ✅ 新增：聚合层透传 is_mem
        provider_channel,
        uniqExact(uid)                                                AS `发送量`,
        uniqExactIf(uid, is_send_success = 1)                         AS `发送成功`,
        uniqExactIf(uid, is_send_success = 1 AND active = 1)          AS `活跃`,
        uniqExactIf(uid, cnt_len < 71 AND is_send_success = 1)
            + uniqExactIf(uid, cnt_len >= 71  AND cnt_len <= 134 AND is_send_success = 1) * 2
            + uniqExactIf(uid, cnt_len >= 135 AND cnt_len <= 201 AND is_send_success = 1) * 3
            + uniqExactIf(uid, cnt_len >= 202 AND is_send_success = 1) * 4  AS `返回成功*文案长度`
    FROM (
        SELECT
            s.uid, s.d, s.tag, s.is_send_success, s.provider_channel,
            substringUTF8(s.content, 1, 5)                            AS con,
            lengthUTF8(s.content)                                     AS cnt,
            if(con LIKE '【脉脉】%', cnt,
               if(s.provider_channel LIKE '%阿里云%', cnt + 2, cnt + 4)) AS cnt_len,
            ext.seven_class                                            AS seven_class,
            ext.active                                                 AS active,
            -- ✅ 新增：用维表子查询判断会员潜客，与周报SQL保持一致
            if(s.uid IN (
                SELECT uid
                FROM dim.dim_user
                WHERE lv3_major IN (
                    SELECT lv3_major_map AS lv3_major
                    FROM dim.dim_lv3_major_da
                    WHERE is_potential_customers = 1
                )
            ), '会员潜客', '非会员潜客')                               AS is_mem
        FROM dws.dw_sms_di s
        ANY LEFT JOIN (
            SELECT
                u.uid,
                u.d,
                u.seven_class,
                if(dau.uid > 0, 1, 0) AS active
            FROM (
                SELECT s2.uid, s2.d, u2.seven_class
                FROM (
                    SELECT uid, d
                    FROM dws.dw_sms_di
                    WHERE d BETWEEN '{{start}}' AND '{{end}}'
                      AND tag LIKE 'recall_1day%'
                    GROUP BY uid, d
                ) s2
                ANY LEFT JOIN (
                    SELECT uid, seven_class
                    FROM dim.dim_user
                ) u2 USING (uid)
            ) u
            ANY LEFT JOIN (
                SELECT uid, d
                FROM dws.dw_dau
                WHERE d BETWEEN '{{start}}' AND '{{end}}'
            ) dau USING (uid, d)
        ) ext USING (uid, d)
        WHERE s.d BETWEEN '{{start}}' AND '{{end}}'
          AND s.tag LIKE 'recall_1day%'
          AND s.d - s.last_active_date BETWEEN 0 AND 29
    )
    GROUP BY d, seven_class, tag,
             is_mem,                                                   -- ✅ 修改：GROUP BY 加入 is_mem
             provider_channel
) AS sms

ANY LEFT JOIN (
    SELECT tag, any(content) AS content
    FROM dws.dw_sms_di
    WHERE d BETWEEN '{{start}}' AND '{{end}}'
      AND tag LIKE 'recall_1day%'
    GROUP BY tag
) AS content_join USING (tag)

ORDER BY d DESC, seven_class, is_mem, `发送成功` DESC  -- ✅ 修改：ORDER BY 加入 is_mem