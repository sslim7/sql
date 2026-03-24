
select * from public.tb_store where store_nm like '%영통%';
select * from sellup.basic_info ;
-- 매장리스트 v1/admin/binfos
select bi.store_no,
       st.store_nm,
       regexp_replace(regexp_replace(st.store_biz_number, '[^0-9]', '', 'g'),'^(\d{3})(\d{2})(\d{5})$','\1-\2-\3') AS biz_number,
       concat(st.address,' ',st.address_detail) address,
       (select count(1) from sellup.manager_store ms join sellup.manager mr on ms.manager_id=mr.manager_id and mr.is_active=true where ms.store_no=bi.store_no) managers,
       bi.ai_enabled,
       bi.token_limit,
       bi.target_sales_month,
       bi.is_active
  from sellup.basic_info bi join public.tb_store st on bi.store_no=st.store_no;


-- *******************************************************************
-- 매출업 매장추가  v1/admin/binfo.create
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

insert into sellup.manager (email, password_hash, name, role)
values (:email,
        crypt(:pwd, gen_salt('bf', 12)),
        :name,
        :role)
RETURNING manager_id;
-- sellup0000!
-- 계정리스트  v1/admin/managers
select mg.manager_id,
       mg.email,
       mg.name,
       mg.is_active,
       mg.role,
       (select count(1) from sellup.manager_store ms where mg.manager_id=ms.manager_id and ms.is_active=true)
  from sellup.manager mg;

select ms.store_no,st.store_nm,ms.is_active from sellup.manager_store ms
    join public.tb_store st on ms.store_no=st.store_no
         where ms.manager_id=:manager_id;
select bi.store_no,st.store_nm,concat(st.address,' ',st.address_detail) address from sellup.basic_info bi join public.tb_store st on bi.store_no=st.store_no
 where not exists (
     select 1 from sellup.manager_store ms
      where ms.store_no=bi.store_no and ms.manager_id=:manager_id
 )
where bi.store_nm like :store_nm or bi.address like :address;
select * from public.tb_store where store_no=693;

select * from sellup.manager_store;

        SELECT
            mg.manager_id::text,
            mg.email,
            mg.name,
            mg.is_active,
            mg.role::text,
            (
                SELECT count(1)
                FROM sellup.manager_store ms
                WHERE mg.manager_id = ms.manager_id AND ms.is_active = true
            ) AS store_count
        FROM sellup.manager mg
        where mg.name LIKE '%monki%' OR mg.email LIKE '%monki%'
        ORDER BY mg.name asc
        LIMIT 30 OFFSET 0
        ;
select * from sellup.manager where manager_id='d1df9fe0-cec8-48d1-be80-3be36d7d7e6a';
select * from sellup.manager_store ms
         where manager_id='369285c1-f8ae-4321-b951-a65cfe7a8ce2'
-- and not exists (select * from sellup.basic_info bi where ms.store_no=bi.store_no)
;

SELECT
            ms.store_no,
            st.store_nm,
            ms.is_active
        FROM sellup.manager_store ms
        JOIN public.tb_store st ON ms.store_no = st.store_no
        WHERE ms.manager_id = 'd1df9fe0-cec8-48d1-be80-3be36d7d7e6a'
        ORDER BY st.store_nm;

select ms.manager_id,mgr.name,mgr.email,ms.role from sellup.manager_store ms join sellup.manager mgr on ms.manager_id=mgr.manager_id where ms.store_no=812 order by mgr.name COLLATE "ko-KR-x-icu";
select mgr.manager_id,mgr.name from sellup.manager mgr
 where not exists (select * from sellup.manager_store ms where mgr.manager_id=ms.manager_id and ms.store_no=812) and mgr.is_active=true
 and (mgr.name like '%홍길%' or mgr.email like '%monki%')
 order by mgr.name COLLATE "ko-KR-x-icu";

select * from sellup.apilot_config_store;

SELECT
            bi.store_no,
            case when acs.store_no is null then concat(st.store_nm,' 🚀') else st.store_nm end AS store_nm,acs.is_auto_pilot,
            regexp_replace(
                regexp_replace(st.store_biz_number, '[^0-9]', '', 'g'),
                '^(\\d{{3}})(\\d{{2}})(\\d{{5}})$',
                '\\1-\\2-\\3'
            ) AS biz_number,
            concat(st.address, ' ', st.address_detail) AS address,
            (
                SELECT count(1)
                FROM sellup.manager_store ms
                JOIN sellup.manager mr
                  ON ms.manager_id = mr.manager_id AND mr.is_active = true
                WHERE ms.store_no = bi.store_no
            ) AS managers,
            bi.ai_enabled,
            bi.token_limit,
            bi.target_sales_month,
            bi.is_active
        FROM sellup.basic_info bi
        JOIN public.tb_store st ON bi.store_no = st.store_no
        LEFT JOIN sellup.apilot_config_store acs on bi.store_no = acs.store_no and acs.is_auto_pilot=true;