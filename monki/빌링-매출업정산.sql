
-- 정산현황
WITH per_store AS (
    SELECT sc.agency_id, cd.code_desc as agency_name, ct.store_no, bl.bill_yymm,
           bool_or(sc.is_deduction) AS is_deduction,
           max(sc.commission_type)  AS commission_type,
           max(sc.commission)       AS commission,
           sum((iv.invoice_data->>'supply_amount')::bigint) AS supply_amount  -- 먼키 income
    FROM billing.payments pm
    JOIN billing.payment_detail pd ON pm.payment_id = pd.payment_id
    JOIN billing.billing bl        ON pd.bill_id = bl.bill_id
    JOIN billing.invoice iv        ON pd.invoice_id = iv.invoice_id
    JOIN billing.contracts ct      ON iv.cont_id = ct.cont_id
    JOIN billing.settle_contracts sc ON iv.cont_id = sc.cont_id
    JOIN public.tb_code cd ON sc.agency_id = cd.code_id AND cd.code_group = 'AGENCY'
    WHERE pm.payment_date >= to_date(:yyyy_mm, 'YYYY-MM')
      AND pm.payment_date <  to_date(:yyyy_mm, 'YYYY-MM') + interval '1 month'
      AND ct.sell_type = 'sellup'
    GROUP BY sc.agency_id, cd.code_desc, ct.store_no, bl.bill_yymm
),
per_store_income AS (
    SELECT ps.*,
           CASE WHEN ps.commission_type = '정액'
                THEN ps.commission                              -- 정산년월당 정액 1회
                ELSE ps.supply_amount * (ps.commission / 100.0) -- 정률: supply × %
           END AS agency_income
    FROM per_store ps
),
store_roll AS (
    SELECT ps.agency_id, ps.agency_name, ps.store_no,
           sum(ps.supply_amount)              AS munki_income,
           sum(ps.agency_income)              AS agency_income,
           sum(COALESCE(toc.deduct_amount,0)) AS deduct_amount,
           max(COALESCE(toc.ops_qty,0))       AS tableorder_count
    FROM per_store_income ps
    LEFT JOIN LATERAL (
        SELECT
            sum(NULLIF(co.contract_data->>'ops_qty','')::numeric) AS ops_qty,
            CASE WHEN ps.is_deduction IS TRUE THEN
                sum(COALESCE(NULLIF(co.contract_data->>'ops_qty','')::numeric,0)
                  * COALESCE(NULLIF(co.contract_data->>'settle_unit_price','')::numeric,0))
            ELSE 0 END AS deduct_amount
        FROM billing.contracts co
        WHERE co.sell_type = 'tableorder'
          AND co.store_no = ps.store_no
          AND (co.contract_data->>'start_bill_date')::date < to_date(ps.bill_yymm,'YYYY-MM')
    ) toc ON true
    GROUP BY ps.agency_id, ps.agency_name, ps.store_no
)
SELECT sr.agency_id, sr.agency_name,
       count(distinct sr.store_no)                    AS store_count,
       sum(sr.tableorder_count)                       AS tableorder_count,
       sum(sr.munki_income)                           AS munki_income,
       sum(sr.agency_income)                          AS agency_income,
       sum(sr.deduct_amount)                          AS agency_deduct_amount,
       sum(sr.agency_income) - sum(sr.deduct_amount)  AS agency_net_income
FROM store_roll sr
GROUP BY 1, 2
ORDER BY 1;

--정산 상세
WITH per_store AS (
    SELECT sc.agency_id, ct.store_no, bl.bill_yymm,
           bool_or(sc.is_deduction) AS is_deduction,
           max(sc.commission_type)  AS commission_type,
           max(sc.commission)       AS commission,
           sum((iv.invoice_data->>'supply_amount')::bigint) AS supply_amount
    FROM billing.payments pm
    JOIN billing.payment_detail pd ON pm.payment_id = pd.payment_id
    JOIN billing.billing bl        ON pd.bill_id = bl.bill_id
    JOIN billing.invoice iv        ON pd.invoice_id = iv.invoice_id
    JOIN billing.contracts ct      ON iv.cont_id = ct.cont_id
    JOIN billing.settle_contracts sc ON iv.cont_id = sc.cont_id
    WHERE pm.payment_date >= to_date(:yyyy_mm, 'YYYY-MM')
      AND pm.payment_date <  to_date(:yyyy_mm, 'YYYY-MM') + interval '1 month'
      AND ct.sell_type = 'sellup'
      AND sc.agency_id = :agency_id
    GROUP BY sc.agency_id, ct.store_no, bl.bill_yymm
),
per_store_income AS (
    SELECT ps.*,
           CASE WHEN ps.commission_type = '정액'
                THEN ps.commission
                ELSE ps.supply_amount * (ps.commission / 100.0)
           END AS agency_income
    FROM per_store ps
)
SELECT psi.store_no,
       st.store_name,
       psi.bill_yymm,
       psi.commission_type,
       psi.commission,
       psi.supply_amount                                  AS munki_income,
       psi.agency_income,
       COALESCE(toc.deduct_amount, 0)                     AS deduct,
       psi.agency_income - COALESCE(toc.deduct_amount, 0) AS agency_net_income,
       COALESCE(toc.ops_qty, 0)                           AS tableorder_count
FROM per_store_income psi
LEFT JOIN billing.stores st ON st.store_no = psi.store_no
LEFT JOIN LATERAL (
    SELECT
        sum(NULLIF(co.contract_data->>'ops_qty','')::numeric) AS ops_qty,
        CASE WHEN psi.is_deduction IS TRUE THEN
            sum(COALESCE(NULLIF(co.contract_data->>'ops_qty','')::numeric, 0)
              * COALESCE(NULLIF(co.contract_data->>'settle_unit_price','')::numeric, 0))
        ELSE 0 END AS deduct_amount
    FROM billing.contracts co
    WHERE co.sell_type = 'tableorder'
      AND co.store_no = psi.store_no
      AND (co.contract_data->>'start_bill_date')::date < to_date(psi.bill_yymm, 'YYYY-MM')
) toc ON true
ORDER BY st.store_name COLLATE "ko-KR-x-icu", psi.bill_yymm;
