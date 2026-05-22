select uid
from
(
    select toUInt64(uid) as uid,
      real_name,
      case
        when class in ('传统行业主流职业', '传统行业非主流职业一线新一线or高学历or中高端or苹果华为') then '传统主流一线'
        else class
      end as class,
      today() - last_active_date as lad,
      last_active_date,
      new_top_major,
      current_position,
      last_school_name,
      is_last_school_985,
      is_last_school_211
    from dim.dim_user
) a
left join
(
    select *
    from(
        SELECT sum(duration) as total_duration,
          toUInt64(uid) uid
        FROM dwd.dw_app_session
        where d between '2024-10-20' and today() -1
        group by uid
      )
) 
b on a.uid = b.uid
where last_active_date != toDate(0)
and uid  not in 
(

  select uid 
  from 
  (
    select
    d,
    uid,
    tag,
    case
        when silent_days  between 30 and 35 and (economy like '%新经济%'  or is_p=1 ) then 1
        else 0
    end as special
    from 
  (
      select
        toUInt64(uid) as uid ,
        d,
        tag
      FROM dws.dw_sms_di
      prewhere  d >= yesterday()-5
  )
  left join 
  (
    select
        d,
        toUInt64(uid) as uid  ,
        economy ,
        lv3_major in (select lv3_major_map from dim.dim_lv3_major_da where is_potential_customers =1) is_p,
        silent_days 
    from dwm.dw_growth_user_active_di
    prewhere d >= yesterday()-5
  
  )
  using d,uid 
  )
  where 
  (
    tag like 'recall_recent%' or tag like  'recall_temporary%'
  )
  and
  (
    special =0 and d =yesterday()
  )
  
  

)
  and uid not in (
    select toUInt64(uid)
    from algo.sms_no_send_daily
  )
  and uid not in (
    select toUInt64(uid)
    from dim.dim_user
    where is_blocked = 1
  )
  and uid not in (
    SELECT toUInt64(uid)
    FROM mysqldump.user_auth
    WHERE toDate(login_time) = today()
  )
  and (
    (
      new_top_major like '%技工%'
      or new_top_major like '%操作工%'
      or new_top_major like '%猎头%'
      or new_top_major like '%信贷业务%'
      or new_top_major like '%理财%'
      or new_top_major like '%司机%'
      or new_top_major like '%驾驶员%'
      or new_top_major like '%服务员%'
      or new_top_major like '%领班%'
      or new_top_major like '%快递员%'
      or new_top_major like '%配送员%'
      or new_top_major like '%跑腿%'
      or new_top_major like '%行政后勤%'
      or new_top_major like '%文员%'
      or new_top_major like '%汽车机修%'
      or new_top_major like '%钣金%'
      or new_top_major like '%喷漆%'
      or new_top_major like '%品牌营销推广%'
      or new_top_major like '%生产%'
      or new_top_major like '%保险代理%'
      or new_top_major like '%个体批发零售%'
      or new_top_major like '%仓管%'
      or new_top_major like '%堆垛%'
      or new_top_major like '%整理%'
      or new_top_major like '%房地产销售%'
      or new_top_major like '%装修%'
      or new_top_major like '%施工%'
      or new_top_major like '%厨师%'
      or new_top_major like '%外卖送餐%'
      or new_top_major like '%建筑现场施工%'
      or new_top_major like '%个体批发零售%'
      or new_top_major like '%厨工%'
      or new_top_major like '%帮厨%'
      or new_top_major like '%打荷切配%'
      or new_top_major like '%装卸%'
      or new_top_major like '%搬运%'
      or new_top_major like '%美容师%'
      or new_top_major like '%美容顾问'
      or new_top_major like '%分拣%'
      or new_top_major like '%畜牧饲养%'
      or new_top_major like '%养殖%'
      or new_top_major like '%农民工%'
    )
  ) = 0
  and new_top_major not in (
    '理疗师/按摩师',
    '消防员',
    '拍卖师',
    '摄影师',
    '化妆师/造型师/服装道具师',
    '工程测绘',
    '餐饮门店管理/运营',
    '健身教练/私人教练',
    '典当业务',
    '体育/健身教练',
    '猎头',
    '搬家服务',
    '发型师',
    '美容师/美容顾问',
    '分拣',
    '保险经纪人',
    '农业种植/果树栽培',
    '设备管理/维修',
    '宠物服务',
    '保险精算师',
    '店员/收银员/营业员',
    '导游/领队'
  )
  AND((
      today() - last_active_date between 30 and 35
      and total_duration not between 0 and 70
      and class in ('传统主流一线','新经济头部','新经济腰尾','传统行业其他','其他华为苹果中高端新一线','其他主流行业','其他其他')
    )
    or(
      today() - last_active_date between 36 and 59
      and total_duration not between 0 and 70
      and (class in ('传统主流一线','新经济头部','新经济腰尾','传统行业其他','其他华为苹果中高端新一线','其他主流行业','其他其他') 
      and toDayOfWeek(today()) in (2,4,7))
    )
    )
  and class in ('新经济头部', '新经济腰尾', '传统主流一线','学生','传统行业其他','其他华为苹果中高端新一线','其他主流行业','其他其他')
  and (
    current_position like '%行长%'
    or current_position like '%院长%'
    or current_position like '%部长%'
    or current_position like '%科长%'
    or current_position like '%处长%'
    or current_position like '%局长%'
    or current_position like '%厅长%'
    or current_position like '%市长%'
    or current_position like '%省长%'
    or current_position like '%系长%'
    or current_position like '%校长%'
    or current_position like '%厂长%'
    or current_position like '%会长%'
    or current_position like '%所长%'
    or current_position like '%理事长%'
    or current_position like '%秘书长%'
    or current_position like '%园长%'
    or current_position like '%总经办%'
    or current_position like '%主编%'
    or current_position like '%主任%'
    or current_position like '%总编%'
    or current_position like '%制片人%'
    or current_position like '%导演%'
    or current_position like '%店长%'
    or current_position like '%总裁%'
    or current_position like '%总经理%'
    or current_position like '%创始人%'
    or current_position like '%首席%'
    or current_position like '%Cbo%'
    or current_position like '%CBo%'
    or current_position like '%CBO%'
    or current_position like '%cbo%'
    or current_position like '%cBo%'
    or current_position like '%cBO%'
    or current_position like '%cDo%'
    or current_position like '%CDo%'
    or current_position like '%CDO%'
    or current_position like '%cdo%'
    or current_position like '%cDo%'
    or current_position like '%cDO%'
    or current_position like '%Ceo%'
    or current_position like '%CEo%'
    or current_position like '%CEO%'
    or current_position like '%ceo%'
    or current_position like '%cEo%'
    or current_position like '%cEO%'
    or current_position like '%Cfo%'
    or current_position like '%CFo%'
    or current_position like '%CFO%'
    or current_position like '%cFo%'
    or current_position like '%cFO%'
    or current_position like '%cfo%'
    or current_position like '%Cho%'
    or current_position like '%CHo%'
    or current_position like '%CHO%'
    or current_position like '%cHO%'
    or current_position like '%cHo%'
    or current_position like '%cho%'
    or current_position like '%CIO%'
    or current_position like '%CIo%'
    or current_position like '%Cio%'
    or current_position like '%cio%'
    or current_position like '%cIo%'
    or current_position like '%cIO%'
    or current_position like '%Cso%'
    or current_position like '%CSo%'
    or current_position like '%CSO%'
    or current_position like '%cso%'
    or current_position like '%cSo%'
    or current_position like '%cSO%'
    or current_position like '%Cto%'
    or current_position like '%CTo%'
    or current_position like '%CTO%'
    or current_position like '%cto%'
    or current_position like '%cTo%'
    or current_position like '%cTO%'
    or current_position like '%Cxo%'
    or current_position like '%CXo%'
    or current_position like '%CXO%'
    or current_position like '%cxo%'
    or current_position like '%cXo%'
    or current_position like '%cXO%'
    or current_position like '%Cmo%'
    or current_position like '%CMo%'
    or current_position like '%CMO%'
    or current_position like '%cMo%'
    or current_position like '%cMO%'
    or current_position like '%cmo%'
    or current_position like '%Coo%'
    or current_position like '%COo%'
    or current_position like '%COO%'
    or current_position like '%coo%'
    or current_position like '%cOo%'
    or current_position like '%cOO%'
    or current_position like '%Director%'
    or current_position like '%director%'
    or current_position like '%GM%'
    or current_position like '%Gm%'
    or current_position like '%gm%'
    or current_position like '%gM%'
    or current_position like '%head%'
    or current_position like '%Head%'
    or current_position like '%HEAD%'
    or current_position like '%VP%'
    or current_position like '%vp%'
    or current_position like '%Vp%'
    or current_position like '%vP%'
    or current_position like '%Svp%'
    or current_position like '%SVp%'
    or current_position like '%SVP%'
    or current_position like '%svp%'
    or current_position like '%sVP%'
    or current_position like '%sVp%'
    or current_position like '%Evp%'
    or current_position like '%EVp%'
    or current_position like '%EVP%'
    or current_position like '%evp%'
    or current_position like '%eVp%'
    or current_position like '%eVP%'
    or current_position like '%董事%'
    or current_position like '%董事总经理%'
    or current_position like '%董事长%'
    or current_position like '%总裁%'
    or current_position like '%执行董事%'
    or current_position like '%事业部总经理%'
    or current_position like '%法人%'
    or current_position like '%书记%'
    or current_position like '%分总%'
    or current_position like '%hr%'
    or current_position like '%人力资源%'
    or current_position like '%招聘%'
    or current_position like '%合伙人%'
    or current_position like '%首席人才官合伙人%'
  ) = 0
  and (
    new_top_major like '%行长%'
    or new_top_major like '%院长%'
    or new_top_major like '%部长%'
    or new_top_major like '%科长%'
    or new_top_major like '%处长%'
    or new_top_major like '%局长%'
    or new_top_major like '%厅长%'
    or new_top_major like '%市长%'
    or new_top_major like '%省长%'
    or new_top_major like '%系长%'
    or new_top_major like '%校长%'
    or new_top_major like '%厂长%'
    or new_top_major like '%会长%'
    or new_top_major like '%所长%'
    or new_top_major like '%理事长%'
    or new_top_major like '%秘书长%'
    or new_top_major like '%园长%'
    or new_top_major like '%总经办%'
    or new_top_major like '%主编%'
    or new_top_major like '%主任%'
    or new_top_major like '%总编%'
    or new_top_major like '%制片人%'
    or new_top_major like '%导演%'
    or new_top_major like '%店长%'
    or new_top_major like '%总裁%'
    or new_top_major like '%总经理%'
    or new_top_major like '%创始人%'
    or new_top_major like '%首席%'
    or new_top_major like '%Cbo%'
    or new_top_major like '%CBo%'
    or new_top_major like '%CBO%'
    or new_top_major like '%cbo%'
    or new_top_major like '%cBo%'
    or new_top_major like '%cBO%'
    or new_top_major like '%cDo%'
    or new_top_major like '%CDo%'
    or new_top_major like '%CDO%'
    or new_top_major like '%cdo%'
    or new_top_major like '%cDo%'
    or new_top_major like '%cDO%'
    or new_top_major like '%Ceo%'
    or new_top_major like '%CEo%'
    or new_top_major like '%CEO%'
    or new_top_major like '%ceo%'
    or new_top_major like '%cEo%'
    or new_top_major like '%cEO%'
    or new_top_major like '%Cfo%'
    or new_top_major like '%CFo%'
    or new_top_major like '%CFO%'
    or new_top_major like '%cFo%'
    or new_top_major like '%cFO%'
    or new_top_major like '%cfo%'
    or new_top_major like '%Cho%'
    or new_top_major like '%CHo%'
    or new_top_major like '%CHO%'
    or new_top_major like '%cHO%'
    or new_top_major like '%cHo%'
    or new_top_major like '%cho%'
    or new_top_major like '%CIO%'
    or new_top_major like '%CIo%'
    or new_top_major like '%Cio%'
    or new_top_major like '%cio%'
    or new_top_major like '%cIo%'
    or new_top_major like '%cIO%'
    or new_top_major like '%Cso%'
    or new_top_major like '%CSo%'
    or new_top_major like '%CSO%'
    or new_top_major like '%cso%'
    or new_top_major like '%cSo%'
    or new_top_major like '%cSO%'
    or new_top_major like '%Cto%'
    or new_top_major like '%CTo%'
    or new_top_major like '%CTO%'
    or new_top_major like '%cto%'
    or new_top_major like '%cTo%'
    or new_top_major like '%cTO%'
    or new_top_major like '%Cxo%'
    or new_top_major like '%CXo%'
    or new_top_major like '%CXO%'
    or new_top_major like '%cxo%'
    or new_top_major like '%cXo%'
    or new_top_major like '%cXO%'
    or new_top_major like '%Cmo%'
    or new_top_major like '%CMo%'
    or new_top_major like '%CMO%'
    or new_top_major like '%cMo%'
    or new_top_major like '%cMO%'
    or new_top_major like '%cmo%'
    or new_top_major like '%Coo%'
    or new_top_major like '%COo%'
    or new_top_major like '%COO%'
    or new_top_major like '%coo%'
    or new_top_major like '%cOo%'
    or new_top_major like '%cOO%'
    or new_top_major like '%Director%'
    or new_top_major like '%director%'
    or new_top_major like '%GM%'
    or new_top_major like '%Gm%'
    or new_top_major like '%gm%'
    or new_top_major like '%gM%'
    or new_top_major like '%head%'
    or new_top_major like '%Head%'
    or new_top_major like '%HEAD%'
    or new_top_major like '%VP%'
    or new_top_major like '%vp%'
    or new_top_major like '%Vp%'
    or new_top_major like '%vP%'
    or new_top_major like '%Svp%'
    or new_top_major like '%SVp%'
    or new_top_major like '%SVP%'
    or new_top_major like '%svp%'
    or new_top_major like '%sVP%'
    or new_top_major like '%sVp%'
    or new_top_major like '%Evp%'
    or new_top_major like '%EVp%'
    or new_top_major like '%EVP%'
    or new_top_major like '%evp%'
    or new_top_major like '%eVp%'
    or new_top_major like '%eVP%'
    or new_top_major like '%董事%'
    or new_top_major like '%董事总经理%'
    or new_top_major like '%董事长%'
    or new_top_major like '%总裁%'
    or new_top_major like '%执行董事%'
    or new_top_major like '%事业部总经理%'
    or new_top_major like '%法人%'
    or new_top_major like '%书记%'
    or new_top_major like '%分总%'
    or new_top_major like '%hr%'
    or new_top_major like '%人力资源%'
    or new_top_major like '%招聘%'
    or new_top_major like '%合伙人%'
    or new_top_major like '%首席人才官合伙人%'
  ) = 0