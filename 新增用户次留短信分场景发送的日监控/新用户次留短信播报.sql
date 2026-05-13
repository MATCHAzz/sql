select
  d,
  `新增DAU-未注销` as `sql量级`,
  `未注销次日被发送增长-短信量` as `触达平台下发成功量级`,
  `未注销次日收到增长-短信量` as `通道返回成功量级`,
  `触达平台下发成功量级`/`sql量级` as `下发占比`,
  `通道返回成功量级`/`sql量级` as `下发成功占比`,
  `通道返回成功量级`/`触达平台下发成功量级` as `通道成功率`
from 
(
  select 
    a1.d+1 as d,
    uniqExact(a1.uid)                                                            as `新增DAU`,
    uniqExactIf(a1.uid,is_send_success=1 and is_growth=1)                        as `次日收到增长-短信量`,
    uniqExactIf(a1.uid,is_send_success=1 )                                       as `次日收到全站-短信量`,
    `次日收到增长-短信量`/`新增DAU` as `新用户次日收到增长短信-占比`,
    `次日收到全站-短信量`/`新增DAU` as `新用户次日收到全站短信-占比`,
    
    uniqExactIf(a1.uid,is_send_success=1 and is_growth=1 and is_liucun=1)           as `次日收到增长-留存量`,
    uniqExactIf(a1.uid,is_send_success=1 and is_liucun=1 )                          as `次日收到全站-留存量`,
    `次日收到全站-留存量`/`次日收到全站-短信量` as `次日留存率-收到全站短信`,
    `次日收到增长-留存量`/ `次日收到增长-短信量` as `次日留存率-收到增长短信`,
    
    uniqExactIf(a1.uid, is_liucun=1 )as `留存DAU`,
    `留存DAU`/ `新增DAU` as `新增DAU-留存率`,
    
    uniqExactIf(a1.uid,if_zhuxiao='已注销') as `新增DAU-注销`,
    `新增DAU-注销`/`新增DAU` as `注销用户占比`,
    uniqExactIf(a1.uid,if_zhuxiao='未注销') as `新增DAU-未注销`,
    uniqExactIf(a1.uid,is_send_success=1 and is_growth=1 and if_zhuxiao='未注销')   as `未注销次日收到增长-短信量`,
    uniqExactIf(a1.uid,is_send_success=1 and if_zhuxiao='未注销')                   as `未注销次日收到全站-短信量`,
    
    `未注销次日收到增长-短信量`/`新增DAU-未注销` as `未注销用户-次日收到增长短信占比`,
    `未注销次日收到全站-短信量`/`新增DAU-未注销` as `未注销用户-次日收到全站短信占比`,
    
    uniqExactIf(a1.uid,is_send=1 and is_growth=1 and if_zhuxiao='未注销')   as `未注销次日被发送增长-短信量`,
    uniqExactIf(a1.uid,is_send=1 and if_zhuxiao='未注销')                   as `未注销次日被发送全站-短信量`,
    
    `未注销次日被发送增长-短信量`/`新增DAU-未注销` as `未注销用户-次日被发送增长短信占比`,
    `未注销次日被发送全站-短信量`/`新增DAU-未注销` as `未注销用户-次日被发送全站短信占比`,
    uniqExactIf(a1.uid,is_send_success=1 and is_growth=1 and if_zhuxiao='未注销')/uniqExactIf(a1.uid,is_send=1 and is_growth=1 and if_zhuxiao='未注销') as `增长短信-发送成功率`,
    uniqExactIf(a1.uid,is_send_success=1  and if_zhuxiao='未注销')/uniqExactIf(a1.uid,is_send=1 and if_zhuxiao='未注销') as `全站短信-发送成功率`
    
  from
  (
    select a1.d as d,a1.uid as uid,if(is_zhuxiao=1,'已注销','未注销') as if_zhuxiao
    from(
        select d,uid
        from dws.dw_dau
        prewhere d >=yesterday()-20
        --and is_puppet = 0 
        and is_new_user = 1 
        group by d,uid
    )a1
    left join(
        --新增注销日期
        select  uid,toDate(uptime) as zhuxiao_date,1 as is_zhuxiao
        from mysqldump.user_auth_deleted
        prewhere toDate(uptime) >=yesterday()-20
        group by uid,zhuxiao_date
       
    )a2 
    on a1.d=a2.zhuxiao_date and a1.uid=a2.uid
    group by d,uid,if_zhuxiao
  )a1
  all left join
  (
    select d,uid,is_send_success,if(tag like '%recall_1day%',1,0 ) as is_growth,1 as is_send
    from dws.dw_sms_di
    prewhere d >=yesterday()-20
    group by d,uid,is_send_success,is_growth
  )a2 
  on a2.d=addDays(a1.d,1) and a1.uid=a2.uid 
  left join
  (
    select d,uid,1 as is_liucun
    from dws.dw_dau
    prewhere d >=yesterday()-20  and is_puppet = 0 
    group by d,uid
  )a3 
  on a3.d=addDays(a1.d,1) and a1.uid=a3.uid 
  group by d
)
where d<=yesterday()
