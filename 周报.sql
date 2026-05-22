select d,class,carrier,lad,`通道`,is_mem
     ,cnt_uv `触达平台发送uv`
     ,report_suc_uv `通道返回成功uv`
     ,case when d = '2025-12-10' and( `通道` = '百应' or `通道` like '挂机短信%') then report_suc_uv
     else cnt_suc_pv  end as `返回成功*文案长度`
     ,`召回`
    ,`召回招聘dau`
     ,`返回成功*文案长度` * case
                       when `通道`= '泰迪熊TDX'           then 0.022
                       when `通道`= '秒信HDHC'           then 0.027
                       when `通道`= '创蓝hdhc1'           then 0.03
                       when `通道`= '中网讯通'            then 0.03
                       when `通道`= '聚梦'                then 0.027
                       when `通道`= '腾域HDHC'            then 0.029
                       when `通道`= '秒信HDHC'            then 0.03
                       when `通道`= '助通HDHC1'           then 0.0278
                       when `通道`= '阿里云HDLC'          then 0.027
                       when `通道`= '阿里云1'             then 0.027
                       when `通道`= '湖南云客' then 0.027
                       when `通道`= '一知' and d < '2025-07-16'      then 0.13
                       when `通道`= '一知' and d >= '2025-07-16'      then 0.16
                       when `通道`= 'aliyun_ai'           then 0.14

                       when `通道`= '文本短信-3日前'      then 0.03

                       when `通道`= '百应' and d < '2025-07-17'     then 0.16
                       when  `通道`= '百应' and d >= '2025-07-17'  and d <= '2025-08-31'   then 0.17
                       when `通道`= '百应' and d >= '2025-09-01' then 0.15
                       when `通道`= '智齿'                then 0.12
                       when `通道`= '挂机短信-聚梦'       then 0.027
                       when `通道`= '挂机短信-秒信HDHC'       then 0.03
                       when `通道`= '挂机短信-中网讯通'   then 0.03
                       when `通道`= '挂机短信-阿里云1'   then 0.027
                       when `通道`= '泰迪'                then 0.12
                       when `通道`= '展奎'                then 0.12

                       when `通道`= '视频短信'            then 0.076
                       when `通道`= '微信/特殊push'       then 0
                       when `通道`= '华为营销'            then 0.032
                       when `通道`= 'BFSHHDHC'            then 0.022
                       else 0 end as fee
