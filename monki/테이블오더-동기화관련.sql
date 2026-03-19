
-- 테이블 조회
SELECT gr.*
--          ,
--       gd.ground_name,
--          gr.resource_name,
--          COALESCE(dh.device_id::text, NULL) AS device_i
--          ,
--          to_char(to_timestamp(dh.reg_dt) AT TIME ZONE 'Asia/Seoul', ...) AS "registered_at",
--          to_char(to_timestamp(ds.last_send_dt) AT TIME ZONE 'Asia/Seoul', ...) AS "last_used_at"
  FROM pos.tb_ground_resource gr
  JOIN pos.tb_ground gd ON gr.ground_id = gd.ground_id
  LEFT JOIN pos.tb_device_history dh ON gr.resource_id = dh.resource_id
  LEFT JOIN pos.tb_device_status ds ON dh.device_id = ds.device_id
  WHERE gd.store_no = :storeNo
    AND gr.deleted_yn = false
--     AND gd.deleted_yn = false
  ORDER BY gd.ground_name, gr.resource_name
;

-- 메뉴조회
  SELECT tb_menu.*,
         tb_menu_price.menu_price AS actual_price,
         tb_code.code_desc AS status_name
  FROM tb_menu
  JOIN tb_menu_price ON tb_menu.menu_price_no = tb_menu_price.menu_price_no
  JOIN tb_code ON tb_menu.menu_status = tb_code.code_id
  WHERE tb_menu.store_no = :storeNo
    AND tb_menu.use_yn = true
  ORDER BY sort_order
;

--  1. 카테고리 조회 (line 290-319)
--  # tb_store_category에서 조회
  SELECT * FROM tb_store_category
  WHERE store_no = :store_id AND use_yn = true
  ORDER BY sort_order;

--  2. 메뉴 목록 조회 (line 321-388)
--  # tb_menu + tb_menu_price + tb_code JOIN
  SELECT tb_menu.*,
         tb_menu_price.menu_price AS actual_price,
         tb_code.code_desc AS status_name
  FROM tb_menu
  JOIN tb_menu_price ON tb_menu.menu_price_no = tb_menu_price.menu_price_no
  JOIN tb_code ON tb_menu.menu_status = tb_code.code_id
  WHERE tb_menu.store_no = :store_id
    AND tb_menu.use_yn = true
  ORDER BY sort_order;

--  # 옵션은 별도 쿼리
  SELECT tb_option.*
  FROM tb_option
  JOIN tb_option_menu_mapping ON tb_option.upper_option_no = tb_option_menu_mapping.upper_option_no
  WHERE tb_option_menu_mapping.menu_no = :menu_no
    AND tb_option.use_yn = true
    AND tb_option.store_no = :store_id
  ORDER BY sort_order;

-- 구 데이타 신 store_no로 변경 (매출제외)
-- a매장: 693, b매장: 875
DO $$
    DECLARE
        a_store_no integer := 693;
        b_store_no integer := 875;
    BEGIN
        UPDATE table_order.user_coupon SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.user_points SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.user_stores SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.subscriptions SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.payment_methods SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.payments SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.point_policy SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.store_feature SET store_no = b_store_no WHERE store_no = a_store_no;
        UPDATE table_order.user_visit SET store_no = b_store_no WHERE store_no = a_store_no;
    END
$$;
