SELECT st.store_no,
       st.store_name,
       st.biz_number,
       st.address,
       co1.cont_id                          AS tableorder_cont_id,
       co1.contract_data->>'contract_date'  AS tableorder_contract_date,
       co2.cont_id                          AS sellup_cont_id,
       co2.contract_data->>'contract_date'  AS sellup_contract_date,
       co3.cont_id                          AS kakaotalk_cont_id,
       co3.contract_data->>'contract_date'  AS kakaotalk_contract_date,
       st.is_active
  FROM billing.stores st
  LEFT JOIN billing.contracts co1 ON st.store_no = co1.store_no AND co1.sell_type = 'tableorder'
  LEFT JOIN billing.contracts co2 ON st.store_no = co2.store_no AND co2.sell_type = 'sellup'
  LEFT JOIN billing.contracts co3 ON st.store_no = co3.store_no AND co3.sell_type = 'kakaotalk'
 WHERE 1=1
   AND (:is_active         IS NULL OR st.is_active = :is_active)
--    AND (:search_keyword    IS NULL OR (
--            st.store_name ILIKE '%' || :search_keyword || '%'
--            OR (:search_keyword ~ '^\d+$' AND st.store_no = :search_keyword::BIGINT)
--        ))
   AND (
       (:filter_tableorder  IS NULL AND :filter_sellup IS NULL AND :filter_kakaotalk IS NULL AND :filter_uncontracted IS NULL)
       OR (:filter_tableorder   = TRUE AND co1.cont_id IS NOT NULL)
       OR (:filter_sellup       = TRUE AND co2.cont_id IS NOT NULL)
       OR (:filter_kakaotalk    = TRUE AND co3.cont_id IS NOT NULL)
       OR (:filter_uncontracted = TRUE AND co1.cont_id IS NULL AND co2.cont_id IS NULL AND co3.cont_id IS NULL)
   )
 ORDER BY st.store_name COLLATE "ko-KR-x-icu"
 LIMIT :page_size OFFSET (:page - 1) * :page_size
;

-- 은행코드
select code_id AS bank_no,code_desc from public.tb_code where code_group='BANK' order by sort_order;

