select * from public.tb_store where store_nm like '%방이%'; --787
다이닝도안2호점
-- 특정매장의 마케팅 동의한 전화번호 목록
select ur.phone from table_order.user_stores us join table_order.users ur on us.user_id=ur.id and ur.marketing_consent=true
 where us.store_no=787;

select * from public.tb_store_config where store_no=891;
select * from pos.seq_tb_deal_deal_id;