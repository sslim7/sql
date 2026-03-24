explain
WITH p AS (
  SELECT
    :base_date::date         AS base_date,
    lower(:period)::text     AS period,
    lower(:store_type)::text AS store_type
),

base_window AS (
  SELECT
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
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM (prev_to_kst  ::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS prev_to_utc
  FROM base_window
),

store_filter AS MATERIALIZED (
  SELECT s.store_no
  FROM public.tb_store s
  WHERE
    (SELECT store_type FROM p) = 'all'

    OR (
      (SELECT store_type FROM p) = 'su-no'
      AND NOT EXISTS (
        SELECT 1 FROM sellup.basic_info bi
        WHERE bi.store_no = s.store_no
          AND bi.is_active = true
      )
    )

    OR (
      (SELECT store_type FROM p) = 'su-all'
      AND EXISTS (
        SELECT 1 FROM sellup.basic_info bi
        WHERE bi.store_no = s.store_no
          AND bi.is_active = true
      )
    )

    OR (
      (SELECT store_type FROM p) = 'su-auto'
      AND EXISTS (
        SELECT 1 FROM sellup.apilot_config_store acs
        WHERE acs.store_no = s.store_no
          AND acs.is_auto_pilot = true
      )
    )
),

visitors AS MATERIALIZED (
  SELECT
    dl.store_no,
    COALESCE(SUM(GREATEST(COALESCE(dl.number_of_adult, 1), 1)) FILTER (
      WHERE dl.reg_dt >= tz.this_from_utc
        AND dl.reg_dt <  tz.this_to_utc
        AND dl.deal_status = 'OPRS_006'
    ), 0)::bigint AS this_visitors,
    COALESCE(SUM(GREATEST(COALESCE(dl.number_of_adult, 1), 1)) FILTER (
      WHERE dl.reg_dt >= tz.prev_from_utc
        AND dl.reg_dt <  tz.prev_to_utc
    ), 0)::bigint AS prev_visitors
  FROM pos.tb_deal dl
  CROSS JOIN tz
  WHERE dl.reg_dt >= tz.prev_from_utc
    AND dl.reg_dt <  tz.this_to_utc
  GROUP BY dl.store_no
)

SELECT
  s.store_no,
  s.store_nm
  || CASE WHEN MAX(acs.store_no) IS NOT NULL THEN ' 🚀' ELSE '' END
  || CASE WHEN MAX(bi.store_no)  IS NOT NULL THEN ' 👀' ELSE '' END
  AS store_nm,

  -- 매출
  COALESCE(SUM(doi.total_price) FILTER (
    WHERE doi.reg_dt >= tz.this_from_utc
      AND doi.reg_dt <  tz.this_to_utc
  ), 0)::bigint AS this_sales,

  COALESCE(SUM(doi.total_price) FILTER (
    WHERE doi.reg_dt >= tz.prev_from_utc
      AND doi.reg_dt <  tz.prev_to_utc
  ), 0)::bigint AS prev_sales,

  -- 매출 증감률 (%)
  ROUND(
    CASE
      WHEN COALESCE(SUM(doi.total_price) FILTER (
             WHERE doi.reg_dt >= tz.prev_from_utc
               AND doi.reg_dt <  tz.prev_to_utc
           ), 0) = 0
      THEN NULL
      ELSE
        (
          COALESCE(SUM(doi.total_price) FILTER (
            WHERE doi.reg_dt >= tz.this_from_utc
              AND doi.reg_dt <  tz.this_to_utc
          ), 0)::numeric
          -
          COALESCE(SUM(doi.total_price) FILTER (
            WHERE doi.reg_dt >= tz.prev_from_utc
              AND doi.reg_dt <  tz.prev_to_utc
          ), 0)::numeric
        )
        /
        COALESCE(SUM(doi.total_price) FILTER (
          WHERE doi.reg_dt >= tz.prev_from_utc
            AND doi.reg_dt <  tz.prev_to_utc
        ), 0)::numeric * 100
    END,
    2
  ) AS sales_change_pct,

  -- 주문 수
  COUNT(DISTINCT doi.order_id) FILTER (
    WHERE doi.reg_dt >= tz.this_from_utc
      AND doi.reg_dt <  tz.this_to_utc
  ) AS this_orders,

  COUNT(DISTINCT doi.order_id) FILTER (
    WHERE doi.reg_dt >= tz.prev_from_utc
      AND doi.reg_dt <  tz.prev_to_utc
  ) AS prev_orders,

  -- AOV (this)
  COALESCE(
    (SUM(doi.total_price) FILTER (
       WHERE doi.reg_dt >= tz.this_from_utc
         AND doi.reg_dt <  tz.this_to_utc
     ))::numeric
    /
    NULLIF(
      COUNT(DISTINCT doi.order_id) FILTER (
        WHERE doi.reg_dt >= tz.this_from_utc
          AND doi.reg_dt <  tz.this_to_utc
      ), 0
    ),
    0
  )::numeric(18,2) AS this_aov,

  -- AOV (prev)
  COALESCE(
    (SUM(doi.total_price) FILTER (
       WHERE doi.reg_dt >= tz.prev_from_utc
         AND doi.reg_dt <  tz.prev_to_utc
     ))::numeric
    /
    NULLIF(
      COUNT(DISTINCT doi.order_id) FILTER (
        WHERE doi.reg_dt >= tz.prev_from_utc
          AND doi.reg_dt <  tz.prev_to_utc
      ), 0
    ),
    0
  )::numeric(18,2) AS prev_aov,

  -- 입장 인원수
  COALESCE(MAX(v.this_visitors), 0) AS this_visitors,
  COALESCE(MAX(v.prev_visitors), 0) AS prev_visitors

FROM pos.tb_deal_order_item doi
CROSS JOIN tz
JOIN public.tb_store s                    ON s.store_no   = doi.store_no
JOIN store_filter sf                      ON sf.store_no  = doi.store_no
LEFT JOIN visitors v                      ON v.store_no   = doi.store_no
LEFT JOIN sellup.apilot_config_store acs  ON acs.store_no = doi.store_no
                                         AND acs.is_auto_pilot = true
LEFT JOIN sellup.basic_info bi            ON bi.store_no  = doi.store_no
                                         AND bi.is_active = true
WHERE doi.order_item_status = 'OPRS_006'
  AND (
       (doi.reg_dt >= tz.this_from_utc AND doi.reg_dt < tz.this_to_utc)
    OR (doi.reg_dt >= tz.prev_from_utc AND doi.reg_dt < tz.prev_to_utc)
  )
GROUP BY s.store_no, s.store_nm
ORDER BY sales_change_pct DESC;