from (
    with
        substringUTF8(content,1,5) as con,
        lengthUTF8(content) as cnt,
        if(con like '【脉脉】%',cnt,if(providerChannel like '%阿里云%',cnt+2,cnt+4)) as cnt_len

    select d,
        providerChannel `通道`,
        carrier,
        class,
        is_mem,
        lad,
        uniqExact(emobile) as cnt_uv,
        uniqExactIf(emobile,callback_status=1) as report_suc_uv,
        countIf(cnt_len<71)
        + countIf(cnt_len>=71 and cnt_len<=134)*2
        + countIf(cnt_len>=135 and cnt_len<=201)*3
        + countIf(cnt_len>=202)*4 as cnt_pv,
        countIf(cnt_len<71 and callback_status=1)
        + countIf(cnt_len>=71 and cnt_len<=134 and callback_status=1)*2
        + countIf(cnt_len>=135 and cnt_len<=201 and callback_status=1)*3
        + countIf(cnt_len>=202 and callback_status=1)*4 as cnt_suc_pv

    from
       (with
        subString(emobile,1,3) as mobile_num,
        subString(emobile,1,4) as mobile_numn,
        case when mobile_num in ('133', '153', '189', '180', '181', '199', '173', '177') or mobile_numn  in ( '1701', '1702')
        then '电信'
        when mobile_num in ('134', '135', '136', '137', '138', '139', '147', '150', '151', '158', '159', '157', '154',
        '152', '178', '188', '187', '182', '183', '184', '1705', '1703', '1706', '198') or mobile_numn  in ( '1703', '1705','1706')
        then '移动'
        else '联通' end as carrier
        select emobile,d,is_send_success callback_status,tag,content,uid
       ,carrier
       ,if((tag like '%机遇%' or tag like '%兜底%' or tag like '%首播%' or tag like '%复播%' or tag like '机遇%' or tag like 'zhichi%' or tag like '百应%' or tag like '智齿%'or tag like 'yizhi%' or tag like '高薪%' or tag like '阿里云%'),'挂机短信-'||provider_channel,provider_channel)providerChannel
       ,case when d-last_active_date between  0 and  29 then '0-29'
        when d-last_active_date between 30 and 35 then '30-35'
        when d-last_active_date between  36 and  59  then '36-59'
        when d-last_active_date between 60  and  100 then '60-100'
        when d-last_active_date between 101 and 166  then '101-166'
        when d-last_active_date between 167  and  365 then '167-365'
        when d-last_active_date between   366 and  1080 then '366-1080'
        else '1080' end as lad
       ,case
        when  economy = '新经济行业' and  type = '头部' then '新经济头部'
        when  economy = '新经济行业' and  type in ('腰部', '尾部') then '新经济腰尾'
        when  economy = '学生' then '学生'
        when  economy = '传统行业' and  (new_top_major in ('研发', '产品', '运营', '设计', '销售', 'CEO/创始人/企业高管', '人力资源(HR)/人事', '商务拓展(BD)/渠道', '商务拓展合作(BD)',
        'IT支持/网络运维', '测试', '数据分析', '销售人员', '猎头', '商务') )
        or  (economy = '传统行业' and new_top_major not in ('研发', '产品', '运营', '设计', '销售', 'CEO/创始人/企业高管', '人力资源(HR)/人事', '商务拓展(BD)/渠道', '商务拓展合作(BD)',
        'IT支持/网络运维', '测试', '数据分析', '销售人员', '猎头', '商务') and  ( city_tier in ('一线', '新一线') or  degree in ('本科', '硕士', '博士') or  career_level in ('中级人才', '高级人才') or
        brand in ('APPLE', 'HUAWEI'))) then '传统主流一线'
        when  economy = '传统行业' and  new_top_major not in ('研发', '产品', '运营', '设计', '销售', 'CEO/创始人/企业高管', '人力资源(HR)/人事', '商务拓展(BD)/渠道', '商务拓展合作(BD)',
        'IT支持/网络运维', '测试', '数据分析', '销售人员', '猎头', '商务') and not ( city_tier in ('一线', '新一线') or  degree in ('本科', '硕士', '博士') or  career_level in ('中级人才', '高级人才') or
        brand in ('APPLE', 'HUAWEI')) then '传统行业其他'
        when  economy='' and  new_top_major in ('研发', '产品', '运营', '设计', '销售', 'CEO/创始人/企业高管', '人力资源(HR)/人事', '商务拓展(BD)/渠道', '商务拓展合作(BD)',
        'IT支持/网络运维', '测试', '数据分析', '销售人员', '猎头', '商务') then '其他主流行业'
        else '其他非主流' end as  class
       ,if(uid in (select uid from dim.dim_user where lv3_major in ('BD经理','CFO','CMO','COO','CTO','HRBP-HRM','保险','保险顾问','财务顾问','采购','采购经理',
        '采购总监','产品VP','厂长','城市经理','出版-发行','大客户代表','代理商销售','导演-编导','董事会秘书',
        '高级管理职位','公关总监','广告','广告销售','海外市场','行业研究','行政主管','活动策划执行','记者','教练',
        '金融销售','经纪人','经理助理','客户代表','客户经理','理财顾问','联合创始人','猎头','律师','媒介经理','媒介投放','媒介总监',
        '美容顾问','培训','品牌公关','企业管理咨询','汽车服务顾问','区域总监','渠道销售','人力资源','人力资源VP-CHO','人力资源经理',
        '人力资源主管','人力资源专员-人力资源助理','人力资源咨询顾问','人力资源总监','融资','商家运营','商务经理','商务渠道','商务总监','市场营销',
        '市场总监-高级市场总监','投资顾问','投资合伙人','投资经理','投资助理','投资总监','团队经理','网络营销','物业招商管理','线下拓展运营','销售',
        '销售VP','销售工程师','销售顾问','销售经理','销售专员','销售总监','校长-副校长','心理咨询师','信贷管理','银行客户经理','游戏发行制作人-游戏发行-游戏制作',
        '园长-副园长','战略咨询','招聘','招生顾问','政府关系','政府事务','制片人','主持人-DJ','咨询','总裁-总经理-CEO','组织发展','并购','财务总监','采编',
        '策略运营','产品总监','创意总监','地产项目管理','法务总监','供应链总监','行政经理','行政总监','互联网金融','互联网金融分析师',
        '技术项目经理','技术项目主管','绩效考核','健康顾问','金融产品经理','理疗师','零售','绿化工','人工智能',
        '商品经理','商业数据分析','设计经理-设计主管','设计总监','深度学习','生产营运','生产总监','市政建设','投后管理','推荐算法','外贸经理','物流总监',
        '选址开发','演员-配音-模特','医生','医学总监','音频编辑','银行','影视策划','用户运营','运营经理-运营主管','运营总监','证券',
        '智能驾驶系统工程师-自动驾驶-智能驾驶','中医','主编','撰稿人','总编',
        --新添加的工种如下：
        '合伙人','技术合伙人','财务经理','市场总监','投融资','投资VP','投资者关系','融资总监','咨询总监','高端市场职位','项目总监','销售管理','分公司-代表处负责人','副总裁-副总经理-VP','事业部负责人','总助-CEO助理-董事长助理','渠道经理','市场经理'
        --7.2由于改名而新加的工种
       ,'猎头顾问','人力资源专员-助理','游戏发行人','智能驾驶系统工程师'
        )),'会员潜客','非会员潜客')is_mem
        from dws.dw_sms_di
        any left join
       (select *,cid company_id from dim.dim_office_company)using company_id
        where d between '{{start}}' and '{{end}}'

        AND (tag LIKE 'recall%'
        OR tag LIKE 'bonus%'
        OR tag LIKE '%mengwang%'
        or tag like 'baiying%'
        or tag like 'zhichi%'
        or tag like '百应%'
        or tag like '智齿%'
        or tag like 'yizhi%'
        or tag like '高薪%'
        or tag like '阿里云%'
        or tag like '%机遇%'
        or tag like '%兜底%'
        or tag like '%首播%'
        or tag like '%复播%'
        or tag like '一知'
        )
        AND tag NOT LIKE 'recall_today_1_send_msg%'
        AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
        )
    group by d,providerChannel
           ,class,lad,carrier,is_mem

    union all

    select
        d
         ,type "通道"
         ,carrier
         ,class
         ,is_mem
         ,lad
         ,uniqExactIf(uid,nextdaycall=0) send_uv
         ,uniqExactIf(uid,success=1) send_success_uv
         ,0
         ,countIf(uid,success=1) send_success_pv
    from(
        select uid,d
       ,case when d-last_active_date between  0 and  29 then '0-29'
        when d-last_active_date between 30 and 35 then '30-35'
        when d-last_active_date between 36 and 59 then '36-59'
        when d-last_active_date between 60 and 100 then '60-100'
        when d-last_active_date between 101 and 166  then '101-166'
        when d-last_active_date between 167  and  365 then '167-365'
        when d-last_active_date between 366  and  1080 then '366-1080'
        else '1080' end as lad
       ,success
       ,class
       ,carrier
       ,sms_type
       ,type
       ,nextdaycall
       ,if(uid in (select uid from dim.dim_user where lv3_major in ('BD经理','CFO','CMO','COO','CTO','HRBP-HRM','保险','保险顾问','财务顾问','采购','采购经理',
        '采购总监','产品VP','厂长','城市经理','出版-发行','大客户代表','代理商销售','导演-编导','董事会秘书',
        '高级管理职位','公关总监','广告','广告销售','海外市场','行业研究','行政主管','活动策划执行','记者','教练',
        '金融销售','经纪人','经理助理','客户代表','客户经理','理财顾问','联合创始人','猎头','律师','媒介经理','媒介投放','媒介总监',
        '美容顾问','培训','品牌公关','企业管理咨询','汽车服务顾问','区域总监','渠道销售','人力资源','人力资源VP-CHO','人力资源经理',
        '人力资源主管','人力资源专员-人力资源助理','人力资源咨询顾问','人力资源总监','融资','商家运营','商务经理','商务渠道','商务总监','市场营销',
        '市场总监-高级市场总监','投资顾问','投资合伙人','投资经理','投资助理','投资总监','团队经理','网络营销','物业招商管理','线下拓展运营','销售',
        '销售VP','销售工程师','销售顾问','销售经理','销售专员','销售总监','校长-副校长','心理咨询师','信贷管理','银行客户经理','游戏发行制作人-游戏发行-游戏制作',
        '园长-副园长','战略咨询','招聘','招生顾问','政府关系','政府事务','制片人','主持人-DJ','咨询','总裁-总经理-CEO','组织发展','并购','财务总监','采编',
        '策略运营','产品总监','创意总监','地产项目管理','法务总监','供应链总监','行政经理','行政总监','互联网金融','互联网金融分析师',
        '技术项目经理','技术项目主管','绩效考核','健康顾问','金融产品经理','理疗师','零售','绿化工','人工智能',
        '商品经理','商业数据分析','设计经理-设计主管','设计总监','深度学习','生产营运','生产总监','市政建设','投后管理','推荐算法','外贸经理','物流总监',
        '选址开发','演员-配音-模特','医生','医学总监','音频编辑','银行','影视策划','用户运营','运营经理-运营主管','运营总监','证券',
        '智能驾驶系统工程师-自动驾驶-智能驾驶','中医','主编','撰稿人','总编',
        --新添加的工种如下：
        '合伙人','技术合伙人','财务经理','市场总监','投融资','投资VP','投资者关系','融资总监','咨询总监','高端市场职位','项目总监','销售管理','分公司-代表处负责人','副总裁-副总经理-VP','事业部负责人','总助-CEO助理-董事长助理','渠道经理','市场经理'
        --7.2由于改名而新加的工种
       ,'猎头顾问','人力资源专员-助理','游戏发行人','智能驾驶系统工程师'
        ) ),'会员潜客','非会员潜客')is_mem
        from (with
        subString(emobile,1,3) as mobile_num,
        subString(emobile,1,4) as mobile_numn,
        case when mobile_num in ('133', '153', '189', '180', '181', '199', '173', '177') or mobile_numn  in ( '1701', '1702')
        then '电信'
        when mobile_num in ('134', '135', '136', '137', '138', '139', '147', '150', '151', '158', '159', '157', '154',
        '152', '178', '188', '187', '182', '183', '184', '1705', '1703', '1706', '198') or mobile_numn  in ( '1703', '1705','1706')
        then '移动'
        else '联通' end as carrier
        select uid,if(nextdaycall=1 ,d-1,d) d, case
        when class in('传统行业主流职业' ,'传统行业非主流职业一线新一线or高学历or中高端or苹果华为') then '传统主流一线'
        when class in('其他华为苹果中高端新一线' , '其他其他' ) then '其他非主流'
        else class end class
       ,if(dau=1,lad,last_active_date)last_active_date
       ,'智能电话' as sms_type
       ,carrier
       ,type
       ,(
       (type ='容联' and reason=0)
        or
       (type ='百应' and reason=1)
        or
       (type ='智齿' and reason=2)
        or
       (type ='中通天鸿' and reason=201)
        or
       (type ='泰迪' and reason=1)
       or 
       (type ='一知' and reason=1)
       or 
       (type ='jumeng' and reason=1)
       or 
       (type ='aliyun_ai' and reason=1)
        )as success
       ,(task_name like '%复播' or task_name like '%次日复%' ) as nextdaycall
        from dwd.dw_growth_sms_smartphone_call_di
        any left join
       (select toUInt64(uid)uid,d,last_active_date lad,1 as dau
        from dws.dw_dau
        where d between '{{start}}' and '{{end}}'
        )using uid,d
        where d between '{{start}}' and '{{end}}'
        and uid!=0
        )
        )
    group by d,class,lad,type ,carrier,is_mem
)
    full join
