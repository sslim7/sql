-- new
SELECT YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3) AS year_week,
                       DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
                       DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
                       ur2.user_id referrer_user_id,
                       CONCAT(any_value(ur2.name),'(',any_value(ur2.phone_no),')') AS referrer,
                       COUNT(1) AS new_subs_count,
                       SUM(ss.price) AS new_subs_price,
                       SUM(so.speed_cash) AS new_speed_cash
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
                       ur2.user_id referrer_user_id,
                       CONCAT(any_value(ur2.name),'(',any_value(ur2.phone_no),')') AS referrer,
                       COUNT(1) AS cancel_subs_count,
                       SUM(ss.price) AS cancel_subs_price,
                       SUM(so.speed_cash) AS paid_speed_cash,
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

주차(year_week), 기간()
year_week,week_start,week_end,referrer_user_id,referrer,new_subs_count,new_subs_price,speed_cash

week_end,referrer_user_id,referrer,cancel_subs_count,cancel_subs_price,paid_speed_cash,return_speed_cash,received_cnt

new의
year_week,week_start,week_end,referrer_user_id,referrer,speed_cash,return_speed_cash,speed_cash-return_speed_cash AS set_speed_cash
cancel의




-- 동일카드 사용자
select so.user_id 구독자ID,ur.name 구독자명,
       ur2.user_id 추천자ID,ur2.name 추천자명,
       bl.card_company,bl.card_number,
       count(1)
  from subs_order_billing bl
  join subs_orders so on bl.subs_orders_id=so.subs_orders_id and so.is_active=1
  join user ur on so.user_id=ur.user_id
  join my_referrer mr on ur.user_id=mr.user_id
  join user ur2 on mr.referrer_user_id=ur2.user_id
         where bl.is_active=1
         group by 1,2,3,4,5,6
        having count(1) > 1;


-- 동일카드 사용자
select so.user_id 구독자ID,ur.name 구독자명,ur.phone_no 구독자전화,
       ur2.user_id 추천인ID,ur2.name 추천인명,ur2.phone_no 추천인전화,
       sob.card_company 카드, sob.card_number 카드번호, CONVERT_TZ(so.created_at,'UTC','Asia/Seoul')
from subs_order_billing sob
join (select
--     so.user_id 구독자ID,ur.name 구독자명,
#        ur2.user_id 추천자ID,ur2.name 추천자명,
bl.card_company,
bl.card_number,
count(1)
               from subs_order_billing bl
                        join subs_orders so on bl.subs_orders_id = so.subs_orders_id and so.is_active = 1
                        join user ur on so.user_id = ur.user_id
                        join my_referrer mr on ur.user_id = mr.user_id
                        join user ur2 on mr.referrer_user_id = ur2.user_id
               where bl.is_active = 1
               group by 1, 2
#                 ,3,4
               having count(1) > 1
               ) aa on sob.card_company=aa.card_company and sob.card_number=aa.card_number
join subs_orders so on sob.subs_orders_id=so.subs_orders_id
join user ur on so.user_id=ur.user_id
join my_referrer mr on ur.user_id=mr.user_id
join user ur2 on mr.referrer_user_id=ur2.user_id
order by 카드,카드번호,추천인명
;

select sob.card_company,sob.card_number,ur.name 구독자,ur2.name 추천자
    from subs_order_billing sob
    join subs_orders so on so.subs_orders_id=sob.subs_orders_id and so.is_active=1
    join user ur on so.user_id=ur.user_id
    join my_referrer mr on ur.user_id=mr.user_id
    join user ur2 on mr.referrer_user_id=ur2.user_id
   where card_company='[삼성]' and card_number='7265'
;

select * from subs_order_billing order by created_at desc;

-- 스피드캐쉬 (query_type=all)
WITH new_subs AS (
    SELECT
        YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3)                    AS year_week,
        DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
        DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
        ur2.user_id                                                                   AS referrer_user_id,
        ANY_VALUE(ur2.name)    COLLATE utf8mb4_general_ci                             AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci                            AS referrer_phone,
        SUM(so.speed_cash)                                                            AS new_speed_cash
    FROM subs_order_payment op
    JOIN subs_orders so ON op.subs_orders_id = so.subs_orders_id
    JOIN subs ss         ON so.subs_id = ss.subs_id
    JOIN user ur         ON so.user_id = ur.user_id
    JOIN my_referrer mr  ON so.user_id = mr.user_id
    JOIN user ur2        ON mr.referrer_user_id = ur2.user_id
    WHERE op.is_success = 1
      AND LEFT(op.created_at, 10) = so.subs_start_date
      AND YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3) = :base_yearweek
    GROUP BY 1, 2, 3, 4
),
cancel_subs AS (
    SELECT
        YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3)                    AS year_week,
        DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
        DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
        ur2.user_id                                                                   AS referrer_user_id,
        ANY_VALUE(ur2.name)    COLLATE utf8mb4_general_ci                             AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci                            AS referrer_phone,
                TRUNCATE(
            SUM(
                CASE
                    WHEN YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3)
                       = YEARWEEK(CONVERT_TZ(so.created_at,'UTC','Asia/Seoul'), 3)
                    THEN so.speed_cash
                    ELSE so.speed_cash
                       - so.speed_cash
                       * (SELECT COUNT(1) FROM subs_order_payment sop
                          WHERE sc.subs_orders_id = sop.subs_orders_id AND sop.is_success = 1) / 12
                END
            ), 0
        )                                                                             AS return_speed_cash
    FROM subs_order_cancel sc
    JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id AND so.speed_cash <> 0
    JOIN subs ss         ON so.subs_id = ss.subs_id
    JOIN user ur         ON so.user_id = ur.user_id
    JOIN my_referrer mr  ON so.user_id = mr.user_id
    JOIN user ur2        ON mr.referrer_user_id = ur2.user_id
    WHERE sc.status = 2
      AND YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3) = :base_yearweek
    GROUP BY 1, 2, 3, 4
)

