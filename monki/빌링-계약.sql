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