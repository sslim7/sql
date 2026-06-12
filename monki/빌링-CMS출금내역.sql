
select pm.payment_id,
       any_value(pm.payment_date) payment_date,
       any_value(bl.total_amount) payment_amount,
       any_value(pm.payment_status) payment_status,
       any_value(pm.reason) reason
  from billing.payment_detail pd
  join billing.payments pm on pm.payment_id=pd.payment_id and pm.payment_status <> '신용카드'
  join billing.billing bl on pd.bill_id=bl.bill_id  and bl.store_no=:store_no
group by pm.payment_id
order by pm.payment_date desc
;

-- 청구기본사항
select st.store_no,st.store_name,ac.bank_no,cd.code_desc bank_name,right(ac.account_number,4) account_number
  from billing.stores st
  left join billing.accounts ac on st.store_no=ac.store_no
  left join public.tb_code cd on ac.bank_no=cd.code_id
 where st.store_no=:store_no;

-- 청구내역 쿼리
select bl.bill_yymm,
       case iv.sell_type::text
        when 'tableorder' then '테이블오더 디바이스'
        when 'qrorder' then 'QR오더'
        when 'sellup' then '매출업'
        when 'kakaotalk' then '알림톡'
        when 'waiting' then '웨이팅'
        when 'service' then 'A/S 비용'
        else iv.sell_type::text
       end item_name,
       case iv.sell_type::text
        when 'tableorder' then concat(iv.invoice_data->>'qty',' 디바이스 X ',iv.invoice_data->>'unit_price','원')
        when 'qrorder' then concat(iv.invoice_data->>'qty',' 테이블 X ',iv.invoice_data->>'unit_price','원')
        when 'sellup' then
            case
                when iv.invoice_data->>'calc_type'='정액' then concat('정액: ',iv.invoice_data->>'calc_value','원')
                else concat('ai매출 ',iv.invoice_data->>'ai_sales','원 X ',iv.invoice_data->>'calc_value',' %')
            end
        when 'kakaotalk' then concat(iv.invoice_data->>'qty','건 발송 X ',iv.invoice_data->>'unit_price','원')
        when 'waiting' then ''
        when 'service' then
           case
               when jsonb_array_length(iv.invoice_data -> 'items') = 1
               then concat(iv.invoice_data -> 'items' -> 0 ->> 'service_date',' ',iv.invoice_data -> 'items' -> 0 ->> 'service_name' )
               else concat(iv.invoice_data -> 'items' -> 0 ->> 'service_date',' ',iv.invoice_data -> 'items' -> 0 ->> 'service_name', ' 외' )
           end
        else iv.sell_type::text
       end basis,
       iv.total_amount,
       iv.supply_amount,
       iv.vat_amount,
       iv.invoice_data
  from billing.payment_detail pd
  join billing.payments pm on pm.payment_id=pd.payment_id
  join billing.billing bl on pd.bill_id=bl.bill_id and bl.store_no=:store_no
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
 where pd.payment_id=:payment_id
;

select * from billing.payment_detail where payment_id='192fce59-de9f-4d81-a340-03526a4b06fe';


select * from billing.payment_detail where payment_id='fb06dadf-3b9c-4785-be7a-f6c17632d155';
select * from billing.billing where bill_id='b2e893d2-27bb-41cd-856c-3b3cfe5c3dbd';
select * from billing.invoice where bill_id='b2e893d2-27bb-41cd-856c-3b3cfe5c3dbd';
7f0ef023-86c0-46a3-859a-eeb0c4f1201a,b2e893d2-27bb-41cd-856c-3b3cfe5c3dbd

명칭
