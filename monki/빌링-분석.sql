
-- 월별 매출현황
select to_char(pm.payment_date,'yyyy-mm'),
       count(distinct bl.store_no) store_count,
       sum(bl.total_amount) total_amount,
       sum(case when iv.sell_type='tableorder' then iv.total_amount else 0 end) tableorder_amount,
       sum(case when iv.sell_type='qrorder' then iv.total_amount else 0 end) qrorder_amount,
       sum(case when iv.sell_type='sellup' then iv.total_amount else 0 end) sellup_amount,
       sum(case when iv.sell_type='waiting' then iv.total_amount else 0 end) waiting_amount,
       sum(case when iv.sell_type='kakaotalk' then iv.total_amount else 0 end) kakaotalk_amount,
       sum(case when iv.sell_type='service' then iv.total_amount else 0 end) service_amount,
       count(distinct case when iv.sell_type='tableorder' then bl.store_no end) tableorder_count,
       count(distinct case when iv.sell_type='qrorder' then bl.store_no  end) qrorder_count,
       count(distinct case when iv.sell_type='sellup' then bl.store_no  end) sellup_count,
       count(distinct case when iv.sell_type='waiting' then bl.store_no  end) waiting_count,
       count(distinct case when iv.sell_type='kakaotalk' then bl.store_no end) kakaotalk_count,
       count(distinct case when iv.sell_type='service' then bl.store_no  end) service_count
       from billing.payments pm
  join billing.payment_detail pd on pm.payment_id=pd.payment_id
  join billing.billing bl on pd.bill_id=bl.bill_id
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
 WHERE pm.payment_date >= make_date(:year::int, 1, 1)
  AND pm.payment_date <  make_date(:year::int + 1, 1, 1)
 group by to_char(pm.payment_date,'yyyy-mm')
 order by to_char(pm.payment_date,'yyyy-mm');

-- 월별 계약현황
WITH base AS (
    SELECT co.store_no, co.sell_type,
           (co.contract_data->>'contract_date')::date AS contract_date,
           NULLIF(co.contract_data->>'ops_qty','')::int AS ops_qty
    FROM billing.contracts co
)
-- 1) 이전 연말 누적 (조회연도 1월 1일 이전 전체)
SELECT 0 AS sort_key,
       '전년 누계' AS ym,
       count(distinct store_no) AS store_count,
       count(distinct case when sell_type='tableorder' then store_no end) AS tableorder_contracts,
       count(distinct case when sell_type='qrorder'    then store_no end) AS qrorder_contracts,
       count(distinct case when sell_type='sellup'     then store_no end) AS sellup_contracts,
       count(distinct case when sell_type='waiting'    then store_no end) AS waiting_contracts,
       count(distinct case when sell_type='kakaotalk'  then store_no end) AS kakaotalk_contracts,
       count(distinct case when sell_type='service'    then store_no end) AS service_contracts,
       sum(case when sell_type='tableorder' then ops_qty end) AS tableorder_count
FROM base
WHERE contract_date < make_date(:year::int, 1, 1)

UNION ALL

-- 2) 조회연도 월별
SELECT 1 AS sort_key,
       to_char(contract_date, 'yyyy-mm') AS ym,
       count(distinct store_no),
       count(distinct case when sell_type='tableorder' then store_no end),
       count(distinct case when sell_type='qrorder'    then store_no end),
       count(distinct case when sell_type='sellup'     then store_no end),
       count(distinct case when sell_type='waiting'    then store_no end),
       count(distinct case when sell_type='kakaotalk'  then store_no end),
       count(distinct case when sell_type='service'    then store_no end),
       sum(case when sell_type='tableorder' then ops_qty end)
FROM base
WHERE contract_date >= make_date(:year::int, 1, 1)
  AND contract_date <  make_date(:year::int + 1, 1, 1)
GROUP BY to_char(contract_date, 'yyyy-mm')

ORDER BY sort_key, ym;

select * from table_order.bills where store_no=815;
select * from table_order.bill_items ;
select * from billing.billing where bill_yymm='2026-04';
select * from billing.contracts;
-- 청구데이타
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
         ),
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
     }
