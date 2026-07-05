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
                 then so.speed_cash else COALESCE(JSON_EXTRACT(ss.speed_cashes, CONCAT('$."', op.chasu, '"')) + 0, 0  ) end
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
        YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3) AS year_week,
        DATE_FORMAT(
            DATE_SUB(
                DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')),
                INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY
            ),
            '%y-%m-%d'
        ) AS week_start,
        DATE_FORMAT(
            DATE_ADD(
                DATE_SUB(
                    DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')),
                    INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY
                ),
                INTERVAL 6 DAY
            ),
            '%y-%m-%d'
        ) AS week_end,
        ur2.user_id AS referrer_user_id,
        ANY_VALUE(ur2.name) COLLATE utf8mb4_general_ci AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci AS referrer_phone,

        TRUNCATE(
            SUM(
                CASE
                    -- ✅ 5/1 이후: speed_cashes JSON 기준
                    WHEN so.subs_start_date >= '2026-05-01' THEN
                        CASE
                            -- 1개월 이내: 지급된 스피드캐시 전액 환수
                            WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH THEN (
                                SELECT COALESCE(
                                    SUM(
                                        JSON_EXTRACT(
                                            ss.speed_cashes,
                                            CONCAT('$."', jt.speed_chasu, '"')
                                        ) + 0
                                    ),
                                    0
                                )
                                FROM JSON_TABLE(
                                    JSON_KEYS(ss.speed_cashes),
                                    '$[*]' COLUMNS (
                                        speed_chasu INT PATH '$'
                                    )
                                ) jt
                                WHERE jt.speed_chasu <= (
                                    SELECT MAX(sop.chasu)
                                    FROM subs_order_payment sop
                                    WHERE sop.subs_orders_id = sc.subs_orders_id
                                      AND sop.is_success = 1
                                )
                            )

                            -- 1개월 이후: 차수별 남은 기간 비례 환수
                            ELSE (
                                SELECT COALESCE(
                                    TRUNCATE(
                                        SUM(
                                            (
                                                JSON_EXTRACT(
                                                    ss.speed_cashes,
                                                    CONCAT('$."', jt.speed_chasu, '"')
                                                ) + 0
                                            )
                                            *
                                            (
                                                12 - (
                                                    SELECT MAX(sop.chasu)
                                                    FROM subs_order_payment sop
                                                    WHERE sop.subs_orders_id = sc.subs_orders_id
                                                      AND sop.is_success = 1
                                                )
                                            )
                                            /
                                            (12 - jt.speed_chasu + 1)
                                        ),
                                        0
                                    ),
                                    0
                                )
                                FROM JSON_TABLE(
                                    JSON_KEYS(ss.speed_cashes),
                                    '$[*]' COLUMNS (
                                        speed_chasu INT PATH '$'
                                    )
                                ) jt
                                WHERE jt.speed_chasu <= (
                                    SELECT MAX(sop.chasu)
                                    FROM subs_order_payment sop
                                    WHERE sop.subs_orders_id = sc.subs_orders_id
                                      AND sop.is_success = 1
                                )
                            )
                        END

                    -- ✅ 5/1 이전: 기존 그대로
                    ELSE
                        CASE
                            WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH
                            THEN so.speed_cash
                            ELSE
                                so.speed_cash
                                - so.speed_cash
                                  * (
                                      SELECT COUNT(1)
                                      FROM subs_order_payment sop
                                      WHERE sop.subs_orders_id = sc.subs_orders_id
                                        AND sop.is_success = 1
                                  ) / 12
                        END
                END
            ),
            0
        ) AS return_speed_cash
    FROM subs_order_cancel sc
    JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id AND so.speed_cash <> 0
    JOIN subs ss ON so.subs_id = ss.subs_id
    JOIN user ur ON so.user_id = ur.user_id
    JOIN my_referrer mr ON so.user_id = mr.user_id
    JOIN user ur2 ON mr.referrer_user_id = ur2.user_id
    WHERE sc.status = 2 AND YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3) = :base_yearweek
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
                       case when so.subs_start_date > '2026-05-01'
                           then COALESCE(JSON_EXTRACT(ss.speed_cashes, CONCAT('$."', op.chasu, '"')) + 0, 0  )
    else so.speed_cash end speed_cash,

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
                 ORDER BY op.created_at DESC;
ALTER TABLE subs