(
    select *,dt d
    from

        (

            select
                dt
                 ,carrier
                 ,class,is_mem,lad
                 ,if(provider_channel_1='',if(provider_channel_2='' ,sms_type,provider_channel_2),provider_channel_1)  as `通道`
                 ,uniqExact(uid)`召回`,
                 uniqExactIf(  uid, 
                 (dt,uid) in (select d,uid from dwm.dw_growth_user_active_di prewhere is_jobs_dau and d between '{{start}}' and '{{end}}') 
                 ) `召回招聘dau`

            from
                (
                    select
                        case when sms_type='智能电话' then replace(replace(tag,'recall_phone_',''),'电话','')
                             when sms_type !='文本短信-3日前' then sms_type
                             else if(provider_channel!='' and sms_type ='文本短信-3日前',provider_channel,'') end as provider_channel_
                         ,if(provider_channel_='yizhi','一知',provider_channel_) provider_channel_1
                         ,uid,d,tag,emobile,lad,class,sms_type
                         ,if(uid in (select uid from dim.dim_user where lv3_major in ('BD经理','CFO','CMO','COO','CTO','HRBP-HRM','保险','保险顾问','财务顾问','采购','采购经理',
                                                                                      '采购总监','产品VP','厂长','城市经理','出版-发行','大客户代表','代理商销售','导演-编导','董事会秘书',
                                                                                      '高级管理职位','公关总监','广告','广告销售','海外市场','行业研究','行政主管','活动策划执行','记者','教练',
                                                                                      '金融销售','经纪人','经理助理','客户代表','客户经理','理财顾问','联合创始人','猎头','律师','媒介经理','媒介投放','媒介总监',
                                                                                      '美容顾问','培训','品牌公关','企业管理咨询','汽车服务顾问','区域总监','渠道销售','人力资源','人力资源VP-CHO','人力资源经理',
                                                                                      '人力资源主管','人力资源专员-人力资源助理','人力资源咨询顾问','人力资源总监','融资','商家运营','商务经理','商务渠道','商务总监','市场营销',
                                                                                      '市场总监-高级市场总监','投资顾问','投资合伙人','投资经理','投资助理','投资总监','团队经理','网络营销','物业招商管理','线下拓展运营','销售',
                                                                                      '销售VP','销售工程师','销售顾问','销售经理','销售专员','销售总监','校长-副校长','心理咨询师','信贷管理','银行客户经理','游戏发行制作人-游戏发行-游戏制作',
                                                                                      '园长-副园长','战略咨询','招聘','招生顾问','政府关系','政府事务','制片人','主持人-DJ','咨询','总裁-总经理-CEO','组织发展','并购','财务总监','采编',
                                                                                      '策略运营','产品总监','创意总监','地产项目管理','法务总监','供应链总监','行政经理','行政总监','互联网金融','互联网金融分析师',
                                                                                      '技术项目经理','技术项目主管','绩效考核','健康顾问','金融产品经理','理疗师','零售','绿化工','人工智能',
                                                                                      '商品经理','商业数据分析','设计经理-设计主管','设计总监','深度学习','生产营运','生产总监','市政建设','投后管理','推荐算法','外贸经理','物流总监',
                                                                                      '选址开发','演员-配音-模特','医生','医学总监','音频编辑','银行','影视策划','用户运营','运营经理-运营主管','运营总监','证券',
                                                                                      '智能驾驶系统工程师-自动驾驶-智能驾驶','中医','主编','撰稿人','总编',
                                                                                      --新添加的工种如下：
                                                                                          '合伙人','技术合伙人','财务经理','市场总监','投融资','投资VP','投资者关系','融资总监','咨询总监','高端市场职位','项目总监','销售管理','分公司-代表处负责人','副总裁-副总经理-VP','事业部负责人','总助-CEO助理-董事长助理','渠道经理','市场经理'
                                                                                          --7.2由于改名而新加的工种
                        ,'猎头顾问','人力资源专员-助理','游戏发行人','智能驾驶系统工程师'
                        )),'会员潜客','非会员潜客')is_mem
                         ,dt
                         ,carrier
                    from(
                        with
                            subString(emobile,1,3) as mobile_num,
                            subString(emobile,1,4) as mobile_numn,
                            case when mobile_num in ('133', '153', '189', '180', '181', '199', '173', '177') or mobile_numn  in ( '1701', '1702')
                            then '电信'
                            when mobile_num in ('134', '135', '136', '137', '138', '139', '147', '150', '151', '158', '159', '157', '154',
                            '152', '178', '188', '187', '182', '183', '184', '1705', '1703', '1706', '198') or mobile_numn  in ( '1703', '1705','1706')
                            then '移动'
                            else '联通' end as carrier
                        SELECT uid,d,lad,seven_class class,emobile,tag,touch_msg_id
                             ,dt
                             ,carrier
                             ,case when tag like 'recall_phone%' then '智能电话'
                            when tag like '%wechat%' then '微信'
                            when tag like 'recall_push%' then '特殊push'
                            when tag like '%fumeiti%' then '视频短信'
                            when tag like 'recall_%' then '文本短信-3日前'
                            else '' end sms_type
                        from
                           (
                            select
                            dt ,d,uid,tag,emobile,touch_msg_id
                            from
                           (select
                            *,if(tag like 'recall_phone%' and nextdaycall=1,d-1,d)dt
                            FROM dwm.dw_growth_user_sms_recall_di
                            any left join
                           (select toUInt32(uid)uid,d,(task_name like '%复播' or task_name like '%次日复%' ) as nextdaycall
                            from
                            dwd.dw_growth_sms_smartphone_call_di
                            where (task_name like '%复播' or task_name like '%次日复%')
                            and d>='2024-03-01'
                        -- and d>=today()-21

                            and (
                           (type ='容联' and reason=0)
                            or
                           (type ='百应' and reason=1)
                            or
                           (type ='智齿' and reason=2)
                            or
                           (type ='中通天鸿' and reason=201)
                            or
                           (type ='泰迪' and reason=1)
                           or 
                           (type ='一知' and reason=1)
                           or 
                           (type ='jumeng' and reason=1)
                           or 
                           (type ='aliyun_ai' and reason=1)
                            )
                            )using uid,d
                            where d between '{{start}}' and '{{end}}'  ))
                            any inner join
                           (select uid,d,seven_class
                           ,case
                            when silent_days between 0 and 29 then '0-29'
                            when silent_days between 30 and 35 then '30-35'
                            when silent_days between 36 and 59 then '36-59'
                            when silent_days between 60 and 100 then '60-100'
                            when silent_days between 101 and 166 then '101-166'
                            when silent_days between 167 and 365 then '167-365'
                            when silent_days between 366 and 1080 then '366-1080'
                            else '1080' end as lad
                            from dwm.dw_growth_user_active_di
                            where d between '{{start}}' and '{{end}}'
                            and is_sms_touch=1
                            )using uid,d
                        WHERE d between '{{start}}' and '{{end}}'
                          AND (tag LIKE 'recall%'
                           OR tag LIKE 'bonus%'
                           OR tag LIKE '%mengwang%'
                            )
                          AND tag NOT LIKE 'recall_today_1_send_msg%'
                          AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                    )
                        any left join
                    (select sms_id touch_msg_id,d,uid,emobile,provider_channel,1 as sms
                     from dws.dw_sms_di
                     where d between  toDate('{{start}}' )-30 and '{{end}}'

                    )using emobile,touch_msg_id
                )
                    any left join
                (select provider_channel_2,tag,emobile,arrayJoin(arrayMap(x->dt+x,range(3))) d
                 from
                     (
                         select d dt,content, emobile,provider_channel provider_channel_2,tag
                         from dws.dw_sms_di
                         where d between toDate('{{start}}' )-3 and '{{end}}'
                           and is_send_success=1
                           and tag like 'recall%'
                         order by ts desc
                         -- limit 1 by emobile,d
                     ))using emobile,tag,d
            group by dt,carrier
                   ,class,lad,is_mem
                   ,`通道`))
