-- 로그인계정 생성
INSERT INTO public.tb_user_store (store_no, user_id, user_pass, user_phone, user_email, company_number, reg_dt, use_yn, company_type, user_nm, login_yn, upd_dt, store_user_grade, pos_proxy_login_yn, pos_proxy_upd_dt)
VALUES (642, 'max',
        encode(digest('kitiwit7!', 'sha256'), 'hex'), '40c68921874e75d3b67aec21bdda3b0e', '3cf81545147d011967171ca433593470fd89f831b53b0a998066a1b3cd4d42cb', null, EXTRACT(EPOCH FROM now())::bigint, true, 'ST_009', '강해성', false, EXTRACT(EPOCH FROM now())::bigint, 'STUG_101', false, 1769154923);

-- 사장님사이트
  - UT_201: 매장 직접 운영자 (먼키 매장 사장님) → tb_user_store
  - UT_101: POS 파트너사 사용자 → pos.tb_pos_partner_user
-- 파트너사 사용자
 SELECT
    user_id,
    convert_from(
      decrypt(
        decode(user_tel, 'hex'),
        '5c185de7-7641-4cbe-8b90-fdfedd38'::bytea,
        'aes-cbc/pad:pkcs'
      ),
      'UTF8'
    ) AS user_tel_decrypted
  FROM pos.tb_pos_partner_user
  WHERE user_id = 'monkitest6';

-- 사장님사이트 마이페이지 회원정보
  SELECT
    user_id,
    convert_from(
      decrypt(
        decode(user_phone, 'hex'),
        '5c185de7-7641-4cbe-8b90-fdfedd38'::bytea,
        'aes-cbc/pad:pkcs'
      ),
      'UTF8'
    ) AS user_phone_decrypted
  FROM public.tb_user_store
  WHERE user_id = 'monkitest6';

select * from public.tb_store where store_no=702;