RENAME COLUMN speed_cashs TO speed_cashes;
select * from subs where speed_cash <> 0;
alter table subs add column speed_cashs json comment "차수별 스피드캐시 지급액";
INSERT INTO conomy.subs (subs_id, name, description, category, price, speed_cash, plan, max_seats, is_active, vat, sub_cate_id)
VALUES (uuid(), '비즈니스 (세레니움)', '3박스 (80통) / 월', '1010', 99000, 300000, 3, 3, 1, 0, '9ee1c839-bd49-11f0-b509-42010a40000b');

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
SELECT
    ttt.*,
    CASE
        -- 5/1 이전: 기존 그대로
        WHEN ttt.subs_start_date < '2026-05-01'
        THEN ttt.speed_cash
        -- 5/1 이후: 실제 지급된 speed_cashes 합계
        ELSE (
            SELECT COALESCE(SUM(
                JSON_EXTRACT(ttt.speed_cashes, CONCAT('$."', jt.speed_chasu, '"')) + 0
            ), 0)
            FROM JSON_TABLE(
                JSON_KEYS(ttt.speed_cashes),
                '$[*]' COLUMNS (
                    speed_chasu INT PATH '$'
                )
            ) jt
            WHERE jt.speed_chasu <= ttt.chasu
        )
    END AS paid_cash,
    CASE
        -- 5/1 이전: 기존 환불 계산
        WHEN ttt.subs_start_date < '2026-05-01'
        THEN
            CASE
                WHEN ttt.cancel_dt_utc < ttt.subs_created_at_utc + INTERVAL 1 MONTH
                THEN ttt.speed_cash
                ELSE ttt.speed_cash - ttt.speed_cash * ttt.chasu / 12
            END
        -- 5/1 이후: 차수별 잔여기간 비례 환수
        ELSE
            CASE
                -- 1개월 이내 취소: 지급된 금액 전액 환수
                WHEN ttt.cancel_dt_utc < ttt.subs_created_at_utc + INTERVAL 1 MONTH
                THEN (
                    SELECT COALESCE(SUM(
                        JSON_EXTRACT(ttt.speed_cashes, CONCAT('$."', jt.speed_chasu, '"')) + 0
                    ), 0)
                    FROM JSON_TABLE(
                        JSON_KEYS(ttt.speed_cashes),
                        '$[*]' COLUMNS (
                            speed_chasu INT PATH '$'
                        )
                    ) jt
                    WHERE jt.speed_chasu <= ttt.chasu
                )
                -- 1개월 이후: 지급차수별 환수 계산
                ELSE (
                    SELECT COALESCE(TRUNCATE(SUM(
                        (JSON_EXTRACT(ttt.speed_cashes, CONCAT('$."', jt.speed_chasu, '"')) + 0)
                        * (12 - ttt.chasu)
                        / (12 - jt.speed_chasu + 1)
                    ), 0), 0)
                    FROM JSON_TABLE(
                        JSON_KEYS(ttt.speed_cashes),
                        '$[*]' COLUMNS (
                            speed_chasu INT PATH '$'
                        )
                    ) jt
                    WHERE jt.speed_chasu <= ttt.chasu
                )
            END
    END AS return_speed_cash
