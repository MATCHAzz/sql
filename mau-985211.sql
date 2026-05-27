SELECT toStartOfDay(toDateTime(`month_d`)) AS `__timestamp_ae6234`,
       sum(`mau`) AS `mau_e3d0cd`,
       sum(`新增`) AS `新增_66ab5e`,
       sum(`付费召回`) AS `付费召回_b1ff31`,
       sum(`回流`) AS `回流_6a1372`,
       sum(`召回+回流`) AS `召回+回流_d6706a`
FROM
  (select d as month_d,
          uniqExact(uid) as mau,
          uniqExactIf(uid, mau_type='新用户') as `新增`,
          uniqExactIf(uid, mau_type='付费召回') as `付费召回`,
          uniqExactIf(uid, mau_type='留存-回流mau') as `回流`,
          `付费召回` + `回流` as `召回+回流`
   from
     (select m.d as d,
             m.uid as uid,
             case
                 when m.is_new=1 then '新用户'
                 when if(m.is_silent_30d=1
                         and (m.is_no_recall_phone_sms_touch + m.sms_click_tag + m.info_stream_priority + m.is_outapp_wechat_priority + m.is_outapp_touch + m.push_click_priority + m.is_outapp_wechat_priority)>0, 1, 0)=1 then '付费召回'
                 when flag=1 then '留存mau'
                 else '留存-回流mau'
             end as mau_type
      from
        (select d,
                uid,
                is_new,
                is_silent_30d,
                is_no_recall_phone_sms_touch,
                sms_click_tag,
                info_stream_priority,
                is_outapp_wechat_priority,
                is_outapp_touch,
                push_click_priority
         from dws.dw_office_user_tag_month prewhere d >= today() - 730
         and uid in
           (select distinct uid
            from dwm.dw_growth_user_active_di prewhere d >= today() - 770
            and d <= today()
            and five_class = '学生'
            and uid in
              (select uid
               from dim.dim_user prewhere is_last_school_211))) m
      inner join
        (select toDate(arrayJoin(range(toUInt32(d), toUInt32(d + 30)))) as target_d,
                uid as uid
         from
           (select distinct d as d,
                            uid as uid
            from dwm.dw_growth_user_active_di prewhere d >= today() - 770
            and d <= today()
            and five_class = '学生'
            and uid in
              (select uid
               from dim.dim_user prewhere is_last_school_211))
         group by target_d,
                  uid
         having target_d >= today() - 730
         and target_d <= today()) dr on m.d = dr.target_d
      and m.uid = dr.uid
      left join
        (select d + 30 as target_d,
                uid as uid,
                       1 as flag
         from dws.dw_office_user_tag_month prewhere d >= today() - 770
         and uid in
           (select distinct uid
            from dwm.dw_growth_user_active_di prewhere d >= today() - 770
            and five_class = '学生'
            and uid in
              (select uid
               from dim.dim_user prewhere is_last_school_211))) m_last on m.d = m_last.target_d
      and m.uid = m_last.uid)
   group by d
   order by d) AS `virtual_table`
GROUP BY toStartOfDay(toDateTime(`month_d`))
ORDER BY `mau_e3d0cd` DESC
LIMIT 1000;