--*************
-- 계약 리스트
--*************
SELECT st.store_no,
       st.store_name,
       st.biz_number,
       st.address,
       co1.cont_id                          AS tableorder_cont_id,
       case when iv1.invoice_data->>'supply_amount' is null
           then case
                   when co1.contract_data->>'contract_type' = '무료'
                       then 0
                   else (co1.contract_data->>'subs_price')::INTEGER
                end
            else (iv1.invoice_data->>'supply_amount')::INTEGER
        end AS tableorder_subs_price,
       co1.contract_data->>'start_bill_date' tableorder_start_bill_date,
       co2.cont_id                          AS sellup_cont_id,
       case when iv2.invoice_data->>'supply_amount' is null
           then case
                   when co2.contract_data->>'calc_type' = '정액'
                        then (co2.contract_data->>'calc_value')::INTEGER
                   when co2.contract_data->>'calc_type' = '정률'
                        then (co2.contract_data->>'calc_value')::INTEGER / 100 * billing.get_ai_sales(:bill_yymm,st.store_no) -- fn_sellup
                   else 0
               end
            else (iv2.invoice_data->>'supply_amount')::INTEGER
        end AS sellup_subs_price,
       co2.contract_data->>'start_bill_date' sellup_start_bill_date,
       co3.cont_id                          AS kakaotalk_cont_id,
       case when iv3.invoice_data->>'supply_amount' is null
           then (co3.contract_data->>'unit_price')::INTEGER * billing.get_kakaotalk_count(:bill_yymm,st.store_no)
           else (iv3.invoice_data->>'supply_amount')::INTEGER
       end AS kakaotalk_subs_price,
       co3.contract_data->>'start_bill_date' kakaotalk_start_bill_date,
       co4.cont_id                          AS qrorder_cont_id,
       case when iv4.invoice_data->>'supply_amount' is null
           then (co4.contract_data->>'subs_price')::INTEGER
           else (iv4.invoice_data->>'supply_amount')::INTEGER
       end AS qrorder_subs_price,
       co4.contract_data->>'start_bill_date' qrorder_start_bill_date,
       co5.cont_id                          AS waiting_cont_id,
       case when iv5.invoice_data->>'supply_amount' is null
           then (co5.contract_data->>'subs_price')::INTEGER
           else (iv5.invoice_data->>'supply_amount')::INTEGER
       end AS waiting_subs_price,
       co5.contract_data->>'start_bill_date' waiting_start_bill_date,
       case when iv6.invoice_data->>'supply_amount' is null
           then 0
           else (iv6.invoice_data->>'supply_amount')::INTEGER
       end AS service_subs_price,
       cd.code_desc AS bank,
       bl.status
  FROM billing.stores st
    LEFT JOIN billing.accounts ac ON st.store_no=ac.store_no
    LEFT JOIN public.tb_code cd ON ac.bank_no=cd.code_id
    LEFT JOIN billing.contracts co1 ON st.store_no = co1.store_no AND co1.sell_type = 'tableorder' AND :bill_yymm >= TO_CHAR((co1.contract_data->>'start_bill_date')::DATE, 'YYYY-MM')
    LEFT JOIN billing.contracts co2 ON st.store_no = co2.store_no AND co2.sell_type = 'sellup'     AND :bill_yymm >= TO_CHAR((co2.contract_data->>'start_bill_date')::DATE, 'YYYY-MM')
    LEFT JOIN billing.contracts co3 ON st.store_no = co3.store_no AND co3.sell_type = 'kakaotalk'  AND :bill_yymm >= TO_CHAR((co3.contract_data->>'start_bill_date')::DATE, 'YYYY-MM')
    LEFT JOIN billing.contracts co4 ON st.store_no = co4.store_no AND co4.sell_type = 'qrorder'    AND :bill_yymm >= TO_CHAR((co4.contract_data->>'start_bill_date')::DATE, 'YYYY-MM')
    LEFT JOIN billing.contracts co5 ON st.store_no = co5.store_no AND co5.sell_type = 'waiting'    AND :bill_yymm >= TO_CHAR((co5.contract_data->>'start_bill_date')::DATE, 'YYYY-MM')
    LEFT JOIN billing.billing bl ON st.store_no = bl.store_no and bl.billing_month=(:bill_yymm||'-01')::DATE
    LEFT JOIN billing.invoice iv1 ON bl.bill_id = iv1.bill_id AND iv1.sell_type = 'tableorder'
    LEFT JOIN billing.invoice iv2 ON bl.bill_id = iv2.bill_id AND iv2.sell_type = 'sellup'
    LEFT JOIN billing.invoice iv3 ON bl.bill_id = iv3.bill_id AND iv3.sell_type = 'kakaotalk'
    LEFT JOIN billing.invoice iv4 ON bl.bill_id = iv4.bill_id AND iv4.sell_type = 'qrorder'
    LEFT JOIN billing.invoice iv5 ON bl.bill_id = iv5.bill_id AND iv5.sell_type = 'waiting'
    LEFT JOIN billing.invoice iv6 ON bl.bill_id = iv6.bill_id AND iv6.sell_type = 'service'
      WHERE st.is_active = true
-- ${where}
and (
    st.bill_day=5 or
    st.bill_day=10 or
    st.bill_day=15 or
    st.bill_day=20 or
    st.bill_day=25
)
and st.store_name ILIKE '%' || :searchKeyword || '%'
-- 여기까지 파라미터 받아서 조건을 넣거나 말거나
        ORDER BY st.store_name COLLATE "ko-KR-x-icu"
        LIMIT :pageSize OFFSET (:page - 1) * :pageSize
;

-- fn_kakaotalk_count
select count(1) from table_order.sms_send_log where store_no=:store_no;

select * from billing.invoice;