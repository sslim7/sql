select * from public.v_pg_payments where pg_mall_name='강릉과질';
select * from public.tb_user where user_no=2103; -- where user_nm='김소영';
select * from public.tb_user_address;
select * from public.tb_user_store -- where user_id='hyeum';
;

select *,store_biz_number from public.tb_store where store_nm like '전주장작불곰탕춘천%';

SELECT
    row_number() OVER (ORDER BY ua.address_no DESC) AS no,
    ua.address_no,
    ua.address_nm,
    ua.near_kitchen_no,
    k.kitchen_nm AS near_kitchen_nm,
    convert_from(decrypt(decode(ua.address, 'hex'), :DB_KEY, 'aes'), 'utf8') AS address,
    convert_from(decrypt(decode(ua.road_address, 'hex'), :DB_KEY, 'aes'), 'utf8') AS road_address,
    convert_from(decrypt(decode(ua.building_name, 'hex'), :DB_KEY, 'aes'), 'utf8') AS building_name,
    convert_from(decrypt(decode(ua.address_detail, 'hex'), :DB_KEY, 'aes'), 'utf8') AS address_detail,
    ua.user_address_type,
    public.fn_get_codetext(ua.user_address_type, 'user_address_type') AS user_address_type_desc,
    COUNT(*) OVER() AS tot_cnt
  FROM public.tb_user_address ua
  LEFT JOIN public.tb_kitchen k ON k.kitchen_no = ua.near_kitchen_no
  WHERE ua.use_yn = true
    AND ua.user_no = :user_no
  ORDER BY ua.address_no DESC
  LIMIT :range OFFSET :offset
;
-- DB_KEY 5c185de7-7641-4cbe-8b90-fdfedd38
-- user_no 2103 <-- hyeum@monki.net

select * from public.tb_user where convert_from(decrypt(decode(user_email, 'hex'), :DB_KEY, 'aes'), 'utf8') = 'hyeum@monki.net';

