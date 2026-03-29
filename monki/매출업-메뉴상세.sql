WITH p AS (
  SELECT
    :store_no::bigint         AS store_no,
    :menu_no::bigint          AS menu_no,
    :base_date::date          AS base_date,
    lower(:period)::text      AS period
),

base_window AS (
  SELECT
    store_no,
    menu_no,
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
    menu_no,
    period,
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM (prev_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_to_utc
  FROM base_window
),

menu_info AS (
  SELECT
    m.store_no,
    m.menu_no,
    m.menu_nm,
    m.category_no,
    m.main_category_no,
    m.menu_type,
    m.menu_product_type,
    COALESCE(m.best_menu_yn, false) AS best_menu_yn,
    mp.menu_price
  FROM public.tb_menu m
  LEFT JOIN public.tb_menu_price mp
    ON mp.menu_no = m.menu_no
  JOIN p
    ON p.store_no = m.store_no
   AND p.menu_no  = m.menu_no
),

valid_orders AS (
  SELECT
    d.store_no,
    d.deal_id,
    o.order_id,
    o.user_no
  FROM pos.tb_deal d
  JOIN pos.tb_deal_order o
    ON o.store_no = d.store_no
   AND o.deal_id = d.deal_id
   AND o.deleted_yn = false
  JOIN p
    ON p.store_no = d.store_no
  WHERE d.deleted_yn = false
    AND o.order_status = 'OPRS_006'
),

item_base AS (
  SELECT
    doi.store_no,
    doi.deal_id,
    doi.order_id,
    vo.user_no,
    doi.menu_no,
    doi.option_no,
    doi.reg_dt,
    COALESCE(doi.product_count, 0) AS product_count,
    COALESCE(doi.total_price, 0) AS total_price,
    CASE
      WHEN doi.reg_dt >= tz.this_from_utc AND doi.reg_dt < tz.this_to_utc THEN 'this'
      WHEN doi.reg_dt >= tz.prev_from_utc AND doi.reg_dt < tz.prev_to_utc THEN 'prev'
      ELSE NULL
    END AS period_type
  FROM pos.tb_deal_order_item doi
  JOIN valid_orders vo
    ON vo.store_no = doi.store_no
   AND vo.deal_id  = doi.deal_id
   AND vo.order_id = doi.order_id
  JOIN tz
    ON tz.store_no = doi.store_no
  WHERE doi.store_no = tz.store_no
    AND doi.deleted_yn = false
    AND doi.order_item_status = 'OPRS_006'
    AND doi.reg_dt >= tz.prev_from_utc
    AND doi.reg_dt <  tz.this_to_utc
),

target_menu AS (
  SELECT ib.*
  FROM item_base ib
  JOIN p
    ON p.store_no = ib.store_no
   AND p.menu_no  = ib.menu_no
  WHERE ib.period_type IS NOT NULL
),

summary_by_period AS (
  SELECT
    period_type,
    COUNT(*) AS order_item_cnt,
    COUNT(DISTINCT order_id) AS order_cnt,
    COUNT(DISTINCT deal_id) AS deal_cnt,
    SUM(product_count) AS qty,
    SUM(total_price) AS sales,
    AVG(CASE WHEN option_no IS NOT NULL THEN 1.0 ELSE 0.0 END) AS direct_option_attach_rate
  FROM target_menu
  GROUP BY 1
),

summary_pivot AS (
  SELECT
    MAX(CASE WHEN period_type = 'this' THEN order_item_cnt END) AS this_order_item_cnt,
    MAX(CASE WHEN period_type = 'prev' THEN order_item_cnt END) AS prev_order_item_cnt,
    MAX(CASE WHEN period_type = 'this' THEN order_cnt END) AS this_order_cnt,
    MAX(CASE WHEN period_type = 'prev' THEN order_cnt END) AS prev_order_cnt,
    MAX(CASE WHEN period_type = 'this' THEN deal_cnt END) AS this_deal_cnt,
    MAX(CASE WHEN period_type = 'prev' THEN deal_cnt END) AS prev_deal_cnt,
    MAX(CASE WHEN period_type = 'this' THEN qty END) AS this_qty,
    MAX(CASE WHEN period_type = 'prev' THEN qty END) AS prev_qty,
    MAX(CASE WHEN period_type = 'this' THEN sales END) AS this_sales,
    MAX(CASE WHEN period_type = 'prev' THEN sales END) AS prev_sales,
    MAX(CASE WHEN period_type = 'this' THEN direct_option_attach_rate END) AS this_direct_option_attach_rate,
    MAX(CASE WHEN period_type = 'prev' THEN direct_option_attach_rate END) AS prev_direct_option_attach_rate
  FROM summary_by_period
),

trend_daily AS (
  SELECT
    timezone('Asia/Seoul', to_timestamp(reg_dt))::date AS biz_date,
    COUNT(DISTINCT order_id) AS order_cnt,
    SUM(product_count) AS qty,
    SUM(total_price) AS sales
  FROM target_menu
  WHERE period_type = 'this'
  GROUP BY 1
),

trend_json AS (
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'date', biz_date,
        'orders', order_cnt,
        'qty', qty,
        'sales', sales
      )
      ORDER BY biz_date
    ) AS sales_trend
  FROM trend_daily
),

