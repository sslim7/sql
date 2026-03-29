-- 실별률 추이
-- store_no,base_date,period(day,week,month,quarter,mtd)
WITH p AS (
  SELECT
    :store_no::bigint AS store_no,
    :base_date::date  AS base_date,
    lower(:period)::text AS period
),

base_window AS (
  SELECT
    store_no,
    period,
    base_date,

    CASE
      WHEN period = 'day'     THEN base_date
      WHEN period = 'week'    THEN (base_date - interval '6 day')::date
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN date_trunc('month', base_date)::date
    END AS this_from_kst,

    (base_date + interval '1 day')::timestamp AS this_to_kst
  FROM p
),

tz AS MATERIALIZED (
  SELECT
    store_no,
    period,
    this_from_kst,
    this_to_kst,
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc
  FROM base_window
),

base_deals AS MATERIALIZED (
  SELECT
    d.deal_id,
    (to_timestamp(d.reg_dt) AT TIME ZONE 'Asia/Seoul')::date AS biz_date,
    MAX(CASE WHEN up.user_id IS NOT NULL THEN 1 ELSE 0 END) AS is_member
  FROM pos.tb_deal d
  LEFT JOIN table_order.user_points up
    ON up.deal_id = d.deal_id
  JOIN tz
    ON d.store_no = tz.store_no
  WHERE d.deal_status = 'OPRS_006'
    AND d.reg_dt >= tz.this_from_utc
    AND d.reg_dt <  tz.this_to_utc
  GROUP BY 1, 2
),

daily_agg AS (
  SELECT
    biz_date,
    COUNT(*) FILTER (WHERE is_member = 1) AS member_orders,
    COUNT(*) AS total_orders
  FROM base_deals
  GROUP BY 1
)

SELECT
  biz_date,
  member_orders,
  total_orders,
  ROUND(
    100.0 * member_orders::numeric / NULLIF(total_orders, 0),
    1
  ) AS identification_rate
FROM daily_agg
WHERE total_orders > 0
ORDER BY biz_date;


