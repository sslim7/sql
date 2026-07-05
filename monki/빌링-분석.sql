-- 매출 데이터 소스 ──
    SELECT
      bl.bill_yymm,
      bl.bill_day,
      st.store_name,
      iv.sell_type,
      coalesce(iv.supply_amount, 0)::int as supply_amount,
      coalesce(iv.vat_amount, 0)::int as vat_amount,
      coalesce(iv.total_amount, 0)::int as total_amount,
      bl.status,
      coalesce(pm.payment_status::text, '미처리') as payment_status
    FROM billing.billing bl
    JOIN billing.stores st ON bl.store_no = st.store_no
    JOIN billing.invoice iv ON bl.bill_id = iv.bill_id
    LEFT JOIN billing.payment_detail pd ON iv.invoice_id = pd.invoice_id
    LEFT JOIN billing.payments pm ON pd.payment_id = pm.payment_id
    WHERE st.is_active = true
    ORDER BY bl.bill_yymm DESC, st.store_name;

-- 계약 데이터 소스 ──
    SELECT
      ct.cont_id,
      st.store_name,
      ct.sell_type,
      ct.sell_status,
      coalesce(ct.contract_data->>'contract_type', '') as contract_type,
      coalesce(ct.contract_data->>'payment_method', '') as payment_method,
      coalesce(ct.contract_data->>'bill_day', '') as bill_day,
      coalesce(nullif(ct.contract_data->>'subs_price', '')::int, 0) as subs_price,
      to_char(ct.created_at, 'YYYY-MM') as contract_month
    FROM billing.contracts ct
    JOIN billing.stores st ON ct.store_no = st.store_no
    WHERE st.is_active = true
    ORDER BY ct.sell_type, st.store_name;

-- 정산 데이터 소스 ──
    WITH per_store AS (
      SELECT
        sc.agency_id,
        cd.code_desc as agency_name,
        ct.store_no,
        st.store_name,
        bl.bill_yymm,
        sc.commission_type,
        sc.commission,
        sc.is_deduction,
        coalesce((iv.invoice_data->>'supply_amount')::int, iv.supply_amount, 0)::int as supply_amount
      FROM billing.settle_contracts sc
      JOIN billing.contracts ct ON sc.cont_id = ct.cont_id
      JOIN billing.stores st ON ct.store_no = st.store_no
      JOIN billing.billing bl ON st.store_no = bl.store_no
      JOIN billing.invoice iv ON bl.bill_id = iv.bill_id AND ct.cont_id = iv.cont_id
      JOIN billing.payment_detail pd ON iv.invoice_id = pd.invoice_id
      JOIN billing.payments pm ON pd.payment_id = pm.payment_id
      LEFT JOIN public.tb_code cd ON sc.agency_id = cd.code_id AND cd.code_group = 'AGENCY'
      WHERE ct.sell_type = 'sellup'
        AND pm.payment_status = 'CMS출금완료'
    ),
    per_store_income AS (
      SELECT
        ps.*,
        ps.supply_amount as monki_income,
        CASE
          WHEN ps.commission_type = '정액' THEN ps.commission::int
          ELSE (ps.supply_amount * ps.commission / 100)::int
        END as agency_income
      FROM per_store ps
    ),
    with_deduct AS (
      SELECT
        psi.*,
        CASE WHEN psi.is_deduction THEN
          coalesce((
            SELECT sum(
              coalesce(nullif(c2.contract_data->>'ops_qty', '')::int, 0)
              * coalesce(nullif(c2.contract_data->>'settle_unit_price', '')::int, 0)
            )
            FROM billing.contracts c2
            WHERE c2.store_no = psi.store_no
              AND c2.sell_type = 'tableorder'
              AND (c2.contract_data->>'start_bill_date') < psi.bill_yymm
          ), 0)::int
        ELSE 0 END as deduct_amount,
        coalesce((
          SELECT sum(coalesce(nullif(c3.contract_data->>'ops_qty', '')::int, 0))
          FROM billing.contracts c3
          WHERE c3.store_no = psi.store_no
            AND c3.sell_type = 'tableorder'
            AND (c3.contract_data->>'start_bill_date') < psi.bill_yymm
        ), 0)::int as tableorder_count
      FROM per_store_income psi
    )
    SELECT
      agency_name,
      store_name,
      bill_yymm,
      commission_type,
      monki_income,
      agency_income,
      deduct_amount,
      (agency_income - deduct_amount) as net_income,
      store_no,
      tableorder_count
    FROM with_deduct
    ORDER BY agency_name, bill_yymm DESC, store_name;

