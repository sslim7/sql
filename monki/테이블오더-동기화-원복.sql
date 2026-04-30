  ---
  1. 메뉴이름 롤백

  -- 확인용
  WITH changed AS (
      SELECT
          elem->>'key'                       AS pos_code,
          elem->'current'->>'MenuName'       AS before_name,
          elem->'incoming'->>'MenuName'      AS after_name
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'menus') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'MenuName' <> elem->'incoming'->>'MenuName'
  )
  SELECT c.pos_code, m.menu_no, m.menu_nm AS db_current, c.before_name, c.after_name
  FROM changed c
  JOIN public.tb_store_product sp ON sp.pos_product_code = c.pos_code AND sp.store_no = :store_no
  JOIN public.tb_menu m ON m.product_no = sp.product_no AND m.store_no = sp.store_no
       AND m.use_yn = true AND m.menu_product_type = 'MNPT_103'
  ORDER BY c.pos_code;

  -- 실행용
  WITH changed AS (
      SELECT elem->>'key' AS pos_code, elem->'current'->>'MenuName' AS before_name
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'menus') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'MenuName' <> elem->'incoming'->>'MenuName'
  ),
  targets AS (
      SELECT m.menu_no, c.before_name
      FROM changed c
      JOIN public.tb_store_product sp ON sp.pos_product_code = c.pos_code AND sp.store_no = :store_no
      JOIN public.tb_menu m ON m.product_no = sp.product_no AND m.store_no = sp.store_no
           AND m.use_yn = true AND m.menu_product_type = 'MNPT_103'
  )
  UPDATE public.tb_menu m
  SET menu_nm = t.before_name
  FROM targets t
  WHERE m.menu_no = t.menu_no;

  2. 메뉴순서 롤백

  -- 확인용
  WITH changed AS (
      SELECT
          elem->>'key'                            AS pos_code,
          (elem->'current'->>'SortOrder')::int    AS before_sort,
          (elem->'incoming'->>'SortOrder')::int   AS after_sort
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'menus') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'SortOrder' <> elem->'incoming'->>'SortOrder'
  )
  SELECT c.pos_code, m.menu_no, m.sort_order AS db_current, c.before_sort, c.after_sort
  FROM changed c
  JOIN public.tb_store_product sp ON sp.pos_product_code = c.pos_code AND sp.store_no = :store_no
  JOIN public.tb_menu m ON m.product_no = sp.product_no AND m.store_no = sp.store_no
       AND m.use_yn = true AND m.menu_product_type = 'MNPT_103'
  ORDER BY c.pos_code;

  -- 실행용 (db_current가 after_sort와 일치하는 경우에만 의미있음)
  WITH changed AS (
      SELECT elem->>'key' AS pos_code, (elem->'current'->>'SortOrder')::int AS before_sort
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'menus') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'SortOrder' <> elem->'incoming'->>'SortOrder'
  ),
  targets AS (
      SELECT m.menu_no, c.before_sort
      FROM changed c
      JOIN public.tb_store_product sp ON sp.pos_product_code = c.pos_code AND sp.store_no = :store_no
      JOIN public.tb_menu m ON m.product_no = sp.product_no AND m.store_no = sp.store_no
           AND m.use_yn = true AND m.menu_product_type = 'MNPT_103'
  )
  UPDATE public.tb_menu m
  SET sort_order = t.before_sort
  FROM targets t
  WHERE m.menu_no = t.menu_no;

  3. 옵션이름 롤백

