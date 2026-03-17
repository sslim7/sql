-- 포스변경되어 메뉴 사잔, 설명 업데이트
-- 사진 있는것만 가져와서 설명까지 업데이트한다
SELECT
    tm875.menu_no,
    tm875.menu_nm,
    tm693.menu_nm    AS src_menu_nm,
    tm693.menu_desc  AS new_desc,
    tm693.use_img_no AS new_img
FROM public.tb_menu tm875
JOIN (
    SELECT DISTINCT ON (REPLACE(menu_nm, ' ', ''))
        menu_nm,
        menu_desc,
        use_img_no
    FROM public.tb_menu
    WHERE store_no = 693
      AND use_img_no IS NOT NULL
      AND menu_desc IS NOT NULL
    ORDER BY REPLACE(menu_nm, ' ', ''), menu_no
) tm693 ON REPLACE(tm875.menu_nm, ' ', '') = REPLACE(tm693.menu_nm, ' ', '')
WHERE tm875.store_no = 875;

--
UPDATE public.tb_menu tm875
SET
    menu_desc = tm693.menu_desc,
    use_img_no = tm693.use_img_no
FROM (
    SELECT DISTINCT ON (REPLACE(menu_nm, ' ', ''))
        menu_nm,
        menu_desc,
        use_img_no
    FROM public.tb_menu
    WHERE store_no = 693
      AND use_img_no IS NOT NULL   -- img 있는 것만
      AND menu_desc IS NOT NULL    -- desc 있는 것만
    ORDER BY REPLACE(menu_nm, ' ', ''), menu_no
) tm693
WHERE tm875.store_no = 875
  AND REPLACE(tm875.menu_nm, ' ', '') = REPLACE(tm693.menu_nm, ' ', '');