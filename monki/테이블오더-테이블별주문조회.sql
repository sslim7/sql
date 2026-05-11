select gr.resource_name,
       tdo.deal_id,
       any_value(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') dt,
       count(1),
       max(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') -
       min(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') AS diff_time,
       min(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') AS first_time,
       max(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') AS last_time
       from pos.tb_ground_resource gr
         join pos.tb_deal_order tdo on gr.store_no=tdo.store_no and gr.resource_id=tdo.resource_id
          and to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul' > '2026-05-01'
         where
             gr.store_no=891 and gr.resource_name like '야장%'
 group by 1,2
 having max(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') -
       min(to_timestamp(tdo.reg_dt) AT TIME ZONE 'Asia/Seoul') > interval '2 hours'
 order by dt desc;

select * from pos.tb_ground_resource gr where gr.store_no=891
--                                           and gr.resource_name like '야장%'
and gr.ext_resource_id in ('008', '034', '055', '047', '045', '065', '054', '031', '053', '052', '009', '007', '005', '044', '062', '037', '043');

select * from public.tb_store_product where store_no=891 and pos_product_code like '000210%';
select * from public.tb_menu where store_no=891;

select * from