-- 식별률 (점심,저녁,주말,주중)
WITH p AS (
  SELECT
    :store_no::bigint AS store_no,
    :base_date::date  AS base_date,
    lower(:period)::text AS period
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
    END AS this_from_kst,

    (base_date + interval '1 day')::timestamp AS this_to_kst,

    CASE
      WHEN period = 'day'     THEN (base_date - interval '1 day')::date
      WHEN period = 'weekday' THEN (base_date - interval '7 day')::date
      WHEN period = 'week'    THEN (base_date - interval '13 day')::date
      WHEN period = 'month'   THEN (base_date - interval '2 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '6 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN (date_trunc('month', base_date) - interval '1 month')::date
    END AS prev_from_kst,

    CASE
      WHEN period = 'day'     THEN base_date::timestamp
      WHEN period = 'weekday' THEN (base_date - interval '6 day')::timestamp
      WHEN period = 'week'    THEN (base_date - interval '6 day')::timestamp
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::timestamp
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::timestamp

      WHEN period = 'mtd' THEN
        (
          LEAST(
            (
              (date_trunc('month', base_date) - interval '1 month')::date
              + (EXTRACT(DAY FROM base_date)::int - 1)
            )::date,
            (date_trunc('month', base_date)::date - interval '1 day')::date
          )
        )::timestamp
    END AS prev_to_kst
  FROM p
),

tz AS MATERIALIZED (
  SELECT
    store_no,
    period,
    this_from_kst,
    this_to_kst,
    prev_from_kst,
    prev_to_kst,
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM ((prev_to_kst + interval '1 day') AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_to_utc
  FROM base_window
),

base_deals AS MATERIALIZED (
  SELECT
    d.deal_id,
    CASE
      WHEN d.reg_dt >= tz.this_from_utc AND d.reg_dt < tz.this_to_utc THEN 'this'
      WHEN d.reg_dt >= tz.prev_from_utc AND d.reg_dt < tz.prev_to_utc THEN 'prev'
    END AS period_type,
    (to_timestamp(d.reg_dt) AT TIME ZONE 'Asia/Seoul') AS reg_kst,
    MAX(CASE WHEN up.user_id IS NOT NULL THEN 1 ELSE 0 END) AS is_member
  FROM pos.tb_deal d
  LEFT JOIN table_order.user_points up
    ON up.deal_id = d.deal_id
  JOIN tz
    ON d.store_no = tz.store_no
  WHERE d.deal_status = 'OPRS_006'
    AND (
      (d.reg_dt >= tz.this_from_utc AND d.reg_dt < tz.this_to_utc)
      OR
      (d.reg_dt >= tz.prev_from_utc AND d.reg_dt < tz.prev_to_utc)
    )
  GROUP BY 1, 2, 3
),

segmented AS (
  SELECT
    b.period_type,
    s.segment_type,
    s.segment_key,
    b.is_member
  FROM base_deals b
  CROSS JOIN LATERAL (
    VALUES
      (
        'meal'::text,
        CASE WHEN b.reg_kst::time < time '16:00' THEN 'lunch' ELSE 'dinner' END
      ),
      (
        'day_type'::text,
        CASE WHEN EXTRACT(ISODOW FROM b.reg_kst) IN (6, 7) THEN 'weekend' ELSE 'weekday' END
      )
  ) AS s(segment_type, segment_key)
),

agg AS (
  SELECT
    period_type,
    segment_type,
    segment_key,
    COUNT(*) FILTER (WHERE is_member = 1) AS member_orders,
    COUNT(*) AS total_orders
  FROM segmented
  GROUP BY 1, 2, 3
)

SELECT
  period_type,
  segment_type,
  segment_key,
  member_orders,
  total_orders,
  ROUND(100.0 * member_orders::numeric / NULLIF(total_orders, 0), 1) AS identification_rate
FROM agg
WHERE total_orders > 0
ORDER BY
  period_type,
  CASE segment_type WHEN 'meal' THEN 1 ELSE 2 END,
  CASE segment_key
    WHEN 'lunch' THEN 1
    WHEN 'dinner' THEN 2
    WHEN 'weekday' THEN 3
    WHEN 'weekend' THEN 4
    ELSE 99
  END;

-- 식별률 시간대별
WITH p AS (
  SELECT
    :store_no::bigint AS store_no,
    :base_date::date  AS base_date,
    lower(:period)::text AS period
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
    END AS this_from_kst,

    (base_date + interval '1 day')::timestamp AS this_to_kst,

    CASE
      WHEN period = 'day'     THEN (base_date - interval '1 day')::date
      WHEN period = 'weekday' THEN (base_date - interval '7 day')::date
      WHEN period = 'week'    THEN (base_date - interval '13 day')::date
      WHEN period = 'month'   THEN (base_date - interval '2 month' + interval '1 day')::date
      WHEN period = 'quarter' THEN (base_date - interval '6 month' + interval '1 day')::date
      WHEN period = 'mtd'     THEN (date_trunc('month', base_date) - interval '1 month')::date
    END AS prev_from_kst,

    CASE
      WHEN period = 'day'     THEN base_date::timestamp
      WHEN period = 'weekday' THEN (base_date - interval '6 day')::timestamp
      WHEN period = 'week'    THEN (base_date - interval '6 day')::timestamp
      WHEN period = 'month'   THEN (base_date - interval '1 month' + interval '1 day')::timestamp
      WHEN period = 'quarter' THEN (base_date - interval '3 month' + interval '1 day')::timestamp

      WHEN period = 'mtd' THEN
        (
          LEAST(
            (
              (date_trunc('month', base_date) - interval '1 month')::date
              + (EXTRACT(DAY FROM base_date)::int - 1)
            )::date,
            (date_trunc('month', base_date)::date - interval '1 day')::date
          )
        )::timestamp
    END AS prev_to_kst
  FROM p
),

tz AS MATERIALIZED (
  SELECT
    store_no,
    period,
    this_from_kst,
    this_to_kst,
    prev_from_kst,
    prev_to_kst,
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM ((prev_to_kst + interval '1 day') AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_to_utc
  FROM base_window
),

base_deals AS MATERIALIZED (
  SELECT
    d.deal_id,
    CASE
      WHEN d.reg_dt >= tz.this_from_utc AND d.reg_dt < tz.this_to_utc THEN 'this'
      WHEN d.reg_dt >= tz.prev_from_utc AND d.reg_dt < tz.prev_to_utc THEN 'prev'
    END AS period_type,
    EXTRACT(HOUR FROM (to_timestamp(d.reg_dt) AT TIME ZONE 'Asia/Seoul'))::int AS hour_of_day,
    MAX(CASE WHEN up.user_id IS NOT NULL THEN 1 ELSE 0 END) AS is_member
  FROM pos.tb_deal d
  LEFT JOIN table_order.user_points up
    ON up.deal_id = d.deal_id
  JOIN tz
    ON d.store_no = tz.store_no
  WHERE d.deal_status = 'OPRS_006'
    AND (
      (d.reg_dt >= tz.this_from_utc AND d.reg_dt < tz.this_to_utc)
      OR
      (d.reg_dt >= tz.prev_from_utc AND d.reg_dt < tz.prev_to_utc)
    )
  GROUP BY 1, 2, 3
),

agg AS (
  SELECT
    period_type,
    hour_of_day,
    COUNT(*) FILTER (WHERE is_member = 1) AS member_orders,
    COUNT(*) AS total_orders
  FROM base_deals
  GROUP BY 1, 2
)

SELECT
  period_type,
  hour_of_day,
  member_orders,
  total_orders,
  ROUND(100.0 * member_orders::numeric / NULLIF(total_orders, 0), 1) AS identification_rate
FROM agg
WHERE total_orders > 0
ORDER BY period_type, hour_of_day;

select * from public.tb_store where tb_store.table_order_yn=true;
store_no=824;
select * from public.tb_store_config sc join public.tb_store st on sc.store_no=st.store_no where st.order_type_yn1=true and config_group = 'order_settings';

select * from public.tb_code where code_id='ST_005';

select * from public.tb_store