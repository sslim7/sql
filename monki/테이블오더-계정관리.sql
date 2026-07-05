
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