-- 청구 데이터 소스 (향후 7개월 청구예정금액) ──
    WITH months AS (
      SELECT to_char(d, 'YYYY-MM') as bill_yymm
      FROM generate_series(
        ${curYymmDate}::date,
        (${curYymmDate}::date + interval '6 months'),
        interval '1 month'
      ) d
    ),
    active_contracts AS (
      SELECT
        ct.cont_id,
        ct.store_no,
        st.store_name,
        ct.sell_type,
        coalesce(ct.contract_data->>'contract_type', '') as contract_type,
        coalesce(ct.contract_data->>'start_bill_date', '') as start_bill_date,
        coalesce(nullif(ct.contract_data->>'subs_price', '')::int, 0) as subs_price,
        coalesce(nullif(ct.contract_data->>'calc_value', '')::int, 0) as calc_value,
        coalesce(ct.contract_data->>'calc_type', '') as calc_type,
        coalesce(nullif(ct.contract_data->>'unit_price', '')::int, 0) as unit_price
      FROM billing.contracts ct
      JOIN billing.stores st ON ct.store_no = st.store_no
      WHERE st.is_active = true
        AND ct.sell_status = 'active'
    ),
    -- store_no별로 딱 1번만 호출 (sellup 정률 매장만)
    sellup_rate_stores AS (
      SELECT DISTINCT store_no
      FROM active_contracts
      WHERE sell_type = 'sellup' AND calc_type = '정률'
    ),
    sellup_sales AS (
      SELECT s.store_no, billing.get_ai_sales(${prevYymm}::text, s.store_no) as ai_sales
      FROM sellup_rate_stores s
    ),
    -- store_no별로 딱 1번만 호출 (kakaotalk 매장만)
    kakaotalk_stores AS (
      SELECT DISTINCT store_no
      FROM active_contracts
      WHERE sell_type = 'kakaotalk'
    ),
    kakaotalk_counts AS (
      SELECT k.store_no, billing.get_kakaotalk_count(${prevYymm}::text, k.store_no) as msg_count
      FROM kakaotalk_stores k
    ),
    billing_rows AS (
      SELECT
        m.bill_yymm,
        ac.store_name,
        ac.sell_type,
        ac.contract_type,
        CASE
          WHEN ac.contract_type = '무료' THEN 0
          WHEN ac.sell_type IN ('tableorder', 'qrorder', 'waiting') THEN ac.subs_price
          WHEN ac.sell_type = 'sellup' AND ac.calc_type = '정액' THEN ac.calc_value
          WHEN ac.sell_type = 'sellup' AND ac.calc_type = '정률'
            THEN (ac.calc_value * coalesce(ss.ai_sales, 0) / 100)::int
          WHEN ac.sell_type = 'kakaotalk'
            THEN ac.unit_price * coalesce(kc.msg_count, 0)
          ELSE 0
        END as supply_amount
      FROM months m
      CROSS JOIN active_contracts ac
      LEFT JOIN sellup_sales ss ON ac.store_no = ss.store_no
      LEFT JOIN kakaotalk_counts kc ON ac.store_no = kc.store_no
      WHERE m.bill_yymm >= to_char(nullif(ac.start_bill_date, '')::date, 'YYYY-MM')
    )
    SELECT
      bill_yymm,
      store_name,
      sell_type,
      contract_type,
      supply_amount,
      floor(supply_amount * 0.1)::int as vat_amount,
      (supply_amount + floor(supply_amount * 0.1))::int as total_amount
    FROM billing_rows
    ORDER BY bill_yymm, store_name, sell_type
    ;