bundle_top5 AS (
  SELECT
    x.paired_menu_no,
    x.paired_menu_nm,
    x.order_cnt
  FROM (
    SELECT
      b.menu_no AS paired_menu_no,
      m.menu_nm AS paired_menu_nm,
      COUNT(DISTINCT a.order_id) AS order_cnt,
      ROW_NUMBER() OVER (
        ORDER BY COUNT(DISTINCT a.order_id) DESC, m.menu_nm
      ) AS rn
    FROM target_menu a
    JOIN item_base b
      ON b.period_type = a.period_type
     AND b.store_no    = a.store_no
     AND b.order_id    = a.order_id
     AND b.menu_no    <> a.menu_no
    JOIN public.tb_menu m
      ON m.store_no = b.store_no
     AND m.menu_no  = b.menu_no
    WHERE a.period_type = 'this'
    GROUP BY 1,2
  ) x
  WHERE x.rn <= 5
),

bundle_json AS (
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'menu_no', paired_menu_no,
        'menu_nm', paired_menu_nm,
        'order_cnt', order_cnt
      )
      ORDER BY order_cnt DESC, paired_menu_nm
    ) AS top5_bundle_menus
  FROM bundle_top5
),

first_buy_per_user AS (
  SELECT
    period_type,
    user_no,
    MIN(reg_dt) AS first_reg_dt
  FROM item_base
  WHERE user_no IS NOT NULL
    AND period_type IS NOT NULL
  GROUP BY 1,2
),

entry_ratio AS (
  SELECT
    COUNT(DISTINCT t.user_no) AS buyer_cnt,
    COUNT(DISTINCT CASE WHEN f.first_reg_dt = t.reg_dt THEN t.user_no END) AS first_buy_user_cnt
  FROM target_menu t
  LEFT JOIN first_buy_per_user f
    ON f.period_type = t.period_type
   AND f.user_no     = t.user_no
  WHERE t.period_type = 'this'
    AND t.user_no IS NOT NULL
),

buy_user_dates AS (
  SELECT DISTINCT
    t.user_no,
    timezone('Asia/Seoul', to_timestamp(t.reg_dt))::date AS buy_date
  FROM target_menu t
  WHERE t.period_type = 'this'
    AND t.user_no IS NOT NULL
),

retention_30d AS (
  SELECT
    COUNT(DISTINCT bud.user_no) AS bought_user_cnt,
    COUNT(DISTINCT uv.user_id) AS retained_30d_user_cnt
  FROM buy_user_dates bud
  LEFT JOIN table_order.user_visit uv
    ON uv.store_no = (SELECT store_no FROM p)
   AND uv.user_id::text = bud.user_no::text
   AND uv.deleted_at IS NULL
   AND uv.visit_date > bud.buy_date
   AND uv.visit_date <= bud.buy_date + 30
)