-- new 기준 (cancel 없을 수 있음)
SELECT
    n.year_week,
    n.week_start,
    n.week_end,
    n.referrer_user_id,
    n.referrer_name,
    n.referrer_phone,
    COALESCE(n.new_speed_cash, 0)                                                     AS speed_cash,
    COALESCE(c.return_speed_cash, 0)                                                  AS return_speed_cash,
    COALESCE(n.new_speed_cash, 0) - COALESCE(c.return_speed_cash, 0)                 AS final_speed_cash
FROM new_subs n
LEFT JOIN cancel_subs c
       ON n.year_week = c.year_week
      AND n.referrer_user_id = c.referrer_user_id

UNION ALL

-- cancel 기준 (new 없는 경우만)
SELECT
    c.year_week,
    c.week_start,
    c.week_end,
    c.referrer_user_id,
    c.referrer_name,
    c.referrer_phone,
    0                                                                                 AS speed_cash,
    c.return_speed_cash                                                               AS return_speed_cash,
    0 - c.return_speed_cash                                                           AS final_speed_cash
FROM cancel_subs c
LEFT JOIN new_subs n
       ON c.year_week = n.year_week
      AND c.referrer_user_id = n.referrer_user_id
WHERE n.referrer_user_id IS NULL

ORDER BY year_week DESC, referrer_name
;

select * from subs_order_billing order by created_at;

-- 한카드가 여러명이 사용할수없게
select count(1) from subs_order_billing sob
    join subs_orders so on sob.subs_orders_id=so.subs_orders_id and so.user_id <> 'e81f77af-357d-4cac-8e69-2dffd028b4a4'
         where sob.card_number='9842' and sob.birth='880730'
;


SELECT DATE_FORMAT(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), '%y-%m-%d %H:%i') AS approved_dt,
                       DATE_FORMAT(CONVERT_TZ(sc.created_at,'UTC','Asia/Seoul'), '%y-%m-%d %H:%i') AS request_dt,
                       DATE_FORMAT(CONVERT_TZ(so.created_at,'UTC','Asia/Seoul'), '%y-%m-%d %H:%i') AS subs_dt,
                       CONCAT(ur.name,'(',ur.user_id,')') AS user,
                       ss.name,
                       ss.price,
                       so.speed_cash,
                       (SELECT COUNT(1) FROM subs_order_payment sop WHERE sc.subs_orders_id=sop.subs_orders_id) AS received_count,
                       CONCAT(ur2.name,'(',ur2.user_id,')') AS referrer,
                       sc.subs_orders_id
                  FROM subs_order_cancel sc
                  JOIN subs_orders so ON sc.subs_orders_id=so.subs_orders_id
                  JOIN subs ss ON so.subs_id=ss.subs_id
                  JOIN user ur ON so.user_id=ur.user_id
                  JOIN my_referrer mr ON so.user_id=mr.user_id AND mr.referrer_user_id = :referrer_user_id
                  JOIN user ur2 ON mr.referrer_user_id=ur2.user_id
                 WHERE YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3) = :year_week
                 ORDER BY sc.updated_at DESC;

select * from subs_orders where user_id='2c6dfb16-a8a5-486c-bc67-d7207c9c95ed';
select * from subs_order_payment where subs_orders_id='4d9e4aaa-2c41-40f5-8c52-eac370ba9ddb';
select * from subs_order_cancel where subs_orders_id in (
    'a917f1e1-de74-4fa6-b143-2de83fb3c283' )
;

select * from subs_order_cancel sc join conomy.subs_orders so on sc.subs_orders_id=so.subs_orders_id where sc.status=9;
select * from subs_order_cancel where subs_orders_id='';
select subs_orders_id from subs_order_cancel group by subs_orders_id having count(1) > 1;

select * from user where name='옥영수';
