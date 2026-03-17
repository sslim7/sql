select * from public.tb_store where store_nm like '%더진국%'; --760

-- 특정매장의 마케팅 동의한 전화번호 목록
select ur.phone from table_order.user_stores us join table_order.users ur on us.user_id=ur.id and ur.marketing_consent=true
 where us.store_no=760;