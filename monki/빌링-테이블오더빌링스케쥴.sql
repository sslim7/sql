WITH contract_base AS (
    SELECT
        c.cont_id,
        c.store_no,
        (c.contract_data->>'ops_qty')::int                AS ops_qty,
        (c.contract_data->>'subs_price')::bigint          AS subs_price,
        (c.contract_data->>'bill_day')::int               AS bill_day,
        (c.contract_data->>'contract_count')::int         AS contract_count,
        date_trunc('month', (c.contract_data->>'start_bill_date')::date)::date AS start_month
    FROM billing.contracts c
    WHERE c.store_no = :store_no
      AND c.sell_type = 'tableorder'
      AND (c.contract_data->>'subs_price')::bigint    > 0
      AND (c.contract_data->>'contract_count')::bigint > 0
),
schedule AS (
    SELECT
        cb.cont_id,
        cb.store_no,
        cb.ops_qty,
        cb.subs_price,
        cb.bill_day,
        (cb.start_month + (gs.n || ' month')::interval)::date AS bill_month_date
    FROM contract_base cb
    CROSS JOIN LATERAL generate_series(0, cb.contract_count - 1) AS gs(n)
),
billed AS (
    SELECT
        iv.cont_id,
        bl.bill_yymm,
        bl.status,
        lp.payment_date
    FROM billing.billing bl
    JOIN billing.invoice iv
      ON iv.bill_id   = bl.bill_id
     AND iv.sell_type = 'tableorder'
    LEFT JOIN LATERAL (
        SELECT pm.payment_date
        FROM billing.payment_detail pd
        JOIN billing.payments pm
          ON pm.payment_id = pd.payment_id
        WHERE pd.invoice_id = iv.invoice_id
        ORDER BY pd.created_at DESC
        LIMIT 1
    ) lp ON true
    WHERE bl.store_no = :store_no
      AND bl.status NOT IN ('draft','issued')
)
SELECT
    to_char(s.bill_month_date, 'YYYY-MM')                                        AS 청구년월,
    s.ops_qty                                                                    AS 보급수량,
    s.subs_price + (s.subs_price * 0.1)                                          AS 청구금액,
    to_char(s.bill_month_date, 'YYYY.MM') || '.' || lpad(s.bill_day::text, 2,'0') AS 청구예정일자,
    CASE
        WHEN b.payment_date IS NOT NULL
        THEN to_char(b.payment_date AT TIME ZONE 'Asia/Seoul', 'YYYY.MM.DD')
        ELSE ''
    END                                                                          AS 결제일자,
    CASE b.status
        WHEN 'processing' THEN '출금진행중'
        WHEN 'paid'       THEN '결제완료'
        WHEN 'failed'     THEN '미납'
        WHEN 'cancelled'  THEN '결제취소'
        ELSE '청구예정'
    END                                                                          AS 결제상태
FROM schedule s
LEFT JOIN billed b
       ON b.cont_id   = s.cont_id
      AND b.bill_yymm = to_char(s.bill_month_date, 'YYYY-MM')
ORDER BY s.bill_month_date, s.bill_day, s.cont_id;