--   옵션 key 형식: group:sdscl-XXXX,sdsgr-XXXX (그룹) / item:sds-XXX,XXXXXX (아이템)
--   → prefix 제거하면 tb_option.pos_option_code와 매칭.

  -- 확인용 (그룹 + 아이템 통합)

  WITH changed AS (
      SELECT
          CASE
              WHEN elem->>'key' LIKE 'group:%' THEN substring(elem->>'key' FROM 7)
              WHEN elem->>'key' LIKE 'item:%'  THEN substring(elem->>'key' FROM 6)
          END AS pos_option_code,
          elem->>'key' AS raw_key,
          elem->'current'->>'OptionName'   AS before_name,
          elem->'incoming'->>'OptionName'  AS after_name
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'options') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'OptionName' <> elem->'incoming'->>'OptionName'
  )
  SELECT c.raw_key, o.option_no, o.option_nm AS db_current, c.before_name, c.after_name
  FROM changed c
  JOIN public.tb_option o ON o.pos_option_code = c.pos_option_code AND o.store_no = :store_no
  ORDER BY c.raw_key;

  -- 실행용
  WITH changed AS (
      SELECT
          CASE
              WHEN elem->>'key' LIKE 'group:%' THEN substring(elem->>'key' FROM 7)
              WHEN elem->>'key' LIKE 'item:%'  THEN substring(elem->>'key' FROM 6)
          END AS pos_option_code,
          elem->'current'->>'OptionName' AS before_name
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'options') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'OptionName' <> elem->'incoming'->>'OptionName'
  ),
  targets AS (
      SELECT o.option_no, c.before_name
      FROM changed c
      JOIN public.tb_option o ON o.pos_option_code = c.pos_option_code AND o.store_no = :store_no
  )
  UPDATE public.tb_option o
  SET option_nm = t.before_name
  FROM targets t
  WHERE o.option_no = t.option_no;

  4. 옵션순서 롤백

  -- 확인용
  WITH changed AS (
      SELECT
          CASE
              WHEN elem->>'key' LIKE 'group:%' THEN substring(elem->>'key' FROM 7)
              WHEN elem->>'key' LIKE 'item:%'  THEN substring(elem->>'key' FROM 6)
          END AS pos_option_code,
          elem->>'key' AS raw_key,
          (elem->'current'->>'SortOrder')::int   AS before_sort,
          (elem->'incoming'->>'SortOrder')::int   AS after_sort
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'options') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'SortOrder' <> elem->'incoming'->>'SortOrder'
  )
  SELECT c.raw_key, o.option_no, o.sort_order AS db_current, c.before_sort, c.after_sort
  FROM changed c
  JOIN public.tb_option o ON o.pos_option_code = c.pos_option_code AND o.store_no = :store_no
  ORDER BY c.raw_key;

  -- 실행용
  WITH changed AS (
      SELECT
          CASE
              WHEN elem->>'key' LIKE 'group:%' THEN substring(elem->>'key' FROM 7)
              WHEN elem->>'key' LIKE 'item:%'  THEN substring(elem->>'key' FROM 6)
          END AS pos_option_code,
          (elem->'current'->>'SortOrder')::int AS before_sort
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'options') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND elem->'current'->>'SortOrder' <> elem->'incoming'->>'SortOrder'
  ),
  targets AS (
      SELECT o.option_no, c.before_sort
      FROM changed c
      JOIN public.tb_option o ON o.pos_option_code = c.pos_option_code AND o.store_no = :store_no
  )
  UPDATE public.tb_option o
  SET sort_order = t.before_sort
  FROM targets t
  WHERE o.option_no = t.option_no;


  -- 옵션 이름,순서 변경 확인용
  WITH changed AS (
      SELECT
          CASE
              WHEN elem->>'key' LIKE 'group:%' THEN substring(elem->>'key' FROM 7)
              WHEN elem->>'key' LIKE 'item:%'  THEN substring(elem->>'key' FROM 6)
          END AS pos_option_code,
          elem->>'key'                          AS raw_key,
          elem->'current'->>'OptionName'        AS before_name,
          elem->'incoming'->>'OptionName'       AS after_name,
          (elem->'current'->>'SortOrder')::int  AS before_sort,
          (elem->'incoming'->>'SortOrder')::int AS after_sort
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'options') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND (elem->'current'->>'OptionName' <> elem->'incoming'->>'OptionName'
             OR elem->'current'->>'SortOrder' <> elem->'incoming'->>'SortOrder')
  )
  SELECT c.raw_key, o.option_no,
         o.option_nm AS db_name, c.before_name, c.after_name,
         o.sort_order AS db_sort, c.before_sort, c.after_sort
  FROM changed c
  JOIN public.tb_option o ON o.pos_option_code = c.pos_option_code AND o.store_no = :store_no
  ORDER BY c.raw_key;

  -- 옵션 이름,순서 변경 실행용
  WITH changed AS (
      SELECT
          CASE
              WHEN elem->>'key' LIKE 'group:%' THEN substring(elem->>'key' FROM 7)
              WHEN elem->>'key' LIKE 'item:%'  THEN substring(elem->>'key' FROM 6)
          END AS pos_option_code,
          elem->'current'->>'OptionName'        AS before_name,
          (elem->'current'->>'SortOrder')::int  AS before_sort
      FROM table_order.tb_pos_sync_version,
           jsonb_array_elements(diff_details->'options') AS elem
      WHERE session_id = '4bf141e0-987c-4ae3-9415-942723befda2'
        AND elem->>'action' = 'UPDATE'
        AND (elem->'current'->>'OptionName' <> elem->'incoming'->>'OptionName'
             OR elem->'current'->>'SortOrder' <> elem->'incoming'->>'SortOrder')
  ),
  targets AS (
      SELECT o.option_no, c.before_name, c.before_sort
      FROM changed c
      JOIN public.tb_option o ON o.pos_option_code = c.pos_option_code AND o.store_no = :store_no
  )
  UPDATE public.tb_option o
  SET --option_nm = t.before_name,
      sort_order = t.before_sort
  FROM targets t
  WHERE o.option_no = t.option_no;
