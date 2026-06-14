
-- 월별 매출현황
select to_char(pm.payment_date,'yyyy-mm'),
       count(distinct bl.store_no) store_count,
       sum(bl.total_amount) total_amount,
       count(distinct case when iv.sell_type='tableorder' then bl.store_no end) tableorder_count,
       count(distinct case when iv.sell_type='qrorder' then bl.store_no  end) qrorder_count,
       count(distinct case when iv.sell_type='sellup' then bl.store_no  end) sellup_count,
       count(distinct case when iv.sell_type='waiting' then bl.store_no  end) waiting_count,
       count(distinct case when iv.sell_type='kakaotalk' then bl.store_no end) kakaotalk_count,
       count(distinct case when iv.sell_type='service' then bl.store_no  end) service_count,
       sum(case when iv.sell_type='tableorder' then iv.total_amount else 0 end) tableorder_abount,
       sum(case when iv.sell_type='qrorder' then iv.total_amount else 0 end) qrorder_abount,
       sum(case when iv.sell_type='sellup' then iv.total_amount else 0 end) sellup_abount,
       sum(case when iv.sell_type='waiting' then iv.total_amount else 0 end) waiting_abount,
       sum(case when iv.sell_type='kakaotalk' then iv.total_amount else 0 end) kakaotalk_abount,
       sum(case when iv.sell_type='service' then iv.total_amount else 0 end) service_abount
       from billing.payments pm
  join billing.payment_detail pd on pm.payment_id=pd.payment_id
  join billing.billing bl on pd.bill_id=bl.bill_id
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
 WHERE pm.payment_date >= make_date(:year::int, 1, 1)
  AND pm.payment_date <  make_date(:year::int + 1, 1, 1)
 group by to_char(pm.payment_date,'yyyy-mm')
 order by to_char(pm.payment_date,'yyyy-mm');

-- 월별 계약현황
SELECT to_char((co.contract_data->>'contract_date')::date, 'yyyy-mm') AS ym,
       count(distinct co.store_no) AS store_count,
       count(distinct case when co.sell_type='tableorder' then co.store_no end) AS tableorder_count,
       count(distinct case when co.sell_type='qrorder'    then co.store_no end) AS qrorder_count,
       count(distinct case when co.sell_type='sellup'     then co.store_no end) AS sellup_count,
       count(distinct case when co.sell_type='waiting'    then co.store_no end) AS waiting_count,
       count(distinct case when co.sell_type='kakaotalk'  then co.store_no end) AS kakaotalk_count,
       count(distinct case when co.sell_type='service'    then co.store_no end) AS service_count,
       sum(case when co.sell_type='tableorder'
                then (co.contract_data->>'ops_qty')::int end) AS tableorder_dv_count
FROM billing.contracts co
WHERE (co.contract_data->>'contract_date')::date >= make_date(:year::int, 1, 1)
  AND (co.contract_data->>'contract_date')::date <  make_date(:year::int + 1, 1, 1)
GROUP BY to_char((co.contract_data->>'contract_date')::date, 'yyyy-mm')
ORDER BY to_char((co.contract_data->>'contract_date')::date, 'yyyy-mm');

