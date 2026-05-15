select * from public.tb_store where store_nm like '%망부석%';

select * from public.tb_menu mn where mn.store_no=817 and menu_nm='세병곰탕';
select * from public.tb_menu mn
         where menu_no != (split_part(name_translation_key, '.', 2))::bigint and name_translation_key is not null;
--          where mn.menu_no=155778;
select * from public.tb_translation where languages->>'ko' like '%세병%';



select * from tb_store_category;

select * from tb_option;

select * from pos.tb_employee_call_item;

  SELECT u.*
  FROM (
      SELECT user_id, MIN(created_at) AS first_visit
      FROM table_order.user_visit
      WHERE store_no = :storeNo
      GROUP BY user_id
  ) AS visits
  JOIN table_order.users u
    ON u.id = visits.user_id
   AND u.deleted_at IS NULL
  ORDER BY u.created_at DESC;

SELECT * FROM table_order.coupon
  WHERE use_yn = true
    AND issue_type = 'AUTO'
    AND issue_schedule_type = 'CONDITIONAL'
and condition_type='FIRST_VISIT'
and store_no=:storeNo;

SELECT * FROM table_order.user_coupon
  WHERE coupon_id = :couponId;

select count(1) from table_order.user_visit where store_no=:storeNo;
select count(1) from table_order.users ur join table_order.user_visit uv on ur.id=uv.user_id and store_no=:storeNo
 where ur.deleted_at is null;

SELECT COUNT(DISTINCT user_id)
  FROM table_order.user_visit
  WHERE store_no = 854;

  SELECT COUNT(DISTINCT v.user_id)
  FROM table_order.user_visit v
  JOIN table_order.users u ON u.id = v.user_id AND u.deleted_at IS NULL
  WHERE v.store_no = 854;

SELECT COUNT(*)
  FROM table_order.user_coupon
  WHERE coupon_id = 'a1232495-6c45-4d82-b869-3055a21ecf64';

SELECT COUNT(*)
  FROM table_order.user_coupon
  WHERE coupon_id = 'a1232495-6c45-4d82-b869-3055a21ecf64'
    AND issued_at >= '2026-05-08';

SELECT id, store_no, coupon_name, issue_type, issue_schedule_type, use_yn, deleted_at
  FROM table_order.coupon
  WHERE use_yn = true
    AND issue_type = 'AUTO'
    AND issue_schedule_type = 'CONDITIONAL'
    AND deleted_at IS NULL
    AND id = 'a1232495-6c45-4d82-b869-3055a21ecf64';

SELECT id, issue_type, issue_schedule_type, condition_type, use_yn, deleted_at
  FROM table_order.coupon
  WHERE id = 'a1232495-6c45-4d82-b869-3055a21ecf64';

SELECT id, coupon_id, store_no, issued_at
  FROM table_order.user_coupon
  WHERE id = 'e6d7330f-aa90-4cf1-ad84-8e0230c3cf82';

select * from table_order.coupon where id='a1232495-6c45-4d82-b869-3055a21ecf64';

select max(uc.created_at) from table_order.coupon cp join table_order.user_coupon uc on cp.id=uc.coupon_id
 where cp.condition_type='FIRST_VISIT';

select * from table_order.user_stores;

select * from pos.solu;
 "tboAccountType": "TBAT_102",
            "kioskAccountType": null,
            "kioskPos": "",
            "tboPos": "REFP_107",


select * from table_order.user_points
         where change_type='ACCUMULATE' limit 1;
         where store_no=903;


select * from pos.tb_deal td
    join pos.tb_deal_order tdo on td.deal_id=tdo.deal_id and tdo.order_status<>'OPRS_003'
    join pos.tb_deal_order_item doi on tdo.order_id=doi.order_id and doi.order_item_status<>'OPRS_003'
where td.store_no=903 and td.deal_status='OPRS_004';

select * from pos.tb_deal td
    join pos.tb_deal_order tdo on td.deal_id=tdo.deal_id --and tdo.order_status<>'OPRS_003'
    join pos.tb_deal_order_item doi on tdo.order_id=doi.order_id --and doi.order_item_status<>'OPRS_003'
       join table_order.user_points up on td.deal_id=up.deal_id
where --td.store_no=903 and
      td.deal_id=227545
--       td.deal_status='OPRS_011'
;

select * from public.tb_code where code_id like 'OPRS_%';
select * from public.tb_store where store_no=903;
OPRS_000,가요청
OPRS_001,요청중
OPRS_002,접수대기
OPRS_003,요청
OPRS_004,진행중
OPRS_005,준비완료
OPRS_006,완료
OPRS_011,취소
OPRS_012,거절


SELECT * FROM public.tb_store_pos sp join public.tb_store st on sp.store_no=st.store_no WHERE --store_no = '903' LIMIT 1;
tbo_account_type='TBAT_102' and ref_pos='REFP_107';
844,삼시세끼
885,낭만족발
897,뒷골생오리
903,얼룩말식당 세종점

select * from table_order.user_points up
 where up.store_no in (844,885,897,903) and change_type='PENDING';

SELECT id, user_id, store_no, deal_id, change_type
FROM table_order.user_points
WHERE store_no IN (844, 885, 897, 903)
  AND change_type = 'PENDING'
  AND deal_id IS NOT NULL;
