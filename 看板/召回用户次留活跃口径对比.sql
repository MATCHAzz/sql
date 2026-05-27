/*
召回用户次留活跃口径对比

目的：
用同一批 recall_remain% 短信发送成功用户，对比两种“活跃/召回”口径：
1. is_recall 口径：dws.dw_sms_di.is_recall = 1。
2. join dau 口径：dws.dw_sms_di 按 uid + d 关联 dws.dw_dau。

说明：
1. 两个口径都只能说明“发送成功用户当天活跃/召回”，不能严格证明活跃由这条短信贡献。
2. 如果 is_recall 是按 uid + d 回填到短信明细，则它和 join dau 口径应该非常接近；
   如果差异较大，需要再确认 is_recall 的回填逻辑、dau 过滤条件、短信明细分区时间。
3. 看板权限解析会把命名 CTE 误判成真实表，所以这里不用命名 CTE。
*/

SELECT
    d,
    send_success_uv AS `发送成功uv`,

    is_recall_active_uv AS `is_recall活跃uv`,
    round(is_recall_active_uv / nullIf(send_success_uv, 0), 4) AS `is_recall活跃率`,

    dau_join_active_uv AS `join_dau活跃uv`,
    round(dau_join_active_uv / nullIf(send_success_uv, 0), 4) AS `join_dau活跃率`,

    both_active_uv AS `两口径都活跃uv`,
    only_is_recall_active_uv AS `仅is_recall活跃uv`,
    only_dau_join_active_uv AS `仅join_dau活跃uv`,
    neither_active_uv AS `两口径都不活跃uv`,

    is_recall_active_uv - dau_join_active_uv AS `is_recall比join_dau多uv`,
    round((is_recall_active_uv - dau_join_active_uv) / nullIf(send_success_uv, 0), 4) AS `is_recall比join_dau多占比`
FROM
(
    SELECT
        s.d AS d,
        uniqExactIf(s.uid, s.send_success_flag = 1) AS send_success_uv,

        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND s.is_recall_active = 1
        ) AS is_recall_active_uv,

        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND ifNull(dau.is_dau, 0) = 1
        ) AS dau_join_active_uv,

        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND s.is_recall_active = 1
            AND ifNull(dau.is_dau, 0) = 1
        ) AS both_active_uv,

        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND s.is_recall_active = 1
            AND ifNull(dau.is_dau, 0) = 0
        ) AS only_is_recall_active_uv,

        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND s.is_recall_active = 0
            AND ifNull(dau.is_dau, 0) = 1
        ) AS only_dau_join_active_uv,

        uniqExactIf(
            s.uid,
            s.send_success_flag = 1
            AND s.is_recall_active = 0
            AND ifNull(dau.is_dau, 0) = 0
        ) AS neither_active_uv
    FROM
    (
        SELECT
            toUInt64(uid) AS uid,
            d,
            max(if(is_send_success = 1, 1, 0)) AS send_success_flag,
            max(if(is_send_success = 1 AND ifNull(is_recall, 0) = 1, 1, 0)) AS is_recall_active
        FROM dws.dw_sms_di
        WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
          AND tag LIKE 'recall_remain%'
          AND toUInt64(uid) != 0
        GROUP BY
            d,
            uid
    ) AS s
    ANY LEFT JOIN
    (
        SELECT
            toUInt64(uid) AS uid,
            d,
            1 AS is_dau
        FROM dws.dw_dau
        WHERE d BETWEEN toDate('2026-01-01') AND yesterday()
          AND toUInt64(uid) != 0
        GROUP BY
            d,
            uid
    ) AS dau
        ON s.uid = dau.uid
       AND s.d = dau.d
    GROUP BY s.d
) AS compare_result
ORDER BY d DESC;
