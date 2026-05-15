select gr.resource_name,
       tdo.deal_id,
       any_value(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') dt,
       count(1),
       min(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') AS first_time,
       max(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') AS last_time,
       min(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') -
       max(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') AS diff_time
       from pos.tb_ground_resource gr
         join pos.tb_deal_order tdo on gr.store_no=tdo.store_no and gr.resource_id=tdo.resource_id
          and to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul' > '2026-05-01'
         where gr.store_no=891 and gr.resource_name like '야장%'
 group by 1,2
 order by dt desc;