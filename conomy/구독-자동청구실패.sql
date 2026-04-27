SELECT DATE_FORMAT(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), '%y-%m-%d %H') payment_date,
                   op.failure_reason,
                   SUBSTRING_INDEX(SUBSTRING_INDEX(jl.source, "'subs_orders_id': '", -1), "'", 1) AS subs_orders_id,
                   concat(SUBSTRING_INDEX(SUBSTRING_INDEX(jl.result, "'resultCode': '", -1), "'", 1) , ':',
                   SUBSTRING_INDEX(SUBSTRING_INDEX(jl.result, "'resultMsg': '", -1), "'", 1)) AS result,
                   DATE_FORMAT(so.subs_start_date, '%y-%m-%d') subs_start_date,
                   (select count(1) from subs_order_payment sop where sop.subs_orders_id=so.subs_orders_id and sop.is_success=1 and sop.created_at < jl.created_at) paid_count,
                   CONCAT(ur.name,'(',ur.user_id,')') user,
                   ss.name subs_name,
                   ss.price subs_price,
                   sb.card_company,
                   sb.card_number,
                   op.subs_order_payment_id payment_id
              FROM jobs_log jl
              JOIN subs_order_payment op ON jl.ref_id=op.subs_order_payment_id
              JOIN subs_orders so ON op.subs_orders_id=so.subs_orders_id
              JOIN subs_order_billing sb ON op.subs_order_billing_id=sb.subs_order_billing_id
              JOIN subs ss ON so.subs_id=ss.subs_id
              JOIN user ur ON so.user_id=ur.user_id
             WHERE jl.result LIKE '나이스페이 정기 결제 등록 실패%'
             ORDER BY jl.created_at DESC
#              LIMIT 100
;

WITH base AS (
    SELECT jl.created_at,
           jl.source,
           jl.result,
           op.failure_reason,
           op.subs_order_payment_id,
           op.subs_orders_id,
           op.subs_order_billing_id,
           DATE_FORMAT(CONVERT_TZ(op.created_at, 'UTC', 'Asia/Seoul'), '%y-%m-%d %H') AS payment_date
      FROM jobs_log jl
      JOIN subs_order_payment op ON jl.ref_id = op.subs_order_payment_id
     WHERE jl.result LIKE '나이스페이 정기 결제 등록 실패%'
)
SELECT b.payment_date,
       b.failure_reason,
       SUBSTRING_INDEX(SUBSTRING_INDEX(b.source, "'subs_orders_id': '", -1), "'", 1) AS subs_orders_id,
       CONCAT(
           SUBSTRING_INDEX(SUBSTRING_INDEX(b.result, "'resultCode': '", -1), "'", 1),
           ':',
           SUBSTRING_INDEX(SUBSTRING_INDEX(b.result, "'resultMsg': '", -1), "'", 1)
       ) AS result,
       DATE_FORMAT(so.subs_start_date, '%y-%m-%d') AS subs_start_date,
       so.billing_day,
       (SELECT COUNT(1)
          FROM subs_order_payment sop
         WHERE sop.subs_orders_id = so.subs_orders_id
           AND sop.is_success = 1
           AND sop.created_at < b.created_at) AS paid_count,
       CONCAT(ur.name, '(', ur.user_id, ')') AS user,
       ss.name AS subs_name,
       ss.price AS subs_price,
       sb.card_company,
       sb.card_number,
       b.subs_order_payment_id AS payment_id
  FROM base b
  JOIN subs_orders so        ON b.subs_orders_id = so.subs_orders_id
      and so.subs_orders_id in
      (
          '1808cec0-04bc-4ba1-9875-294e8b1538c1',
'decf9bc7-ec2c-4ad8-ba6d-b7ff7374c247',
'56c873f9-b76f-44d2-8bd8-f98eb77e660c',
'2bf14f55-b2ea-46da-9c11-67457479fd34',
'd4cf600b-88bb-47b4-8a4e-3543baee6e60',
'28d19a4a-17b7-41ce-9659-3be05d020547',
'fcbe438d-0f6f-4f00-a6df-3656d436284e',
'de447b50-521f-4551-b5c0-12722344c0a0',
'686d953a-abc0-42c3-9eea-2323567dc452',
'0132e721-fe57-426e-ab9a-fd402600de80',
'5f4b0a4b-0ce7-408c-bda9-600ab838ffbe'
          )
  JOIN subs_order_billing sb ON b.subs_order_billing_id = sb.subs_order_billing_id
  JOIN subs ss               ON so.subs_id = ss.subs_id
  JOIN user ur               ON so.user_id = ur.user_id
 WHERE b.payment_date = (SELECT MAX(payment_date) FROM base)
 ORDER BY user;

