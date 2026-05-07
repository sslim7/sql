select so.subs_orders_id,
       left(so.subs_start_date,10) start_date,
       case so.is_active when 1 then '구독중' when 2 then '구독종료' else so.is_active end status,
       case ss.category when '1010' then '설악천연수' when '1020' then '웰니스 레볼루션' when '1030' then '뷰티 레볼루션' when '1040' then '펫샵' else ss.category end category,
       sc.name sub_cate_name,
       ss.name subs_name,
       ss.description subs_desc,
       so.remain_seats remain_qty,
       so.billing_day,
       ss.plan,
       ss.price,
       (select concat(left(sop.created_at,10), case when sop.failure_reason is null then '' else concat('(',sop.failure_reason,')') end)
          from subs_order_payment sop
         where so.subs_orders_id=sop.subs_orders_id
         order by created_at desc limit 1) last_paid,
       (select sum(oi.order_qty) from orders od join order_items oi on od.order_id=oi.order_id where od.subs_order_id=so.subs_orders_id and od.order_status<>99) order_qty,
       (select left(od2.created_at,10) from orders od2 where od2.subs_order_id=so.subs_orders_id and od2.order_status<>99 order by sc.created_at desc limit 1) last_order,
       oc.created_at cancel_request_at,
       (select case
                 when next_expected_date > today_kst then 0
                 else datediff(today_kst, next_expected_date)
               end
          from (
            select date(convert_tz(now(), '+00:00', '+09:00')) as today_kst,
                   case
                     when (select max(billing_yymm) from subs_order_payment
                            where subs_orders_id=so.subs_orders_id and is_success=1) is null
                       then so.subs_start_date
                     else date_add(
                            date_add(
                              str_to_date(concat(
                                (select max(billing_yymm) from subs_order_payment
                                  where subs_orders_id=so.subs_orders_id and is_success=1),
                                '01'), '%Y%m%d'),
                              interval 1 month),
                            interval (so.billing_day - 1) day)
                   end as next_expected_date
          ) t
       ) overdue_days
  from subs_orders so
  join subs ss on so.subs_id=ss.subs_id
  join sub_cate sc on ss.sub_cate_id=sc.sub_cate_id
  left join subs_order_cancel oc on so.subs_orders_id=oc.subs_orders_id
 where so.user_id=:user_id
 order by so.is_active, so.subs_start_date desc;