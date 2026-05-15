-- 차수 업데이트
UPDATE
#     select sop.subs_orders_id,sop.billing_yymm,t.rn from
        subs_order_payment sop
JOIN (
    SELECT subs_order_payment_id,
           ROW_NUMBER() OVER (
               PARTITION BY subs_orders_id
               ORDER BY created_at
           ) AS rn
    FROM subs_order_payment
    WHERE is_success = 1
) t ON sop.subs_order_payment_id = t.subs_order_payment_id
SET sop.chasu = t.rn
WHERE sop.is_success = 0;


-- speed_cash list 'all'
WITH new_subs AS (
                    SELECT
                        YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3)                    AS year_week,
                        DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
                        DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
                        ur2.user_id                                                                   AS referrer_user_id,
                        ANY_VALUE(ur2.name)    COLLATE utf8mb4_general_ci                             AS referrer_name,
                        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci                            AS referrer_phone,
                        SUM(case when so.subs_start_date < '2026-05-01'
                                 then so.speed_cash else truncate(so.speed_cash / 3,0) end
                        ) AS new_speed_cash
                    FROM subs_order_payment op
                    JOIN subs_orders so ON op.subs_orders_id = so.subs_orders_id
                    JOIN subs ss         ON so.subs_id = ss.subs_id
                    JOIN user ur         ON so.user_id = ur.user_id
                    JOIN my_referrer mr  ON so.user_id = mr.user_id
                    JOIN user ur2        ON mr.referrer_user_id = ur2.user_id
                    WHERE op.is_success = 1
                      AND YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3) = :base_yearweek
                      AND ((so.subs_start_date >= '2026-05-01' and op.chasu in (1,2,3)) OR
                          ((so.subs_start_date < '2026-05-01') and op.chasu in (1)))
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
                                        -- ✅ 5/1 이후
                                        WHEN so.subs_start_date >= '2026-05-01' THEN
                                            CASE
                                                -- 1개월 이내: 실제 지급액 전액 환불
                                                WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH
                                                THEN TRUNCATE(so.speed_cash / 3, 0)
                                                   * (SELECT COUNT(1) FROM subs_order_payment sop
                                                      WHERE sop.subs_orders_id = sc.subs_orders_id
                                                        AND sop.is_success = 1)
                                                -- 1개월 이후: 실제 지급액에서 paid_count/12 빼고 환불
                                                ELSE
                                                    TRUNCATE(so.speed_cash / 3, 0)
                                                    * (SELECT COUNT(1) FROM subs_order_payment sop
                                                       WHERE sop.subs_orders_id = sc.subs_orders_id
                                                         AND sop.is_success = 1)
                                                    * (12 - (SELECT COUNT(1) FROM subs_order_payment sop
                                                             WHERE sop.subs_orders_id = sc.subs_orders_id
                                                               AND sop.is_success = 1))
                                                    / 12
                                            END

                                        -- ✅ 5/1 이전: 기존 그대로
                                        ELSE
                                            CASE
                                                WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH
                                                THEN so.speed_cash
                                                ELSE so.speed_cash
                                                   - so.speed_cash
                                                   * (SELECT COUNT(1) FROM subs_order_payment sop
                                                      WHERE sop.subs_orders_id = sc.subs_orders_id
                                                        AND sop.is_success = 1) / 12
                                            END
                                    END
                                ), 0
                            ) AS return_speed_cash
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
                SELECT
                    n.year_week,
                    n.week_start,
                    n.week_end,
                    n.referrer_user_id,
                    CONCAT(
                        COALESCE(
                            DATE_FORMAT(
                                (SELECT CONVERT_TZ(so2.created_at, 'UTC', 'Asia/Seoul')
                                 FROM subs_orders so2
                                 WHERE so2.user_id = n.referrer_user_id
                                   AND so2.is_active = 1
                                 ORDER BY so2.created_at
                                 LIMIT 1),
                                '%m/%d '
                            ),
                            ''
                        ),
                        n.referrer_name
                    )                                                                                 AS referrer_name,
                    n.referrer_phone,
                    COALESCE(n.new_speed_cash, 0)                                                     AS speed_cash,
                    COALESCE(c.return_speed_cash, 0)                                                  AS return_speed_cash,
                    COALESCE(n.new_speed_cash, 0) - COALESCE(c.return_speed_cash, 0)                 AS final_speed_cash,
                    si.birth_date,
                    si.rrn_back,
                    si.bank_code,
                    b.name                                                                            AS bank_name,
                    si.account_number,
                    si.account_holder
                FROM new_subs n
                LEFT JOIN cancel_subs c
                       ON n.year_week = c.year_week
                      AND n.referrer_user_id = c.referrer_user_id
                LEFT JOIN seller_info si ON si.user_id = n.referrer_user_id
                LEFT JOIN bank b          ON b.bank_code = si.bank_code

                UNION ALL

                SELECT
                    c.year_week,
                    c.week_start,
                    c.week_end,
                    c.referrer_user_id,
                    CONCAT(
                        COALESCE(
                            DATE_FORMAT(
                                (SELECT CONVERT_TZ(so2.created_at, 'UTC', 'Asia/Seoul')
                                 FROM subs_orders so2
                                 WHERE so2.user_id = c.referrer_user_id
                                   AND so2.is_active = 1
                                 ORDER BY so2.created_at
                                 LIMIT 1),
                                '%m/%d '
                            ),
                            ''
                        ),
                        c.referrer_name
                    )                                                                                 AS referrer_name,
                    c.referrer_phone,
                    0                                                                                 AS speed_cash,
                    c.return_speed_cash                                                               AS return_speed_cash,
                    0 - c.return_speed_cash                                                           AS final_speed_cash,
                    si.birth_date,
                    si.rrn_back,
                    si.bank_code,
                    b.name                                                                            AS bank_name,
                    si.account_number,
                    si.account_holder
                FROM cancel_subs c
                LEFT JOIN new_subs n
                       ON c.year_week = n.year_week
                      AND c.referrer_user_id = n.referrer_user_id
                LEFT JOIN seller_info si ON si.user_id = c.referrer_user_id
                LEFT JOIN bank b          ON b.bank_code = si.bank_code
                WHERE n.referrer_user_id IS NULL

                ORDER BY year_week DESC, referrer_name