select * from subs_orders so
#          join subs_order_payment sop on so.subs_orders_id=sop.subs_orders_id and sop.created_at>'2026-03-20'
         where so.subs_start_date='2026-03-19' and is_active=1
;

WITH p AS (
              SELECT
                -- KST 기준 오늘
                DATE(CONVERT_TZ(NOW(),'UTC','Asia/Seoul')) AS today_kst,
                DAY(CONVERT_TZ(NOW(),'UTC','Asia/Seoul'))  AS today_day,

                -- 이번달/전달 yymm (KST 기준)
                DATE_FORMAT(CONVERT_TZ(NOW(),'UTC','Asia/Seoul'), '%Y%m') AS yymm_this,
                DATE_FORMAT(DATE_SUB(CONVERT_TZ(NOW(),'UTC','Asia/Seoul'), INTERVAL 1 MONTH), '%Y%m') AS yymm_prev,

                -- 말일
                LAST_DAY(DATE(CONVERT_TZ(NOW(),'UTC','Asia/Seoul'))) AS last_day_kst,

                -- ✅ 이번달 1일 00:00:00 (KST)
                STR_TO_DATE(
                  DATE_FORMAT(CONVERT_TZ(NOW(),'UTC','Asia/Seoul'), '%Y-%m-01 00:00:00'),
                  '%Y-%m-%d %H:%i:%s'
                ) AS this_month_start_kst
            )

            SELECT
              so.subs_orders_id,
              so.user_id,
              so.subs_id,
              so.billing_day,
              so.is_end_of_month,

              ss.name  AS subs_name,
              ss.price AS net_amount,
              ss.vat,
              ss.max_seats,

              u.name   AS user_name,

              sb.billingKey,
              sb.is_active,
              sb.subs_order_billing_id,
              sb.pg_type,

              sb.created_at AS subs_start_date,

              -- ✅ 어떤 월을 청구해야 하는지 (미수면 prev, 아니면 this)
              CASE
                WHEN (
                  -- 전달 성공 결제가 없으면 전달 미수
                  NOT EXISTS (
                    SELECT 1
                    FROM subs_order_payment x
                    WHERE x.subs_orders_id = so.subs_orders_id
                      AND x.billing_yymm   = p.yymm_prev
                      AND x.is_success     = 1
                  )
                )
                THEN p.yymm_prev
                ELSE p.yymm_this
              END AS target_billing_yymm,

              CASE
                WHEN (
                  NOT EXISTS (
                    SELECT 1
                    FROM subs_order_payment x
                    WHERE x.subs_orders_id = so.subs_orders_id
                      AND x.billing_yymm   = p.yymm_prev
                      AND x.is_success     = 1
                  )
                )
                THEN CONCAT('ARREARS_', p.yymm_prev)
                ELSE CONCAT('DUE_', p.yymm_this)
              END AS pick_reason

            FROM subs_orders so
            JOIN subs ss
              ON so.subs_id = ss.subs_id
            JOIN subs_order_billing sb
              ON so.subs_orders_id = sb.subs_orders_id
            JOIN user u
              ON so.user_id = u.user_id
            CROSS JOIN p

            WHERE
              so.is_active = 1
              AND sb.is_active = 1
              AND sb.pg_type <> 10

              -- ✅ 핵심: "익월부터 자동결제" → 이번달 가입자는 배치 대상에서 제외
              AND CONVERT_TZ(sb.created_at,'UTC','Asia/Seoul') < p.this_month_start_kst

              AND (
                -- ✅ 1) 전달 미수는 무조건 대상 (단, 위 조건으로 이번달 가입자는 이미 제외됨)
                NOT EXISTS (
                  SELECT 1
                  FROM subs_order_payment x
                  WHERE x.subs_orders_id = so.subs_orders_id
                    AND x.billing_yymm   = p.yymm_prev
                    AND x.is_success     = 1
                )

                OR

                -- ✅ 2) 이번달 도래분 대상: 이번달 성공 없음 + billing_day 규칙
                (
                  NOT EXISTS (
                    SELECT 1
                    FROM subs_order_payment y
                    WHERE y.subs_orders_id = so.subs_orders_id
                      AND y.billing_yymm   = p.yymm_this
                      AND y.is_success     = 1
                  )
                  AND (
                    (p.today_kst = p.last_day_kst AND so.billing_day <= 31)
                    OR (p.today_kst <> p.last_day_kst
                        AND so.is_end_of_month = 0
                        AND so.billing_day <= p.today_day)
                  )
                )
              )

            ORDER BY
              -- 미수 먼저
              (CASE
                 WHEN NOT EXISTS (
                   SELECT 1
                   FROM subs_order_payment x
                   WHERE x.subs_orders_id = so.subs_orders_id
                     AND x.billing_yymm   = p.yymm_prev
                     AND x.is_success     = 1
                 ) THEN 0 ELSE 1
               END),
              sb.created_at
;

