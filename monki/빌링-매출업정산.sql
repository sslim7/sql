
select sc.agency_id,cd.code_desc,
       count(distinct ct.store_no),

  from billing.payments pm
  join billing.payment_detail pd on pm.payment_id=pd.payment_id
  join billing.invoice co on pd.invoice_id=co.invoice_id
  join billing.contracts ct on co.cont_id=ct.cont_id
  join billing.settle_contracts sc on co.cont_id=sc.cont_id
  join public.tb_code cd on sc.agency_id=cd.code_id and cd.code_group='AGENCY'
 where pm.payment_date >= to_date(:yyyy_mm,'YYYY-MM')
   and pm.payment_date < to_date(:yyyy_mm, 'YYYY-MM') + interval '1 month'
 group by 1,2
;
select * from public.tb_code cd where cd.code_group='AGENCY'

select * from billing.payments;