
WITH per_store AS (
    SELECT sc.agency_id, cd.code_desc, ct.store_no,
           sum((iv.invoice_data->>'supply_amount')::bigint) AS supply_amount
    FROM billing.payments pm
    JOIN billing.payment_detail pd ON pm.payment_id = pd.payment_id
    JOIN billing.invoice iv        ON pd.invoice_id = iv.invoice_id
    JOIN billing.contracts ct      ON iv.cont_id = ct.cont_id
    JOIN billing.settle_contracts sc ON iv.cont_id = sc.cont_id
    JOIN public.tb_code cd ON sc.agency_id = cd.code_id AND cd.code_group = 'AGENCY'
    WHERE pm.payment_date >= to_date(:yyyy_mm, 'YYYY-MM')
      AND pm.payment_date <  to_date(:yyyy_mm, 'YYYY-MM') + interval '1 month'
      AND ct.sell_type='sellup'
    GROUP BY sc.agency_id, cd.code_desc, ct.store_no
),
toc AS (
    SELECT store_no,
           sum(NULLIF(contract_data->>'ops_qty','')::numeric) AS ops_qty,
           sum(NULLIF(contract_data->>'ops_qty','')::numeric
               * NULLIF(contract_data->>'settle_unit_price','')::numeric) AS deduct_amount
    FROM billing.contracts
    WHERE sell_type = 'tableorder' and contract_data->>'start_bill_date'::date < to_date(:yyyy_mm, 'YYYY-MM')
    GROUP BY store_no
)
SELECT ps.agency_id, ps.code_desc,
       count(distinct ps.store_no)  AS store_count,
       sum(toc.ops_qty)             AS tableorder_count,
       sum(ps.supply_amount)        AS income_sellup,
       sum(toc.deduct_amount)       AS cost
FROM per_store ps
LEFT JOIN toc ON toc.store_no = ps.store_no
GROUP BY 1, 2;

select sc.agency_id,cd.code_desc,
       count(distinct ct.store_no),
       sum((iv.invoice_data->>'supply_amount')::bigint) income_sellup,
       (select sum((co.contract_data->>'ops_qty')::bigint) from billing.contracts co
                       where ct.store_no=co.store_no and co.sell_type='tableorder') as aaa
  from billing.payments pm
  join billing.payment_detail pd on pm.payment_id=pd.payment_id
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
  join billing.contracts ct on iv.cont_id=ct.cont_id
  join billing.settle_contracts sc on iv.cont_id=sc.cont_id
  join public.tb_code cd on sc.agency_id=cd.code_id and cd.code_group='AGENCY'
 where pm.payment_date >= to_date(:yyyy_mm,'YYYY-MM')
   and pm.payment_date < to_date(:yyyy_mm, 'YYYY-MM') + interval '1 month'
   and ct.sell_type='sellup'
 group by 1,2
;
select * from public.tb_code cd where cd.code_group='AGENCY'

select * from billing.payments;
select * from billing.contracts;
select * from billing.invoice;