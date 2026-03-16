
select * from public.tb_store where store_nm like '%영통%';
-- 760 더진국
-- 687 우나기칸
-- 825 오늘도닭갈비 영통경희대점
select * from sellup.basic_info ;
INSERT INTO sellup.basic_info (store_no, ai_enabled, token_limit, target_sales_month, is_active) VALUES (760, true, 100000000, 0, true);
INSERT INTO sellup.basic_info (store_no, ai_enabled, token_limit, target_sales_month, is_active) VALUES (687, true, 100000000, 0, true);
INSERT INTO sellup.basic_info (store_no, ai_enabled, token_limit, target_sales_month, is_active) VALUES (825, true, 100000000, 0, true);

select * from sellup.manager;
-- 369285c1-f8ae-4321-b951-a65cfe7a8ce2 max
-- e73adca8-5b6b-4cee-b932-1cb644f0c6ea 혁균
-- d1df9fe0-cec8-48d1-be80-3be36d7d7e6a 유민
select * from sellup.manager_store where store_no=760;
INSERT INTO sellup.manager_store (manager_store_id, manager_id, store_no, role,is_active) VALUES (uuid_generate_v4(), 'e73adca8-5b6b-4cee-b932-1cb644f0c6ea', 760, 'MK_ADMIN',true);
INSERT INTO sellup.manager_store (manager_store_id, manager_id, store_no, role,is_active) VALUES (uuid_generate_v4(), 'e73adca8-5b6b-4cee-b932-1cb644f0c6ea', 687, 'MK_ADMIN',true);
INSERT INTO sellup.manager_store (manager_store_id, manager_id, store_no, role,is_active) VALUES (uuid_generate_v4(), 'e73adca8-5b6b-4cee-b932-1cb644f0c6ea', 825, 'MK_ADMIN',true);


select *,crypt(concat(email,'!'), gen_salt('bf', 12)),crypt(concat(email,'!'),crypt(concat(email,'!'), gen_salt('bf', 12)))=password_hash from sellup.manager where role='OWNER' and email <> 'test';

-- OWNER 인사람들 사업자번호+a!로 비번변경
UPDATE sellup.manager
SET
    password_hash = crypt(email || 'a!', gen_salt('bf', 12)),
    updated_at = now()
WHERE role = 'OWNER'
  AND email <> 'test';

update sellup.manager m
set
    password_hash = crypt(m.email || 'a!', gen_salt('bf', 12)),
    updated_at = now()
where exists (
    select 1
    from sellup.manager_store ms
    where ms.manager_id = m.manager_id
      and ms.role = 'OWNER'
)
and m.email <> 'test';

SELECT
    manager_id,
    email,
    crypt(email || 'a!', password_hash) = password_hash AS password_ok
FROM sellup.manager
WHERE role = 'OWNER'
  AND email <> 'test';