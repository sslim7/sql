WITH p AS (
  SELECT
    :store_no::bigint         AS store_no,
    :base_date::date          AS base_date,
    lower(:period)::text      AS period
),

base_window AS (
  SELECT
    store_no,
    period,
    base_date,

    date_trunc('month', base_date)::date                                   AS this_month_start,
    (date_trunc('month', base_date) + interval '1 month')::date            AS next_month_start,
    ((date_trunc('month', base_date) + interval '1 month')::date
      - interval '1 day')::date                                            AS this_month_last_day,
    (date_trunc('month', base_date) - interval '1 month')::date            AS prev_month_start,

    CASE
      WHEN period = 'day'     THEN base_date
      WHEN period = 'weekday' THEN base_date
      WHEN period = 'week'    THEN (base_date - interval '6 day')::date
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN date_trunc('month', base_date)::date
      WHEN period = 'mtdhms'  THEN date_trunc('month', base_date)::date
    END AS this_from_kst,

    CASE
      WHEN period = 'mtdhms'  THEN base_date::timestamp
                                   + (now() AT TIME ZONE 'Asia/Seoul')::time
      WHEN period = 'mtd'     THEN (base_date + interval '1 day')::timestamp
      ELSE (base_date + interval '1 day')::timestamp
    END AS this_to_kst,

    CASE
      WHEN period = 'day'     THEN (base_date - interval '1 day')::date
      WHEN period = 'weekday' THEN (base_date - interval '7 day')::date
      WHEN period = 'week'    THEN (base_date - interval '13 day')::date
      WHEN period = 'month'   THEN (base_date - interval '2 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '6 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN (date_trunc('month', base_date) - interval '1 month')::date
      WHEN period = 'mtdhms'  THEN (date_trunc('month', base_date) - interval '1 month')::date
    END AS prev_from_kst,

    CASE
      WHEN period = 'day'     THEN base_date
      WHEN period = 'weekday' THEN (base_date - interval '6 day')::date
      WHEN period = 'week'    THEN (base_date - interval '6 day')::date
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::date

      WHEN period = 'mtd' THEN
        CASE
          WHEN base_date = ((date_trunc('month', base_date) + interval '1 month')::date
                            - interval '1 day')::date
            THEN date_trunc('month', base_date)::date
          ELSE (
            (date_trunc('month', base_date) - interval '1 month')::date
            + (base_date - date_trunc('month', base_date)::date + 1)
          )::date
        END

      WHEN period = 'mtdhms' THEN
        LEAST(
          ((date_trunc('month', base_date) - interval '1 month')::date
           + (base_date - date_trunc('month', base_date)::date)
          )::timestamp
          + (now() AT TIME ZONE 'Asia/Seoul')::time,
          date_trunc('month', base_date)::timestamp
        )
    END AS prev_to_kst
  FROM p
),

tz AS MATERIALIZED (
  SELECT
    store_no,
    period,
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM (prev_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_to_utc
  FROM base_window
),

menu_info AS (
  SELECT DISTINCT
    m.store_no,
    m.menu_no,
    m.menu_nm,
    m.category_no,
    m.main_category_no,
    m.menu_type,
    m.menu_product_type,
    COALESCE(m.best_menu_yn, false) AS best_menu_yn
  FROM public.tb_menu m
  JOIN p
    ON p.store_no = m.store_no
  JOIN public.tb_menu_price mp
    ON mp.menu_no = m.menu_no
   AND mp.menu_price > 0
  WHERE COALESCE(m.use_yn, true) = true
),

menu_price AS (
  SELECT
    mn.store_no,
    mp.menu_no,
    MAX(mp.menu_price) AS menu_price
  FROM public.tb_menu_price mp
  JOIN public.tb_menu mn
    ON mn.menu_no = mp.menu_no
  JOIN p
    ON p.store_no = mn.store_no
  WHERE mp.menu_price > 0
  GROUP BY mn.store_no, mp.menu_no
),

base AS (
  SELECT
    doi.store_no,
    doi.menu_no,
    doi.order_id,
    doi.deal_id,
    doi.reg_dt,
    COALESCE(doi.product_count, 0) AS product_count,
    COALESCE(doi.total_price, 0) AS total_price,
    CASE
      WHEN doi.reg_dt >= tz.this_from_utc AND doi.reg_dt < tz.this_to_utc THEN 'this'
      WHEN doi.reg_dt >= tz.prev_from_utc AND doi.reg_dt < tz.prev_to_utc THEN 'prev'
      ELSE NULL
    END AS period_type
  FROM pos.tb_deal_order_item doi
  JOIN tz
    ON tz.store_no = doi.store_no
  WHERE doi.store_no = tz.store_no
    AND doi.deleted_yn = false
    AND doi.order_item_status = 'OPRS_006'
    AND doi.menu_no IS NOT NULL
    AND doi.reg_dt >= tz.prev_from_utc
    AND doi.reg_dt <  tz.this_to_utc
),

agg AS (
  SELECT
    b.period_type,
    b.store_no,
    b.menu_no,
    COUNT(*) AS order_item_cnt,
    COUNT(DISTINCT b.order_id) AS order_cnt,
    COUNT(DISTINCT b.deal_id) AS deal_cnt,
    SUM(b.product_count) AS qty,
    SUM(b.total_price) AS sales
  FROM base b
  WHERE b.period_type IS NOT NULL
  GROUP BY 1,2,3
),

totals AS (
  SELECT
    a.period_type,
    a.store_no,
    SUM(a.sales) AS total_sales
  FROM agg a
  GROUP BY 1,2
),

scored AS (
  SELECT
    a.*,
    percent_rank() OVER (PARTITION BY a.period_type, a.store_no ORDER BY a.order_cnt) * 100 AS sales_score,
    percent_rank() OVER (PARTITION BY a.period_type, a.store_no ORDER BY a.sales) * 100 AS revenue_score
  FROM agg a
),

labeled AS (
  SELECT
    s.*,
    CASE
      WHEN s.revenue_score >= 80 AND s.sales_score >= 70 THEN '핵심 매출 메뉴'
      WHEN s.sales_score <= 20 AND s.revenue_score <= 20 THEN '부진 메뉴'
      ELSE '일반 메뉴'
    END AS primary_role
  FROM scored s
),

pivoted AS (
  SELECT
    l.store_no,
    l.menu_no,

    MAX(CASE WHEN l.period_type = 'this' THEN l.order_item_cnt END) AS this_order_item_cnt,
    MAX(CASE WHEN l.period_type = 'prev' THEN l.order_item_cnt END) AS prev_order_item_cnt,

    MAX(CASE WHEN l.period_type = 'this' THEN l.order_cnt END) AS this_order_cnt,
    MAX(CASE WHEN l.period_type = 'prev' THEN l.order_cnt END) AS prev_order_cnt,

    MAX(CASE WHEN l.period_type = 'this' THEN l.deal_cnt END) AS this_deal_cnt,
    MAX(CASE WHEN l.period_type = 'prev' THEN l.deal_cnt END) AS prev_deal_cnt,

    MAX(CASE WHEN l.period_type = 'this' THEN l.qty END) AS this_qty,
    MAX(CASE WHEN l.period_type = 'prev' THEN l.qty END) AS prev_qty,

    MAX(CASE WHEN l.period_type = 'this' THEN l.sales END) AS this_sales,
    MAX(CASE WHEN l.period_type = 'prev' THEN l.sales END) AS prev_sales,

    MAX(CASE WHEN l.period_type = 'this' THEN l.sales_score END) AS this_sales_score,
    MAX(CASE WHEN l.period_type = 'this' THEN l.revenue_score END) AS this_revenue_score,

    MAX(CASE WHEN l.period_type = 'this' THEN l.primary_role END) AS primary_role
  FROM labeled l
  GROUP BY l.store_no, l.menu_no
)

SELECT
  pv.store_no,
  pv.menu_no,
  mi.menu_nm,
  mi.category_no,
  mi.main_category_no,
  mi.menu_type,
  mi.menu_product_type,
  mi.best_menu_yn,
  mp.menu_price,

  pv.primary_role,

  pv.this_order_item_cnt,
  pv.prev_order_item_cnt,
  COALESCE(pv.this_order_item_cnt, 0) - COALESCE(pv.prev_order_item_cnt, 0) AS diff_order_item_cnt,
  CASE
    WHEN COALESCE(pv.prev_order_item_cnt, 0) > 0
      THEN ROUND(((pv.this_order_item_cnt - pv.prev_order_item_cnt)::numeric / pv.prev_order_item_cnt) * 100, 2)
    ELSE NULL
  END AS diff_order_item_cnt_pct,

  pv.this_order_cnt,
  pv.prev_order_cnt,
  COALESCE(pv.this_order_cnt, 0) - COALESCE(pv.prev_order_cnt, 0) AS diff_order_cnt,
  CASE
    WHEN COALESCE(pv.prev_order_cnt, 0) > 0
      THEN ROUND(((pv.this_order_cnt - pv.prev_order_cnt)::numeric / pv.prev_order_cnt) * 100, 2)
    ELSE NULL
  END AS diff_order_cnt_pct,

  pv.this_deal_cnt,
  pv.prev_deal_cnt,
  COALESCE(pv.this_deal_cnt, 0) - COALESCE(pv.prev_deal_cnt, 0) AS diff_deal_cnt,
  CASE
    WHEN COALESCE(pv.prev_deal_cnt, 0) > 0
      THEN ROUND(((pv.this_deal_cnt - pv.prev_deal_cnt)::numeric / pv.prev_deal_cnt) * 100, 2)
    ELSE NULL
  END AS diff_deal_cnt_pct,

  pv.this_qty,
  pv.prev_qty,
  COALESCE(pv.this_qty, 0) - COALESCE(pv.prev_qty, 0) AS diff_qty,
  CASE
    WHEN COALESCE(pv.prev_qty, 0) > 0
      THEN ROUND(((pv.this_qty - pv.prev_qty)::numeric / pv.prev_qty) * 100, 2)
    ELSE NULL
  END AS diff_qty_pct,

  pv.this_sales,
  pv.prev_sales,
  COALESCE(pv.this_sales, 0) - COALESCE(pv.prev_sales, 0) AS diff_sales,
  CASE
    WHEN COALESCE(pv.prev_sales, 0) > 0
      THEN ROUND(((pv.this_sales - pv.prev_sales)::numeric / pv.prev_sales) * 100, 2)
    ELSE NULL
  END AS diff_sales_pct,

  CASE
    WHEN COALESCE(t.total_sales, 0) > 0
      THEN ROUND((pv.this_sales::numeric / t.total_sales) * 100, 2)
    ELSE 0
  END AS this_sales_share_pct,

  ROUND(COALESCE(pv.this_sales_score, 0)::numeric, 1) AS this_sales_score,
  ROUND(COALESCE(pv.this_revenue_score, 0)::numeric, 1) AS this_revenue_score

FROM pivoted pv
JOIN menu_info mi
  ON mi.store_no = pv.store_no
 AND mi.menu_no  = pv.menu_no
LEFT JOIN menu_price mp
  ON mp.store_no = pv.store_no
 AND mp.menu_no  = pv.menu_no
LEFT JOIN totals t
  ON t.period_type = 'this'
 AND t.store_no = pv.store_no
WHERE COALESCE(pv.this_order_cnt, 0) > 0
ORDER BY pv.this_sales DESC, pv.this_order_cnt DESC, pv.menu_no;