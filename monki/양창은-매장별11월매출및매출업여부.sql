WITH params AS (
  SELECT '2026-11'::text AS ym            -- 매출 집계 월
),
bounds AS (
  SELECT EXTRACT(EPOCH FROM (to_date(ym,'YYYY-MM')::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint                      AS from_utc,
         EXTRACT(EPOCH FROM ((to_date(ym,'YYYY-MM') + interval '1 month')::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS to_utc
  FROM params
),
base AS (                                  -- 행 집합: 테이블오더 구독 매장(매장당 1행)
  SELECT s.store_no, s.plan, s.status, s.trial_start_date, s.trial_end_date
  FROM table_order.subscriptions s
),
sales AS (                                 -- 매출액: OPRS_006 total_price 합, 월 요약 SQL 과 같은 정의
  SELECT doi.store_no, SUM(COALESCE(doi.total_price, 0))::bigint AS month_sales
  FROM pos.tb_deal_order_item doi
  CROSS JOIN bounds b
  WHERE doi.order_item_status = 'OPRS_006'
    AND doi.reg_dt >= b.from_utc AND doi.reg_dt < b.to_utc
  GROUP BY 1
),
feat AS (                                  -- 포인트/쿠폰: store_feature.is_enabled, 행 없으면 feature 기본값
  SELECT b.store_no, f.code,
         COALESCE(sf.is_enabled
                  AND (sf.effective_from IS NULL OR sf.effective_from <= now())
                  AND (sf.effective_to   IS NULL OR sf.effective_to   >  now()),
                  f.default_enabled) AS enabled
  FROM base b
  CROSS JOIN table_order.feature f
  LEFT JOIN table_order.store_feature sf ON sf.store_no = b.store_no AND sf.feature_id = f.id
  WHERE f.code IN ('POINT', 'COUPON')
),
card AS (                                  -- 카드등록: CARD 이고 bill_key 가 있는 행
  SELECT store_no,
         bool_or(method_type = 'CARD' AND bill_key IS NOT NULL) AS card_registered
  FROM table_order.payment_methods
  GROUP BY 1
)
SELECT b.store_no                                                           AS "매장번호",
       st.store_nm                                                          AS "상호",
       COALESCE(NULLIF(st.store_biz_number, ''), bs.biz_number)             AS "사업자번호",
       COALESCE(sa.month_sales, 0)                                          AS "11월 매출액",
       CASE WHEN b.trial_start_date IS NULL THEN ''
            ELSE to_char(b.trial_start_date, 'YYYY.MM.DD') || ' ~ ' || to_char(b.trial_end_date, 'YYYY.MM.DD') END AS "무료기간",
       b.status                                                             AS "구독상태",
       CASE WHEN fp.enabled THEN 'Y' ELSE 'N' END                           AS "포인트 적용여부",
       CASE WHEN fc.enabled THEN 'Y' ELSE 'N' END                           AS "쿠폰 적용여부",
       CASE WHEN COALESCE(c.card_registered, false) THEN 'Y' ELSE 'N' END   AS "카드등록 여부",
       CASE WHEN bi.is_active AND COALESCE(cs.is_auto_pilot, false) THEN 'Y' ELSE '' END     AS "매출업 오토파일럿",
       CASE WHEN bi.is_active AND NOT COALESCE(cs.is_auto_pilot, false) THEN 'Y' ELSE '' END AS "매출업 베이직",
       CASE WHEN COALESCE(bi.is_active, false) THEN '' ELSE 'Y' END                           AS "매출업 미적용"
FROM base b
LEFT JOIN public.tb_store st            ON st.store_no = b.store_no
LEFT JOIN billing.stores bs             ON bs.store_no = b.store_no
LEFT JOIN sales sa                      ON sa.store_no = b.store_no
LEFT JOIN feat fp                       ON fp.store_no = b.store_no AND fp.code = 'POINT'
LEFT JOIN feat fc                       ON fc.store_no = b.store_no AND fc.code = 'COUPON'
LEFT JOIN card c                        ON c.store_no  = b.store_no
LEFT JOIN sellup.basic_info bi          ON bi.store_no = b.store_no
LEFT JOIN sellup.apilot_config_store cs ON cs.store_no = b.store_no
ORDER BY b.store_no;