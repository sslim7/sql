-- 대상 확인 먼저
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
ORDER BY 5 DESC;

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