SELECT
  mi.store_no,
  mi.menu_no,
  mi.menu_nm,
  mi.category_no,
  mi.main_category_no,
  mi.menu_type,
  mi.menu_product_type,
  mi.best_menu_yn,
  mi.menu_price,

  sp.this_order_item_cnt,
  sp.prev_order_item_cnt,
  COALESCE(sp.this_order_item_cnt, 0) - COALESCE(sp.prev_order_item_cnt, 0) AS diff_order_item_cnt,
  CASE
    WHEN COALESCE(sp.prev_order_item_cnt, 0) > 0
      THEN ROUND(((sp.this_order_item_cnt - sp.prev_order_item_cnt)::numeric / sp.prev_order_item_cnt) * 100, 2)
    ELSE NULL
  END AS diff_order_item_cnt_pct,

  sp.this_order_cnt,
  sp.prev_order_cnt,
  COALESCE(sp.this_order_cnt, 0) - COALESCE(sp.prev_order_cnt, 0) AS diff_order_cnt,
  CASE
    WHEN COALESCE(sp.prev_order_cnt, 0) > 0
      THEN ROUND(((sp.this_order_cnt - sp.prev_order_cnt)::numeric / sp.prev_order_cnt) * 100, 2)
    ELSE NULL
  END AS diff_order_cnt_pct,

  sp.this_deal_cnt,
  sp.prev_deal_cnt,
  COALESCE(sp.this_deal_cnt, 0) - COALESCE(sp.prev_deal_cnt, 0) AS diff_deal_cnt,
  CASE
    WHEN COALESCE(sp.prev_deal_cnt, 0) > 0
      THEN ROUND(((sp.this_deal_cnt - sp.prev_deal_cnt)::numeric / sp.prev_deal_cnt) * 100, 2)
    ELSE NULL
  END AS diff_deal_cnt_pct,

  sp.this_qty,
  sp.prev_qty,
  COALESCE(sp.this_qty, 0) - COALESCE(sp.prev_qty, 0) AS diff_qty,
  CASE
    WHEN COALESCE(sp.prev_qty, 0) > 0
      THEN ROUND(((sp.this_qty - sp.prev_qty)::numeric / sp.prev_qty) * 100, 2)
    ELSE NULL
  END AS diff_qty_pct,

  sp.this_sales,
  sp.prev_sales,
  COALESCE(sp.this_sales, 0) - COALESCE(sp.prev_sales, 0) AS diff_sales,
  CASE
    WHEN COALESCE(sp.prev_sales, 0) > 0
      THEN ROUND(((sp.this_sales - sp.prev_sales)::numeric / sp.prev_sales) * 100, 2)
    ELSE NULL
  END AS diff_sales_pct,

  ROUND((COALESCE(sp.this_direct_option_attach_rate, 0) * 100)::numeric, 2) AS this_direct_option_attach_rate_pct,
  ROUND((COALESCE(sp.prev_direct_option_attach_rate, 0) * 100)::numeric, 2) AS prev_direct_option_attach_rate_pct,
  ROUND(((COALESCE(sp.this_direct_option_attach_rate, 0) - COALESCE(sp.prev_direct_option_attach_rate, 0)) * 100)::numeric, 2) AS diff_direct_option_attach_rate_pp,

  CASE
    WHEN COALESCE(er.buyer_cnt, 0) > 0
      THEN ROUND((er.first_buy_user_cnt::numeric / er.buyer_cnt) * 100, 2)
    ELSE 0
  END AS this_first_buy_ratio_pct,

  CASE
    WHEN COALESCE(r.bought_user_cnt, 0) > 0
      THEN ROUND((r.retained_30d_user_cnt::numeric / r.bought_user_cnt) * 100, 2)
    ELSE 0
  END AS this_retention_30d_rate_pct,

  tj.sales_trend,
  bj.top5_bundle_menus

FROM menu_info mi
CROSS JOIN summary_pivot sp
CROSS JOIN trend_json tj
CROSS JOIN bundle_json bj
CROSS JOIN entry_ratio er
CROSS JOIN retention_30d r;