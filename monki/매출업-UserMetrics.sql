select
--     count(distinct user_id)
    um.user_id,umv.field_name,umf.field_description,umv.*
 from sellup.user_metrics um
    join sellup.user_metrics_value umv on um.user_metrics_id=umv.user_metrics_id
    join sellup.user_metrics_field umf on umv.field_name=umf.field_name
 where um.store_no=841 and um.snap_date='2026-06-12'
 order by um.user_id,umv.field_name;

select count(distinct user_id) from table_order.user_stores us
 where us.store_no=841

select * from table_order.coupon where store_no=841 order by created_at desc;


