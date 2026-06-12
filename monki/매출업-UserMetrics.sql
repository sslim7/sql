select * from sellup.user_metrics um
    join sellup.user_metrics_value umv on um.user_metrics_id=umv.user_metrics_id
    join sellup.user_metrics_field umf on umv.user_metrics_value_id=umf.user_metrics_field_id
 where um.store_no=841 and um.snap_date='2026-06-12'
 order by created_at desc;