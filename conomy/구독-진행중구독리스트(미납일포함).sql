select so.subs_orders_id, ur.name user_name, ur.user_id, sc.name category, left(so.subs_start_date,10) subs_start_date,
       COALESCE((select sum(oi.order_qty) from orders od join order_items oi on od.order_id=oi.order_id where od.subs_order_id=so.subs_orders_id and od.order_status<>99),0) total_order_qty,
       COALESCE((select sum(oi.order_qty) from orders od join order_items oi on od.order_id=oi.order_id where od.subs_order_id=so.subs_orders_id and od.order_status=4),0) total_delivery_qty,
       (select count(1) from subs_order_payment sop where so.subs_orders_id=sop.subs_orders_id and sop.is_success=1) total_bill_cnt,
       case sb.plan when 1 then 'standard' when 2 then 'premium' when 3 then 'business' else sb.plan end plan,
       sb.description, sb.price, so.max_seats, so.remain_seats, sob.billingKey, case sob.is_active when 1 then 'active' else sob.is_active end sob_is_active,
       case sob.pg_type when 21 then 'toss' when 22 then 'nice' else sob.pg_type end pg_type,
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
join subs_order_billing sob on so.subs_orders_id=sob.subs_orders_id
join subs sb on so.subs_id=sb.subs_id
join user ur on so.user_id=ur.user_id
join sub_cate sc on sb.sub_cate_id=sc.sub_cate_id
where so.is_active=1
order by so.created_at desc;

select * from subs_order_payment where subs_orders_id="487a3ae5-41a1-48ee-b083-4485cc4eee65";

select * from subs_orders where user_id='b2852cb3-1149-4f41-99d9-f3f680d82346';
select * from subs_order_billing where subs_orders_id='2d6b8b44-fdac-4959-9059-d88013fc2ca4';
select * from subs_order_cancel where subs_orders_id='2d6b8b44-fdac-4959-9059-d88013fc2ca4';


select * from