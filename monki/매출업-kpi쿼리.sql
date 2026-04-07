WITH p AS (
  SELECT
    :store_no::bigint    AS store_no,
    :base_date::date     AS base_date,
    lower(:period::text) AS period
),

base_window AS (
  SELECT
    store_no,
    period,
    base_date,

    CASE
      WHEN period = 'day'     THEN base_date
      WHEN period = 'weekday' THEN base_date
      WHEN period = 'week'    THEN (base_date - interval '6 day')::date
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN date_trunc('month', base_date)::date
      WHEN period = 'mtdhms'  THEN date_trunc('month', base_date)::date
      ELSE base_date
    END AS this_from_kst,

    CASE
      WHEN period = 'mtdhms' THEN
        base_date::timestamp + (now() AT TIME ZONE 'Asia/Seoul')::time
      WHEN period = 'mtd' THEN
        (base_date + interval '1 day')::timestamp
      ELSE
        (base_date + interval '1 day')::timestamp
    END AS this_to_kst,

    CASE
      WHEN period = 'day'     THEN (base_date - interval '1 day')::date
      WHEN period = 'weekday' THEN (base_date - interval '7 day')::date
      WHEN period = 'week'    THEN (base_date - interval '13 day')::date
      WHEN period = 'month'   THEN (base_date - interval '2 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '6 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN (date_trunc('month', base_date) - interval '1 month')::date
      WHEN period = 'mtdhms'  THEN (date_trunc('month', base_date) - interval '1 month')::date
      ELSE (base_date - interval '1 day')::date
    END AS prev_from_kst,

    CASE
      WHEN period = 'day'     THEN base_date::timestamp
      WHEN period = 'weekday' THEN (base_date - interval '6 day')::timestamp
      WHEN period = 'week'    THEN (base_date - interval '6 day')::timestamp
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::timestamp
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::timestamp

      WHEN period = 'mtd' THEN
        CASE
          WHEN base_date = (
            (date_trunc('month', base_date) + interval '1 month')::date
            - interval '1 day'
          )::date
          THEN date_trunc('month', base_date)::timestamp
          ELSE (
            (date_trunc('month', base_date) - interval '1 month')::date
            + (base_date - date_trunc('month', base_date)::date + 1)
          )::timestamp
        END

      WHEN period = 'mtdhms' THEN
        LEAST(
          (
            (date_trunc('month', base_date) - interval '1 month')::date
            + (base_date - date_trunc('month', base_date)::date)
          )::timestamp
          + (now() AT TIME ZONE 'Asia/Seoul')::time,
          date_trunc('month', base_date)::timestamp
        )

      ELSE base_date::timestamp
    END AS prev_to_kst
  FROM p
),

tz AS (
  SELECT
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM (prev_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_to_utc,
    store_no,
    this_from_kst,
    this_to_kst,
    prev_from_kst,
    prev_to_kst
  FROM base_window
),

dl_filt AS (
  SELECT
    dl.deal_id,
    dl.reg_dt,
    dl.store_no,
    COALESCE(dl.number_of_adult, 0)::bigint AS adult_cnt
  FROM tz
  JOIN pos.tb_deal dl
    ON dl.store_no    = tz.store_no
   AND dl.deal_status = 'OPRS_006'
   AND dl.reg_dt >= tz.prev_from_utc
   AND dl.reg_dt <  tz.this_to_utc
),

guest_deals AS (
  SELECT
    d.deal_id,
    d.reg_dt,
    d.store_no,
    d.adult_cnt
  FROM dl_filt d
  WHERE NOT EXISTS (
    SELECT 1
    FROM table_order.user_points up
    WHERE up.store_no    = d.store_no
      AND up.deal_id     = d.deal_id
      AND up.change_type = 'ACCUMULATE'
  )
),

deal_amounts AS (
  SELECT
    doi.store_no,
    doi.deal_id,
    SUM(doi.total_price)::bigint AS order_amount
  FROM pos.tb_deal_order_item doi
  JOIN guest_deals gd
    ON gd.deal_id  = doi.deal_id
   AND gd.store_no = doi.store_no
  WHERE doi.order_item_status = 'OPRS_006'
  GROUP BY doi.store_no, doi.deal_id
),

agg AS (
  SELECT
    SUM(gd.adult_cnt) FILTER (
      WHERE gd.reg_dt >= tz.this_from_utc
        AND gd.reg_dt <  tz.this_to_utc
    ) AS this_people,

    SUM(gd.adult_cnt) FILTER (
      WHERE gd.reg_dt >= tz.prev_from_utc
        AND gd.reg_dt <  tz.prev_to_utc
    ) AS prev_people,

    COUNT(DISTINCT gd.deal_id) FILTER (
      WHERE gd.reg_dt >= tz.this_from_utc
        AND gd.reg_dt <  tz.this_to_utc
    ) AS this_guest_deals,

    COUNT(DISTINCT gd.deal_id) FILTER (
      WHERE gd.reg_dt >= tz.prev_from_utc
        AND gd.reg_dt <  tz.prev_to_utc
    ) AS prev_guest_deals,

    SUM(da.order_amount) FILTER (
      WHERE gd.reg_dt >= tz.this_from_utc
        AND gd.reg_dt <  tz.this_to_utc
    ) AS this_sales,

    SUM(da.order_amount) FILTER (
      WHERE gd.reg_dt >= tz.prev_from_utc
        AND gd.reg_dt <  tz.prev_to_utc
    ) AS prev_sales
  FROM guest_deals gd
  JOIN deal_amounts da
    ON da.deal_id  = gd.deal_id
   AND da.store_no = gd.store_no
  CROSS JOIN tz
)

SELECT
  to_char(tz.this_from_kst, 'YYYY-MM-DD HH24:MI:SS') AS this_from_kst,
  to_char(tz.this_to_kst  , 'YYYY-MM-DD HH24:MI:SS') AS this_to_kst,
  to_char(tz.prev_from_kst, 'YYYY-MM-DD HH24:MI:SS') AS prev_from_kst,
  to_char(tz.prev_to_kst  , 'YYYY-MM-DD HH24:MI:SS') AS prev_to_kst,

  a.this_sales,
  a.this_people,
  a.this_guest_deals,

  a.prev_sales,
  a.prev_people,
  a.prev_guest_deals,

  -- 평균은 people이 아니라 guest_deals 기준
  ROUND(a.this_sales::numeric / NULLIF(a.this_guest_deals, 0), 2) AS this_guest_avg,
  ROUND(a.prev_sales::numeric / NULLIF(a.prev_guest_deals, 0), 2) AS prev_guest_avg,

  ROUND(
    CASE
      WHEN NULLIF(a.prev_sales::numeric / NULLIF(a.prev_guest_deals, 0), 0) IS NULL
      THEN NULL
      ELSE (
        (a.this_sales::numeric / NULLIF(a.this_guest_deals, 0)) /
        (a.prev_sales::numeric / NULLIF(a.prev_guest_deals, 0)) - 1
      ) * 100
    END
  , 2) AS guest_avg_delta_pct

FROM tz
CROSS JOIN agg a;