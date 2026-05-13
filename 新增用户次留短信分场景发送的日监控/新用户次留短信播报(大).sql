select dt, `sql量级`,`触达平台下发成功量级`,`下发占比`,`通道返回成功量级`,`通道成功率`
from(
select dt,
uniqExact(uid) as `sql量级`,
uniqExactIf(uid, is_touched = 1) as `触达平台下发成功量级`,
uniqExactIf(uid, is_touched = 1 and is_send_success = 1) as `通道返回成功量级`,
`通道返回成功量级`/`触达平台下发成功量级` as `通道成功率`,
`通道返回成功量级`/`sql量级` as `下发占比`

--  `触达平台下发成功量级` / `sql量级` as `下发占比`
from(
select *
from(
select *
from(
select d+1 dt,uid
from dws.dw_dau
where dt - yesterday() in (0,-1,-2)
and is_new_user = 1 
group by dt,uid)
left join(
select uid,toDate(uptime)+1 as dt, 1 as is_delete
from mysqldump.user_auth_deleted
where dt - yesterday() in (0,-1,-2)
)using dt, uid
where is_delete != 1)
  any left join(
    select uid, dt,1 as is_touched,is_send_success,tag
      --uniqExact(uid) as `触达平台下发成功量级`,
      --uniqExactIf(uid, is_send_success = 1) as `通道返回成功量级`,
      --`通道返回成功量级` / `触达平台下发成功量级` as `通道成功率`
    from(
        select uid,
          d dt,
          tag,
          is_send_success
        from dws.dw_sms_di
        where tag like 'recall_1day%'
          and dt in (yesterday(), yesterday() -1,yesterday() - 2)
      )
  ) using dt,uid
)group by dt)