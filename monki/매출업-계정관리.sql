
select * from public.tb_store where store_nm like '%영통%';
select * from sellup.basic_info ;
-- *******************************************************************
-- 매출업 매장추가
-- *******************************************************************
-- INSERT INTO sellup.basic_info (store_no)
-- select st.store_no from public.tb_store st where st.store_no=760
-- ON CONFLICT (store_no) DO NOTHING;

select * from sellup.manager;
select * from sellup.manager_store where store_no=760;
-- *******************************************************************
-- 특정 매장의 OWNER 계정 생성 (email=사업자번호,password=사업자번호+a!)
-- *******************************************************************
-- insert into sellup.manager (email, password_hash, name, role)
-- select regexp_replace(st.store_biz_number, '[^0-9]', '', 'g'),
--        crypt(regexp_replace(st.store_biz_number, '[^0-9]', '', 'g') || 'a!',
--        gen_salt('bf', 12)),
--        st.store_nm || ' 사장님',
--        'OWNER'
--   from public.tb_store st where st.store_no=760
--   ON CONFLICT (email) DO NOTHING;
-- INSERT INTO sellup.manager_store (manager_id, store_no, role,is_active)
-- select mgr.manager_id,st.store_no,'OWNER',true
-- from sellup.manager mgr join public.tb_store st on mgr.email = regexp_replace(st.store_biz_number, '[^0-9]', '', 'g') and st.store_no=760
-- ON CONFLICT (manager_id,store_no) DO NOTHING;

--비밀번호 검사
select *,crypt(concat(email,'!'), gen_salt('bf', 12)),crypt(concat(email,'!'),crypt(concat(email,'!'), gen_salt('bf', 12)))=password_hash from sellup.manager where role='OWNER' and email <> 'test';

insert into sellup.manager (email, password_hash, name, role)
select :email,
       crypt(regexp_replace(st.store_biz_number, '[^0-9]', '', 'g') || 'a!',
       gen_salt('bf', 12)),
       st.store_nm || ' 사장님',
       'OWNER'
  from public.tb_store st where st.store_no=760
  ON CONFLICT (email) DO NOTHING;