FROM (
    SELECT
        DATE_FORMAT(CONVERT_TZ(sc.updated_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS approved_dt,
        DATE_FORMAT(CONVERT_TZ(sc.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS request_dt,
        DATE_FORMAT(CONVERT_TZ(so.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS subs_dt,
        sc.updated_at AS cancel_dt_utc,
        so.created_at AS subs_created_at_utc,
        CONCAT(ur.name, '(', ur.user_id, ')') AS user,
        ss.name,
        ss.price,
        so.speed_cash,
        ss.speed_cashes,
        (
            SELECT sop.chasu
            FROM subs_order_payment sop
            WHERE sc.subs_orders_id = sop.subs_orders_id
              AND sop.is_success = 1
            ORDER BY sop.created_at DESC
            LIMIT 1
        ) AS chasu,
        CONCAT(ur2.name, '(', ur2.user_id, ')') AS referrer,
        sc.subs_orders_id,
        so.subs_start_date
    FROM subs_order_cancel sc
    JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id
    JOIN subs ss ON so.subs_id = ss.subs_id
    JOIN user ur ON so.user_id = ur.user_id
    JOIN my_referrer mr ON so.user_id = mr.user_id AND mr.referrer_user_id = :referrer_user_id
    JOIN user ur2 ON mr.referrer_user_id = ur2.user_id
    WHERE YEARWEEK(CONVERT_TZ(sc.updated_at, 'UTC', 'Asia/Seoul'), 3) = :year_week
    ORDER BY sc.updated_at DESC
) ttt;
select * from subs;
select * from user where user_id='ddaa1fda-a6b8-44fa-80fb-42583882c651';
select * from subs_order_payment where is_success=1 and chasu=0;


select du.name,du.phone_no,sos.receiver_name,sos.address,sos.address_detail,du.created_at
from withdrawn_users du join subs_orders so on du.user_id=so.user_id
    join subs_order_shipping sos on so.subs_orders_id=sos.subs_order_id
 order by du.created_at desc;#where status=2;
select * from user_status_changes;
select * from user where user_id='f963a94c-b03f-4c31-97bb-94d94d6ad17b';
select * from user where name='장성태';
select * from subs_orders where user_id='6b703a90-b9b9-4e19-88dc-32c64b2aac95';
select * from subs_orders so
         join subs_order_billing sob on so.subs_orders_id=sob.subs_orders_id
         left join subs_order_payment sop on sob.subs_order_billing_id=sop.subs_order_billing_id
         where so.subs_orders_id in ('5993e3d5-d55f-4d38-918c-68f58d256f77',
'7295334e-5e13-48e3-acb7-1d5feffb86ee');
select * from subs_order_billing where subs_orders_id='510c0f58-f131-43f4-a766-d66a82c59e6c';
select * from subs_order_billing
         where card_number='3010';
select * from subs_order_payment where subs_orders_id='7295334e-5e13-48e3-acb7-1d5feffb86ee';
-- 박영숙 2026-05-07 23:33:23.111300
select * from user where user_id in ('1fd64c53-b379-487c-abe1-82ede1694de0',
'6b703a90-b9b9-4e19-88dc-32c64b2aac95');
1fd64c53-b379-487c-abe1-82ede1694de0,박영숙,01085582818
6b703a90-b9b9-4e19-88dc-32c64b2aac95,장성태 ,01040629779
;

# 현제시점 추천인별 스피드캐시
WITH new_subs AS (
    SELECT
        ur2.user_id AS referrer_user_id,
        ANY_VALUE(ur2.name) COLLATE utf8mb4_general_ci AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci AS referrer_phone,
        SUM(
            CASE
                WHEN so.subs_start_date < '2026-05-01'
                THEN so.speed_cash
                ELSE COALESCE(
                    JSON_EXTRACT(ss.speed_cashes, CONCAT('$."', op.chasu, '"')) + 0,
                    0
                )
            END
        ) AS new_speed_cash
    FROM subs_order_payment op
    JOIN subs_orders so ON op.subs_orders_id = so.subs_orders_id
    JOIN subs ss ON so.subs_id = ss.subs_id
    JOIN user ur ON so.user_id = ur.user_id
    JOIN my_referrer mr ON so.user_id = mr.user_id
    JOIN user ur2 ON mr.referrer_user_id = ur2.user_id
    WHERE op.is_success = 1
      AND (
            (so.subs_start_date >= '2026-05-01' AND op.chasu IN (1,2,3,4,5,6,7,8,9,10,11,12))
         OR (so.subs_start_date <  '2026-05-01' AND op.chasu IN (1))
      )
    GROUP BY ur2.user_id
),
cancel_subs AS (
    SELECT
        ur2.user_id AS referrer_user_id,
        ANY_VALUE(ur2.name) COLLATE utf8mb4_general_ci AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci AS referrer_phone,

        TRUNCATE(
            SUM(
                CASE
                    WHEN so.subs_start_date >= '2026-05-01' THEN
                        CASE
                            WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH THEN (
                                SELECT COALESCE(
                                    SUM(
                                        JSON_EXTRACT(
                                            ss.speed_cashes,
                                            CONCAT('$."', jt.speed_chasu, '"')
                                        ) + 0
                                    ),
                                    0
                                )
                                FROM JSON_TABLE(
                                    JSON_KEYS(ss.speed_cashes),
                                    '$[*]' COLUMNS (
                                        speed_chasu INT PATH '$'
                                    )
                                ) jt
                                WHERE jt.speed_chasu <= (
                                    SELECT MAX(sop.chasu)
                                    FROM subs_order_payment sop
                                    WHERE sop.subs_orders_id = sc.subs_orders_id
                                      AND sop.is_success = 1
                                )
                            )

                            ELSE (
                                SELECT COALESCE(
                                    TRUNCATE(
                                        SUM(
                                            (
                                                JSON_EXTRACT(
                                                    ss.speed_cashes,
                                                    CONCAT('$."', jt.speed_chasu, '"')
                                                ) + 0
                                            )
                                            *
                                            (
                                                12 - (
                                                    SELECT MAX(sop.chasu)
                                                    FROM subs_order_payment sop
                                                    WHERE sop.subs_orders_id = sc.subs_orders_id
                                                      AND sop.is_success = 1
                                                )
                                            )
                                            /
                                            (12 - jt.speed_chasu + 1)
                                        ),
                                        0
                                    ),
                                    0
                                )
                                FROM JSON_TABLE(
                                    JSON_KEYS(ss.speed_cashes),
                                    '$[*]' COLUMNS (
                                        speed_chasu INT PATH '$'
                                    )
                                ) jt
                                WHERE jt.speed_chasu <= (
                                    SELECT MAX(sop.chasu)
                                    FROM subs_order_payment sop
                                    WHERE sop.subs_orders_id = sc.subs_orders_id
                                      AND sop.is_success = 1
                                )
                            )
                        END

                    ELSE
                        CASE
                            WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH
                            THEN so.speed_cash
                            ELSE
                                so.speed_cash
                                - so.speed_cash
                                  * (
                                      SELECT COUNT(1)
                                      FROM subs_order_payment sop
                                      WHERE sop.subs_orders_id = sc.subs_orders_id
                                        AND sop.is_success = 1
                                  ) / 12
                        END
                END
            ),
            0
        ) AS return_speed_cash

    FROM subs_order_cancel sc
    JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id AND so.speed_cash <> 0
    JOIN subs ss ON so.subs_id = ss.subs_id
    JOIN user ur ON so.user_id = ur.user_id
    JOIN my_referrer mr ON so.user_id = mr.user_id
    JOIN user ur2 ON mr.referrer_user_id = ur2.user_id
    WHERE sc.status = 2
    GROUP BY ur2.user_id
)
SELECT
    n.referrer_user_id,
    CONCAT(
        COALESCE(
            DATE_FORMAT(
                (
                    SELECT CONVERT_TZ(so2.created_at, 'UTC', 'Asia/Seoul')
                    FROM subs_orders so2
                    WHERE so2.user_id = n.referrer_user_id
                      AND so2.is_active = 1
                    ORDER BY so2.created_at
                    LIMIT 1
                ),
                '%m/%d '
            ),
            ''
        ),
        n.referrer_name
    ) AS referrer_name,
    n.referrer_phone,
    COALESCE(n.new_speed_cash, 0) AS speed_cash,
    COALESCE(c.return_speed_cash, 0) AS return_speed_cash,
    COALESCE(n.new_speed_cash, 0) - COALESCE(c.return_speed_cash, 0) AS final_speed_cash,
    si.birth_date,
    si.rrn_back,
    si.bank_code,
    b.name AS bank_name,
    si.account_number,
    si.account_holder
FROM new_subs n
LEFT JOIN cancel_subs c
       ON n.referrer_user_id = c.referrer_user_id
LEFT JOIN seller_info si ON si.user_id = n.referrer_user_id
LEFT JOIN bank b ON b.bank_code = si.bank_code

UNION ALL

SELECT
    c.referrer_user_id,
    CONCAT(
        COALESCE(
            DATE_FORMAT(
                (
                    SELECT CONVERT_TZ(so2.created_at, 'UTC', 'Asia/Seoul')
                    FROM subs_orders so2
                    WHERE so2.user_id = c.referrer_user_id
                      AND so2.is_active = 1
                    ORDER BY so2.created_at
                    LIMIT 1
                ),
                '%m/%d '
            ),
            ''
        ),
        c.referrer_name
    ) AS referrer_name,
    c.referrer_phone,
    0 AS speed_cash,
    c.return_speed_cash AS return_speed_cash,
    0 - c.return_speed_cash AS final_speed_cash,
    si.birth_date,
    si.rrn_back,
    si.bank_code,
    b.name AS bank_name,
    si.account_number,
    si.account_holder
FROM cancel_subs c
LEFT JOIN new_subs n
       ON c.referrer_user_id = n.referrer_user_id
LEFT JOIN seller_info si ON si.user_id = c.referrer_user_id
LEFT JOIN bank b ON b.bank_code = si.bank_code
WHERE n.referrer_user_id IS NULL

ORDER BY referrer_name;


SELECT
    ttt.*,

    CASE
        WHEN ttt.subs_start_date < '2026-05-01'
        THEN ttt.speed_cash
        ELSE (
            SELECT COALESCE(SUM(
                JSON_EXTRACT(ttt.speed_cashes, CONCAT('$."', jt.speed_chasu, '"')) + 0
            ), 0)
            FROM JSON_TABLE(
                JSON_KEYS(ttt.speed_cashes),
                '$[*]' COLUMNS (
                    speed_chasu INT PATH '$'
                )
            ) jt
            WHERE jt.speed_chasu <= ttt.chasu
        )
    END AS paid_cash,

    CASE
        WHEN ttt.subs_start_date < '2026-05-01'
        THEN
            CASE
                WHEN ttt.cancel_dt_utc < ttt.subs_created_at_utc + INTERVAL 1 MONTH
                THEN ttt.speed_cash
                ELSE ttt.speed_cash - ttt.speed_cash * ttt.chasu / 12
            END
        ELSE
            CASE
                WHEN ttt.cancel_dt_utc < ttt.subs_created_at_utc + INTERVAL 1 MONTH
                THEN (
                    SELECT COALESCE(SUM(
                        JSON_EXTRACT(ttt.speed_cashes, CONCAT('$."', jt.speed_chasu, '"')) + 0
                    ), 0)
                    FROM JSON_TABLE(
                        JSON_KEYS(ttt.speed_cashes),
                        '$[*]' COLUMNS (
                            speed_chasu INT PATH '$'
                        )
                    ) jt
                    WHERE jt.speed_chasu <= ttt.chasu
                )
                ELSE (
                    SELECT COALESCE(TRUNCATE(SUM(
                        (JSON_EXTRACT(ttt.speed_cashes, CONCAT('$."', jt.speed_chasu, '"')) + 0)
                        * (12 - ttt.chasu)
                        / (12 - jt.speed_chasu + 1)
                    ), 0), 0)
                    FROM JSON_TABLE(
                        JSON_KEYS(ttt.speed_cashes),
                        '$[*]' COLUMNS (
                            speed_chasu INT PATH '$'
                        )
                    ) jt
                    WHERE jt.speed_chasu <= ttt.chasu
                )
            END
    END AS return_speed_cash

FROM (
    SELECT
        DATE_FORMAT(CONVERT_TZ(sc.updated_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS approved_dt,
        DATE_FORMAT(CONVERT_TZ(sc.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS request_dt,
        DATE_FORMAT(CONVERT_TZ(so.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H:%i') AS subs_dt,

        sc.updated_at AS cancel_dt_utc,
        so.created_at AS subs_created_at_utc,

        CONCAT(ur.name, '(', ur.user_id, ')') AS user,
        ss.name,
        ss.price,
        so.speed_cash,
        ss.speed_cashes,

        (
            SELECT sop.chasu
            FROM subs_order_payment sop
            WHERE sc.subs_orders_id = sop.subs_orders_id
              AND sop.is_success = 1
            ORDER BY sop.created_at DESC
            LIMIT 1
        ) AS chasu,

        CONCAT(ur2.name, '(', ur2.user_id, ')') AS referrer,
        ur2.user_id AS referrer_user_id,
        sc.subs_orders_id,
        so.subs_start_date

    FROM subs_order_cancel sc
    JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id
    JOIN subs ss ON so.subs_id = ss.subs_id
    JOIN user ur ON so.user_id = ur.user_id
    JOIN my_referrer mr ON so.user_id = mr.user_id
    JOIN user ur2 ON mr.referrer_user_id = ur2.user_id
    WHERE sc.status = 2
    ORDER BY sc.updated_at DESC
) ttt;
select * from user where name='안재선';

select * from orders where user_id='32f2f945-fe52-4784-be64-524f433eb39c';
select * from order_items where order_id='4ef6e6a4-93c6-48ca-8e15-d9af14988eb5';

select *,CONVERT_TZ(sop.created_at, '+00:00', '+09:00') AS created_kst from subs_order_billing sob
         join subs_orders so on so.subs_orders_id=sob.subs_orders_id
         join subs_order_payment sop on sob.subs_order_billing_id=sop.subs_order_billing_id
         join user ur on so.user_id=ur.user_id
         where card_number=3028;

select sob.card_number from subs_orders so
    join subs_order_billing sob on so.subs_orders_id=sob.subs_orders_id
         join subs_order_payment sop on so.subs_orders_id=sop.subs_orders_id
         where user_id='1a6d129a-8063-416b-bc49-154190688f15'