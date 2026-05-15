-- ⚠️ 트랜잭션으로 묶어서 실행 (문제 시 롤백 가능)
BEGIN;

-- 1. table_order.user_points: PENDING → ACCUMULATE
-- UPDATE table_order.user_points
-- SET change_type = 'ACCUMULATE'
-- WHERE store_no IN (897)
--   AND change_type = 'PENDING';

-- 2. pos.tb_deal: deal_status → OPRS_006
UPDATE pos.tb_deal
SET deal_status = 'OPRS_006'
WHERE deal_id IN (
    SELECT deal_id
    FROM table_order.user_points
    WHERE store_no IN (897)
      AND change_type = 'PENDING'  -- 위 UPDATE 이후 상태
      AND deal_id IS NOT NULL
);

-- 3. pos.tb_deal_store: order_status → OPRS_006
UPDATE pos.tb_deal_order
SET order_status = 'OPRS_006'
WHERE deal_id IN (
    SELECT deal_id
    FROM table_order.user_points
    WHERE store_no IN (897)
      AND change_type = 'PENDING'
      AND deal_id IS NOT NULL
);

-- 4. pos.tb_deal_store_item: order_item_status → OPRS_006
UPDATE pos.tb_deal_order_item
SET order_item_status = 'OPRS_006'
WHERE deal_id IN (
    SELECT deal_id
    FROM table_order.user_points
    WHERE store_no IN (897)
      AND change_type = 'PENDING'
      AND deal_id IS NOT NULL
);

-- 결과 확인 후 커밋 or 롤백
-- ROLLBACK;
COMMIT;


select up.store_no,
       st.store_nm,
       cd1.code_desc,
       cd2.code_desc,
       left(up.created_at::text,10),
       up.order_id,
       count(1)
from table_order.user_points up
join pos.tb_deal_order tdo on up.order_id=tdo.order_id and tdo.order_status = 'OPRS_006'
join public.tb_store st on up.store_no=st.store_no
join public.tb_store_pos sp on up.store_no=sp.store_no
join public.tb_code cd1 on sp.ref_pos=cd1.code_id
join public.tb_code cd2 on sp.tbo_account_type=cd2.code_id
 where up.change_type='PENDING'
 group by 1,2,3,4,5,6
order by 5 desc;

SELECT up.store_no,
       up.order_id,
       up.change_type,
       tdo.order_status,
       left(up.created_at::text, 10) AS created_date,
       count(1)
FROM table_order.user_points up
JOIN pos.tb_deal_order tdo ON up.order_id = tdo.order_id
                           AND tdo.order_status = 'OPRS_006'
WHERE up.change_type = 'PENDING'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 5 DESC
;

-- UPDATE
BEGIN;

UPDATE table_order.user_points up
SET change_type = 'ACCUMULATE'
FROM pos.tb_deal_order tdo
WHERE up.order_id = tdo.order_id
  AND tdo.order_status = 'OPRS_006'
  AND up.change_type = 'PENDING';

-- 영향받은 row 수 확인 후
-- ROLLBACK;
COMMIT;


646,샤브몽,OKPOS(공용),선불요금제,2026-05-14,1703987,1
824,오늘도닭갈비 본점,"OKPOS(KIS,NICE서버)",후불요금제,2026-05-14,1705501,1
824,오늘도닭갈비 본점,"OKPOS(KIS,NICE서버)",후불요금제,2026-05-14,1705570,1
824,오늘도닭갈비 본점,"OKPOS(KIS,NICE서버)",후불요금제,2026-05-14,1705652,1
839,완도상회 물금역본점,"OKPOS(KIS,NICE서버)",후불요금제,2026-05-14,1705710,1

select * from pos.tb_deal where deal_id=1095382;
select * from pos.tb_deal_order_item where order_id=1707866;
select * from table_order.user_points where order_id=1705501;
select * from pos.tb_deal_order_item where deal_id=1092311;
1092313
select * from table_order.user_points where order_id=1703987;

select order_id,count(1)
from table_order.user_points
where change_type in ('PENDING','ACCUMULATE') and created_at > '2026-05-01'
group by 1 having count(1)>1;

select * from table_order.user_points where order_id in (1661116);
select * from pos.tb_deal_order_item where order_id=1661116;
1260
179

select * from table_order.tb_store_sync_config;


