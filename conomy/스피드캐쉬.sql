-- new
SELECT YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3) AS year_week,
                       DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
                       DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
                       CONCAT(ur2.name,'(',ur2.user_id,')') AS referrer,
                       COUNT(1) AS subs_count,
                       SUM(ss.price) AS subs_price,
                       SUM(so.speed_cash) AS speed_cash
                  FROM subs_order_payment op
                  JOIN subs_orders so ON op.subs_orders_id=so.subs_orders_id
                  JOIN subs ss ON so.subs_id=ss.subs_id
                  JOIN user ur ON so.user_id=ur.user_id
                  JOIN my_referrer mr ON so.user_id=mr.user_id
                  JOIN user ur2 ON mr.referrer_user_id=ur2.user_id
                 WHERE op.is_success=1
                   AND LEFT(op.created_at,10)=so.subs_start_date
                   AND LEFT(YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3),4) = :base_year
                 GROUP BY 1,2,3,4
                 ORDER BY year_week DESC, referrer;

-- cancel
SELECT YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3) AS year_week,
                       DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
                       DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
                       CONCAT(ur2.name,'(',ur2.user_id,')') AS referrer,
                       COUNT(1) AS subs_count,
                       SUM(ss.price) AS subs_price,
                       SUM(so.speed_cash) AS paid_speed_cash,
                       SUM((SELECT COUNT(1) FROM subs_order_payment sop
                                                                          WHERE sc.subs_orders_id=sop.subs_orders_id)),
                       TRUNCATE(SUM(so.speed_cash) - SUM(so.speed_cash * (SELECT COUNT(1) FROM subs_order_payment sop
                                                                          WHERE sc.subs_orders_id=sop.subs_orders_id and sop.is_success=1) / 12),0) AS return_speed_cash,
                       SUM((SELECT COUNT(1) FROM subs_order_payment sop WHERE sc.subs_orders_id=sop.subs_orders_id)) AS received_cnt
                  FROM subs_order_cancel sc
                  JOIN subs_orders so ON sc.subs_orders_id=so.subs_orders_id AND so.speed_cash <> 0
                  JOIN subs ss ON so.subs_id=ss.subs_id
                  JOIN user ur ON so.user_id=ur.user_id
                  JOIN my_referrer mr ON so.user_id=mr.user_id
                  JOIN user ur2 ON mr.referrer_user_id=ur2.user_id
                 WHERE sc.status=2
                   AND LEFT(YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3),4) = :base_year
                 GROUP BY 1,2,3,4
                 ORDER BY year_week DESC, referrer
;

select * from user where name = '조장란';

select * from subs_orders where user_id='c1691e54-4c75-4b12-bde3-8aca3c7a0411';

select * from subs_order_payment where subs_orders_id='17ce115c-355c-4c3d-8d66-2b22b9e4fd0f';