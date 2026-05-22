/*
在用户表里筛出“注册完成后第 1 天”的用户，并排除一批疑似管理层、HR、猎头等人群
从 dim.dim_user 里筛选注册完成用户，给用户打上注册后第几天的“延迟”标签，然后排除一批管理层、HR、猎头等用户，最后只保留 +1 用户。
*/

SELECT
    uid,
    `延迟`
FROM
(
    SELECT
        uid,
        register_complete_date,

        CASE
            WHEN today() - register_complete_date = 1 THEN '+1'
            WHEN today() - register_complete_date = 7 THEN '+7'
            WHEN today() - register_complete_date = 14 THEN '+14'
            ELSE '排除'
        END AS `延迟`

    FROM dim.dim_user

    WHERE register_complete_date >= '2025-07-10'

      AND uid NOT IN
      (
          SELECT
              toUInt32(uid)
          FROM dim.dim_user
          WHERE company_id <> 1
            AND
            (
                current_position LIKE '%行长%'
                OR current_position LIKE '%院长%'
                OR current_position LIKE '%部长%'
                OR current_position LIKE '%科长%'
                OR current_position LIKE '%处长%'
                OR current_position LIKE '%局长%'
                OR current_position LIKE '%厅长%'
                OR current_position LIKE '%市长%'
                OR current_position LIKE '%省长%'
                OR current_position LIKE '%系长%'
                OR current_position LIKE '%校长%'
                OR current_position LIKE '%厂长%'
                OR current_position LIKE '%会长%'
                OR current_position LIKE '%所长%'
                OR current_position LIKE '%理事长%'
                OR current_position LIKE '%秘书长%'
                OR current_position LIKE '%园长%'
                OR current_position LIKE '%总经办%'
                OR current_position LIKE '%主编%'
                OR current_position LIKE '%主任%'
                OR current_position LIKE '%总编%'
                OR current_position LIKE '%制片人%'
                OR current_position LIKE '%导演%'
                OR current_position LIKE '%店长%'
                OR current_position LIKE '%总裁%'
                OR current_position LIKE '%总经理%'
                OR current_position LIKE '%创始人%'
                OR current_position LIKE '%首席%'
                OR current_position LIKE '%Director%'
                OR current_position LIKE '%director%'
                OR current_position LIKE '%GM%'
                OR current_position LIKE '%head%'
                OR current_position LIKE '%Head%'
                OR current_position LIKE '%VP%'
                OR current_position LIKE '%董事%'
                OR current_position LIKE '%董事长%'
                OR current_position LIKE '%执行董事%'
                OR current_position LIKE '%法人%'
                OR current_position LIKE '%书记%'
                OR current_position LIKE '%分总%'
                OR current_position LIKE '%hr%'
                OR current_position LIKE '%人力资源%'
                OR current_position LIKE '%招聘%'
                OR current_position LIKE '%合伙人%'
                OR current_position LIKE '%负责人%'

                OR is_hr = 1
                OR is_headhunting = 1

                OR lv3_major LIKE '%院长%'
                OR lv3_major LIKE '%部长%'
                OR lv3_major LIKE '%科长%'
                OR lv3_major LIKE '%处长%'
                OR lv3_major LIKE '%局长%'
                OR lv3_major LIKE '%厅长%'
                OR lv3_major LIKE '%市长%'
                OR lv3_major LIKE '%省长%'
                OR lv3_major LIKE '%系长%'
                OR lv3_major LIKE '%校长%'
                OR lv3_major LIKE '%厂长%'
                OR lv3_major LIKE '%会长%'
                OR lv3_major LIKE '%所长%'
                OR lv3_major LIKE '%理事长%'
                OR lv3_major LIKE '%秘书长%'
                OR lv3_major LIKE '%园长%'
                OR lv3_major LIKE '%总经办%'
                OR lv3_major LIKE '%主编%'
                OR lv3_major LIKE '%主任%'
                OR lv3_major LIKE '%总编%'
                OR lv3_major LIKE '%制片人%'
                OR lv3_major LIKE '%导演%'
                OR lv3_major LIKE '%店长%'
                OR lv3_major LIKE '%总裁%'
                OR lv3_major LIKE '%总经理%'
                OR lv3_major LIKE '%创始人%'
                OR lv3_major LIKE '%首席%'
                OR lv3_major LIKE '%Director%'
                OR lv3_major LIKE '%director%'
                OR lv3_major LIKE '%GM%'
                OR lv3_major LIKE '%head%'
                OR lv3_major LIKE '%Head%'
                OR lv3_major LIKE '%VP%'
                OR lv3_major LIKE '%董事%'
                OR lv3_major LIKE '%董事长%'
                OR lv3_major LIKE '%执行董事%'
                OR lv3_major LIKE '%法人%'
                OR lv3_major LIKE '%书记%'
                OR lv3_major LIKE '%分总%'
                OR lv3_major LIKE '%hr%'
                OR lv3_major LIKE '%人力资源%'
                OR lv3_major LIKE '%招聘%'
                OR lv3_major LIKE '%合伙人%'
            ) = 1
      )
)
WHERE `延迟` = '+1';