using d,class,lad,`通道`,carrier,is_mem
where d  between  toDate('{{start}}' ) and '{{end}}'

UNION ALL

select d, '0' as class,'0' as carrier, '30+' as lad ,'普通push' as `通道`,'1' as is_mem
     ,0 `触达平台发送uv`
     ,0 `通道返回成功uv`
     ,0 `返回成功*文案长度`
     ,toUInt64(greatest(uniqExactIf(uid, normal_push = 1 AND d - last_active_date >= 30)- (uniqIf(d, toStartOfMonth(dt) = start_m) * 671),0)) as `召回`
      ,uniqExactIf(  uid, 
        (d ,uid) in (select d,uid from dwm.dw_growth_user_active_di prewhere is_jobs_dau and d between '{{start}}' and '{{end}}') 
        ) `召回招聘dau`
     ,0 as fee

from(
select uid,d,
case when d-last_active_date between  0 and  29 then '0-29'
        when d-last_active_date between 30 and 35 then '30-35'
        when d-last_active_date between  36 and  59  then '36-59'
        when d-last_active_date between 60  and  100 then '60-100'
        when d-last_active_date between 101 and 166  then '101-166'
        when d-last_active_date between 167  and  365 then '167-365'
        when d-last_active_date between 366 and  1080 then '366-1080'
        else '1080' end as lad
        ,is_sms_touch
        ,normal_push,sms_type
        ,last_active_date
        ,is_info_stream_priority
        ,economy,is_p,seven_class
        ,toStartOfMonth(d) as start_m
        ,arrayJoin(arrayMap(x->x+d ,range(33))) as dt 
        from
            (select *
            from(
            select uid,d,normal_push,sms_type,is_sms_touch,is_info_stream_priority,economy,seven_class
            ,(lv3_major in ((select lv3_major_map lv3_major from dim.dim_lv3_major_da where is_potential_customers=1)))is_p
                from dwm.dw_growth_user_active_di
                any left join
                (
                --普通push
                    select d d2,uid uid2,1 as normal_push
                    from
                        (select uid,d,push_id
                            from dws.dw_push_di
                        where tag not like 'recall_push_xiaomi%'  and tag not like 'recall_push_huawei%'  
                        and tag like '%recall_push%' 
                        and d between '{{start}}' and '{{end}}'
                        and (uid,d) in (select uid,d from dwm.dw_growth_user_active_di
                                        where d between '{{start}}' and '{{end}}' and  is_info_stream_priority=0 and is_push_click_priority=1 and is_silent_30d=1 and is_new=0)
                        )
                        any inner join
                            (select uid,d,push_id
                            from dwd.dw_push_click
                            where  d between '{{start}}' and '{{end}}'
                        )using d,push_id

                ) on uid=uid2 and d=d2

                any left join
                (
                select d d3,uid uid3,
                    case when tag like 'recall_phone%' then '智能电话'
                      when tag like 'recall_wechat%' then 'wechat'
                      when tag like 'recall_push%' then 'push'
                      when tag like '%fumeiti%' then '视频短信'
                      when tag like 'recall_%' then '文本短信'
                      else '' end sms_type
                    from dwm.dw_growth_user_sms_recall_di
                    where d between '{{start}}' and '{{end}}'
                    AND (tag LIKE 'recall%'
                    OR tag LIKE 'bonus%'
                    OR tag LIKE '%mengwang%'
                          )
                    AND tag NOT LIKE 'recall_today_1_send_msg%'
                    AND tag NOT LIKE 'recall_after_3_send_msg_with_equity%'
                )on uid=uid3 and d=d3
                where d between '{{start}}' and '{{end}}'
            )
            )
        any left join 
        (
          select d,uid,last_active_date,company_id,1 as is_dau from dws.dw_dau where d>='2025-07-01' and is_new_user=0)
        using(d,uid)
        where normal_push = 1)
        where d between '{{start}}' and '{{end}}'
        group by d, class