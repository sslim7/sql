
-- 얼룩말
-- 결제 콜백누락으로 주문도 요청으로 남아있고, 포인트도 적립 누락되었다
-- 주문을 모두 완료로 수정하고 포인트도 적립으로 수정
-- ⚠️ 트랜잭션으로 묶어서 실행 (문제 시 롤백 가능)
BEGIN;

select * from public.tb_store where store_nm like '얼룩말%'; -- 903

UPDATE pos.tb_deal
SET deal_status = 'OPRS_006'
WHERE deal_id IN (
    SELECT deal_id
    FROM table_order.user_points
    WHERE store_no IN (903)
      AND change_type = 'PENDING'  -- 위 UPDATE 이후 상태
      AND deal_id IS NOT NULL
);

UPDATE pos.tb_deal_order
SET order_status = 'OPRS_006'
WHERE deal_id IN (
    SELECT deal_id
    FROM table_order.user_points
    WHERE store_no IN (903)
      AND change_type = 'PENDING'
      AND deal_id IS NOT NULL
);

UPDATE pos.tb_deal_order_item
SET order_item_status = 'OPRS_006'
WHERE deal_id IN (
    SELECT deal_id
    FROM table_order.user_points
    WHERE store_no IN (903)
      AND change_type = 'PENDING'
      AND deal_id IS NOT NULL
);

UPDATE table_order.user_points
SET change_type = 'ACCUMULATE'
WHERE store_no IN (903)
  AND change_type = 'PENDING';

COMMIT;

-- 거래완료인데 포인트 PENDING 건들
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

