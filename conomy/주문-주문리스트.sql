select #count(1)
    a.order_id,
                       a.subs_order_id,
                       c.order_item_id,
                       left(convert_tz(a.order_date,'UTC','Asia/Seoul'),16) order_date,
                       ur.name order_user_name,
                       a.order_number,
                       c.order_status ,
                       left(convert_tz(b.delivery_date,'UTC','Asia/Seoul'),16) delivery_date,
                       b.delivery_comment,
                       b.address,
                       b.address_detail,
                       b.receiver_name,
                       c.item_id,
                       c.order_qty,
                       a.use_points,
                       d.name,
                       case b.receipt_method when 1 then '택배' when 2 then '직접' else b.receipt_method end receipt_method,
                        b.zipcode,
                        b.phone_number,
                        b.invoice_no,
                       d.category,
                       a.user_id,
                       so.subs_start_date,
                       so.billing_day
                from order_items c
                         join shipping b on c.order_item_id = b.order_item_id
                         join item d on c.item_id = d.item_id
                         join orders a on a.order_id = c.order_id
                         join subs_orders so on a.subs_order_id=so.subs_orders_id
                         join user ur on a.user_id = ur.user_id
                where c.order_status in (1)
                order by a.order_date,so.billing_day,so.subs_start_date
;

select so.subs_start_date,count(1)
from subs_orders so
where subs_start_date>'2026-04-11' and is_active=1
group by 1
order by 1;

select * from subs;

select * from subs_order_payment;

# 차수