;

# Speed_Cash 상세 - New
SELECT DATE_FORMAT(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), '%y-%m-%d %H:%i') AS payment_time,
                       CONCAT(ur.name,'(',ur.user_id,')') AS user,
                       ss.name,
                       ss.price,
                       case when so.created_at > '2026-05-01' then truncate(so.speed_cash / 3,0) else so.speed_cash end speed_cash,
                       CONCAT(ur2.name,'(',ur2.user_id,')') AS referrer,
                       op.subs_order_payment_id, op.chasu
                  FROM subs_order_payment op
                  JOIN subs_orders so ON op.subs_orders_id=so.subs_orders_id
                  JOIN subs ss ON so.subs_id=ss.subs_id
                  JOIN user ur ON so.user_id=ur.user_id
                  JOIN my_referrer mr ON so.user_id=mr.user_id AND mr.referrer_user_id = :referrer_user_id
                  JOIN user ur2 ON mr.referrer_user_id=ur2.user_id
                 WHERE YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3) = :year_week
                   and op.is_success=1
                   and ((so.subs_start_date >= '2026-05-01' and op.chasu in (1,2,3)) OR
                        ((so.subs_start_date < '2026-05-01') and op.chasu in (1)))
                 ORDER BY op.created_at DESC
;

# Speed_Cash 상세 - cancel
select *,
       case when ttt.subs_start_date < '2026-05-01' then ttt.speed_cash else truncate(ttt.speed_cash / 3 * ttt.chasu,0) end paid_cash
  from
     (SELECT DATE_FORMAT(CONVERT_TZ(sc.updated_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS approved_dt,
              DATE_FORMAT(CONVERT_TZ(sc.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS request_dt,
              DATE_FORMAT(CONVERT_TZ(so.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS subs_dt,
              CONCAT(ur.name, '(', ur.user_id, ')')                                         AS user,
              ss.name,
              ss.price,
              so.speed_cash,
              (SELECT sop.chasu
               FROM subs_order_payment sop
               WHERE sc.subs_orders_id = sop.subs_orders_id
                 and sop.is_success = 1
               order by sop.created_at desc
               limit 1)                                                                     AS chasu,
              CONCAT(ur2.name, '(', ur2.user_id, ')')                                       AS referrer,
              sc.subs_orders_id,
              so.subs_start_date
       FROM subs_order_cancel sc
                JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id
                JOIN subs ss ON so.subs_id = ss.subs_id
                JOIN user ur ON so.user_id = ur.user_id
                JOIN my_referrer mr ON so.user_id = mr.user_id AND mr.referrer_user_id = :referrer_user_id
                JOIN user ur2 ON mr.referrer_user_id = ur2.user_id
       WHERE YEARWEEK(CONVERT_TZ(sc.updated_at, 'UTC', 'Asia/Seoul'), 3) = :year_week
       ORDER BY sc.updated_at DESC) ttt
;

select * from subs;
select * from user where user_id='ddaa1fda-a6b8-44fa-80fb-42583882c651';
select * from subs_order_payment where is_success=1 and chasu=0;


select du.name,du.phone_no,sos.receiver_name,sos.address,sos.address_detail,du.created_at
from withdrawn_users du join subs_orders so on du.user_id=so.user_id
    join subs_order_shipping sos on so.subs_orders_id=sos.subs_order_id
 order by du.created_at desc;#where status=2;
select * from user_status_changes;
select * from user where user_id='f963a94c-b03f-4c31-97bb-94d94d6ad17b';