
--seg_lib,seg_lib_sql에 쿼리를 추가한다

INSERT INTO sellup.seg_lib (seg_lib_id, seg_code, seg_name, params_schema, target, description, ai_hint, status, tags, default_engine)
VALUES (uuid_generate_v4(), 'stores_sales_status_fc', '프렌차이즈 관리자의 매장별 영업분석', '{"type": "object", "required": ["manager_id", "base_date", "period", "store_type"], "properties": {"manager_id": {"type": "string"}, "period": {"type": "string"}, "base_date": {"type": "string", "format": "date"}, "store_type": {"type": "string"}}}', '프랜차이즈 파트너가 관리하는 매장의 특정월에 대한 캠페인이 반영된 매출지표 요약 및 캠페인별 순매출현황', '프랜차이즈 파트너가 관리하는 매장의 선택된 매장유형별 매장의 영업현황을 조회한다. 매장유형(store_type): 전체(all),매출업미사용(sellup-no),매출업매장(sellup-all),매출업파일럿매장(sellup-auto)', '{}', 'active', '{sales stores,sales,orders,aovs,visitors,members}', 'postgres');

INSERT INTO sellup.seg_lib (seg_lib_id, seg_code, seg_name, params_schema, target, description, ai_hint, status, tags, default_engine)
VALUES (uuid_generate_v4(), 'stores_sales_status_fc', '특정매장의 점심/저녁,주중/주말에 대한 매출액/주문수/객단가/방문자수 비교', '{"type": "object", "required": ["store_no", "base_date", "period"], "properties": {"period": {"enum": ["day", "weekday", "week", "month", "quarter", "mtd", "mtdhms"], "type": "string"}, "store_no": {"type": "integer"}, "base_date": {"type": "string", "format": "date"}}}', '점심/저녁, 주중/주말에 대한 매출/주문수/객단가/입장고객수',
        '조회구간의 점심/저녁,주중/주말에 대한 매출액/주문수/객단가/방문자수 비교 한다.', '{"unit": "amount", "notes": "조회구간의 점심/저녁,주중/주말에 대한 매출액/주문수/객단가/방문자수 비교 한다.", "visual": "kpi", "metrics": ["this_sales_lunch","prev_sales_lunch","this_orders_lunch","prev_orders_lunch","this_aov_lunch","prev_aov_lunch","this_visitors_lunch","prev_visitors_lunch","this_sales_dinner","prev_sales_dinner","this_orders_dinner","prev_orders_dinner","this_aov_dinner","prev_aov_dinner","this_visitors_dinner","prev_visitors_dinner","this_sales_weekdays","prev_sales_weekdays","this_orders_weekdays","prev_orders_weekdays","this_aov_weekdays","prev_aov_weekdays","this_visitors_weekdays","prev_visitors_weekdays","this_sales_weekend","prev_sales_weekend","this_orders_weekend","prev_orders_weekend","this_aov_weekend","prev_aov_weekend","this_visitors_weekend","prev_visitors_weekend"], "purpose": "dashboard_timeslop,lunch,dinner,weekdays,weekend"}',
        'active', '{dashboard_kpi,lunch,dinner,weekdays,weekend}', 'postgres');


select * from sellup.seg_lib where seg_code='ai_sales';

INSERT INTO sellup.seg_lib_sql (seg_lib_sql_id, seg_lib_id, engine, sql_base, sql_preview_override, sql_materialize_override, notes)
select uuid_generate_v4(),seg_lib_id,'postgres',e'WITH p AS (
  SELECT
    :base_date::date         AS base_date,
    lower(:period)::text     AS period,
    lower(:store_type)::text AS store_type
),

base_window AS (
  SELECT
    period,
    base_date,

    date_trunc(''month'', base_date)::date                                   AS this_month_start,
    (date_trunc(''month'', base_date) + interval ''1 month'')::date            AS next_month_start,
    ((date_trunc(''month'', base_date) + interval ''1 month'')::date
      - interval ''1 day'')::date                                            AS this_month_last_day,
    (date_trunc(''month'', base_date) - interval ''1 month'')::date            AS prev_month_start,

    CASE
      WHEN period = ''day''     THEN base_date
      WHEN period = ''weekday'' THEN base_date
      WHEN period = ''week''    THEN (base_date - interval ''6 day'')::date
      WHEN period = ''month''   THEN (base_date - interval ''1 month'' + interval ''1 day'')::date
      WHEN period = ''quarter'' THEN (base_date - interval ''3 month'' + interval ''1 day'')::date
      WHEN period = ''mtd''     THEN date_trunc(''month'', base_date)::date
      WHEN period = ''mtdhms''  THEN date_trunc(''month'', base_date)::date
    END AS this_from_kst,

    CASE
      WHEN period = ''mtdhms''  THEN base_date::timestamp
                                     + (now() AT TIME ZONE ''Asia/Seoul'')::time
      WHEN period = ''mtd''     THEN (base_date + interval ''1 day'')::timestamp
      ELSE (base_date + interval ''1 day'')::timestamp
    END AS this_to_kst,

    CASE
      WHEN period = ''day''     THEN (base_date - interval ''1 day'')::date
      WHEN period = ''weekday'' THEN (base_date - interval ''7 day'')::date
      WHEN period = ''week''    THEN (base_date - interval ''13 day'')::date
      WHEN period = ''month''   THEN (base_date - interval ''2 month'' + interval ''1 day'')::date
      WHEN period = ''quarter'' THEN (base_date - interval ''6 month'' + interval ''1 day'')::date
      WHEN period = ''mtd''     THEN (date_trunc(''month'', base_date) - interval ''1 month'')::date
      WHEN period = ''mtdhms''  THEN (date_trunc(''month'', base_date) - interval ''1 month'')::date
    END AS prev_from_kst,

    CASE
      WHEN period = ''day''     THEN base_date
      WHEN period = ''weekday'' THEN (base_date - interval ''6 day'')::date
      WHEN period = ''week''    THEN (base_date - interval ''6 day'')::date
      WHEN period = ''month''   THEN (base_date - interval ''1 month'' + interval ''1 day'')::date
      WHEN period = ''quarter'' THEN (base_date - interval ''3 month'' + interval ''1 day'')::date

      WHEN period = ''mtd'' THEN
        CASE
          WHEN base_date = ((date_trunc(''month'', base_date) + interval ''1 month'')::date
                            - interval ''1 day'')::date
            THEN date_trunc(''month'', base_date)::date
          ELSE (
            (date_trunc(''month'', base_date) - interval ''1 month'')::date
            + (base_date - date_trunc(''month'', base_date)::date + 1)
          )::date
        END

      WHEN period = ''mtdhms'' THEN
        LEAST(
          ((date_trunc(''month'', base_date) - interval ''1 month'')::date
           + (base_date - date_trunc(''month'', base_date)::date)
          )::timestamp
          + (now() AT TIME ZONE ''Asia/Seoul'')::time,
          date_trunc(''month'', base_date)::timestamp
        )
    END AS prev_to_kst
  FROM p
),

tz AS MATERIALIZED (
  SELECT
    EXTRACT(EPOCH FROM (this_from_kst::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (this_to_kst  ::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (prev_from_kst::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM (prev_to_kst  ::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS prev_to_utc,
    (this_from_kst::timestamp AT TIME ZONE ''Asia/Seoul'') AS this_from_ts,
    (this_to_kst  ::timestamp AT TIME ZONE ''Asia/Seoul'') AS this_to_ts
  FROM base_window
),

store_filter AS MATERIALIZED (
  SELECT s.store_no
  FROM public.tb_store s
  JOIN sellup.manager_store ms on s.store_no=ms.store_no
  JOIN sellup.manager mgr on ms.manager_id=mgr.manager_id and mgr.manager_id=:manager_id
  WHERE s.table_order_yn = true          -- 기본 베이스 조건
    AND (
      (SELECT store_type FROM p) = ''all''

      OR (
        (SELECT store_type FROM p) = ''sellup-no''
        AND NOT EXISTS (
          SELECT 1 FROM sellup.basic_info bi
          WHERE bi.store_no = s.store_no
            AND bi.is_active = true
        )
      )

      OR (
        (SELECT store_type FROM p) = ''sellup-all''
        AND EXISTS (
          SELECT 1 FROM sellup.basic_info bi
          WHERE bi.store_no = s.store_no
            AND bi.is_active = true
        )
      )

      OR (
        (SELECT store_type FROM p) = ''sellup-auto''
        AND EXISTS (
          SELECT 1 FROM sellup.apilot_config_store acs
          WHERE acs.store_no = s.store_no
            AND acs.is_auto_pilot = true
        )
      )
    )
),

visitors AS MATERIALIZED (
  SELECT
    dl.store_no,
    COALESCE(SUM(GREATEST(COALESCE(dl.number_of_adult, 1), 1)) FILTER (
      WHERE dl.reg_dt >= (SELECT this_from_utc FROM tz)
        AND dl.reg_dt <  (SELECT this_to_utc   FROM tz)
    ), 0)::bigint AS this_visitors,
    COALESCE(SUM(GREATEST(COALESCE(dl.number_of_adult, 1), 1)) FILTER (
      WHERE dl.reg_dt >= (SELECT prev_from_utc FROM tz)
        AND dl.reg_dt <  (SELECT prev_to_utc   FROM tz)
    ), 0)::bigint AS prev_visitors
  FROM pos.tb_deal dl
  JOIN store_filter sf ON sf.store_no = dl.store_no    -- store_filter 선적용
  WHERE dl.reg_dt >= (SELECT prev_from_utc FROM tz)
    AND dl.reg_dt <  (SELECT this_to_utc   FROM tz)
    AND dl.deal_status = ''OPRS_006''
  GROUP BY dl.store_no
),

nc_crm_sales AS MATERIALIZED (
  SELECT
    dd_base.store_no,
    COALESCE(SUM(doi.total_price), 0)::bigint AS sales
  FROM (
    SELECT DISTINCT
      store_no,
      deal_id,
      order_id
    FROM table_order.deal_discount
    WHERE discount_type IN (''COUPON'', ''POINT'')
      AND discount_amount > 0
      AND created_at >= (SELECT this_from_ts FROM tz)
      AND created_at <  (SELECT this_to_ts   FROM tz)
      AND (
        discount_type = ''POINT''
        OR (
          discount_type = ''COUPON''
          AND NOT EXISTS (
            SELECT 1
            FROM table_order.user_coupon uc
            JOIN sellup.campaign cp
              ON cp.coupon_id = uc.coupon_id
             AND cp.store_no  = uc.store_no
            WHERE uc.id = discount_ref_id
          )
        )
      )
  ) dd_base
  JOIN store_filter sf ON sf.store_no = dd_base.store_no   -- store_filter 선적용
  JOIN pos.tb_deal dl
    ON dl.deal_id     = dd_base.deal_id
   AND dl.store_no    = dd_base.store_no
   AND dl.deal_status = ''OPRS_006''
  JOIN pos.tb_deal_order_item doi
    ON doi.deal_id          = dd_base.deal_id
   AND doi.store_no          = dd_base.store_no
   AND doi.order_item_status = ''OPRS_006''
   AND doi.deleted_yn        = false
   AND (dd_base.order_id = 0 OR doi.order_id = dd_base.order_id)
  GROUP BY dd_base.store_no
),

campaign_crm_sales AS MATERIALIZED (
  SELECT
    c.store_no,
    COALESCE(SUM(doi.total_price), 0)::bigint AS sales
  FROM sellup.campaign_user cu
  JOIN sellup.campaign c
    ON c.campaign_id = cu.campaign_id
  JOIN store_filter sf ON sf.store_no = c.store_no         -- store_filter 선적용
  JOIN (
    SELECT
      cp2.store_no,
      uc2.coupon_id,
      GREATEST(
        MIN(cp2.created_at AT TIME ZONE ''Asia/Seoul''),
        (SELECT this_from_ts FROM tz)
      ) AS win_start,
      LEAST(
        MAX(uc2.expire_at AT TIME ZONE ''Asia/Seoul''),
        (SELECT this_to_ts FROM tz)
      ) AS win_end
    FROM table_order.coupon cp2
    JOIN table_order.user_coupon uc2
      ON uc2.coupon_id = cp2.id
     AND uc2.store_no  = cp2.store_no
    GROUP BY cp2.store_no, uc2.coupon_id
  ) cw
    ON cw.coupon_id  = c.coupon_id
   AND cw.store_no   = c.store_no
   AND cw.win_start  < cw.win_end
  JOIN pos.tb_deal dl
    ON dl.store_no    = c.store_no
   AND dl.deal_status = ''OPRS_006''
  JOIN pos.tb_deal_order tdo
    ON tdo.deal_id  = dl.deal_id
   AND tdo.store_no = dl.store_no
  LEFT JOIN table_order.user_points up
    ON up.store_no    = dl.store_no
   AND up.order_id    = tdo.order_id
   AND up.change_type = ''ACCUMULATE''
  JOIN pos.tb_deal_order_item doi
    ON doi.store_no          = tdo.store_no
   AND doi.order_id          = tdo.order_id
   AND doi.order_item_status = ''OPRS_006''
  WHERE cu.holdout = false
    AND up.user_id = cu.user_id
    AND (to_timestamp(dl.reg_dt) AT TIME ZONE ''Asia/Seoul'')
          BETWEEN cw.win_start AND cw.win_end
  GROUP BY c.store_no
),

member_count AS MATERIALIZED (
  SELECT
    us.store_no,
    COUNT(1)::bigint AS total_members
  FROM table_order.user_stores us
  JOIN store_filter sf ON sf.store_no = us.store_no  -- store_no 조인
  WHERE us.created_at < (SELECT this_to_ts FROM tz)  -- timestamptz 일치
    AND us.deleted_at IS NULL
  GROUP BY us.store_no
)

SELECT
  s.store_no,
  s.store_nm
  || CASE WHEN MAX(acs.store_no) IS NOT NULL THEN '' 🚀'' ELSE '''' END
  || CASE WHEN MAX(bi.store_no)  IS NOT NULL THEN '' ⭐'' ELSE '''' END
  AS store_nm,
  CASE WHEN MAX(bi.store_no) IS NULL THEN ''sellup-no''
       WHEN MAX(acs.store_no) IS NULL THEN ''sellup-basic''
       ELSE ''sellup-autopilot''
  END AS store_type,
  tsp.tbo_adult_yn,

  -- 매출
  COALESCE(SUM(doi.total_price) FILTER (
    WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
      AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
  ), 0)::bigint AS this_sales,

  COALESCE(SUM(doi.total_price) FILTER (
    WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
      AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
  ), 0)::bigint AS prev_sales,

  ROUND(
    CASE
      WHEN COALESCE(SUM(doi.total_price) FILTER (
             WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
               AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
           ), 0) = 0
      THEN NULL
      ELSE
        (
          COALESCE(SUM(doi.total_price) FILTER (
            WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
              AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
          ), 0)::numeric
          -
          COALESCE(SUM(doi.total_price) FILTER (
            WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
              AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
          ), 0)::numeric
        )
        /
        COALESCE(SUM(doi.total_price) FILTER (
          WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
            AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
        ), 0)::numeric * 100
    END,
    2
  ) AS sales_change_pct,

  -- 주문 수
  COUNT(DISTINCT doi.deal_id) FILTER (
    WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
      AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
  ) AS this_orders,

  COUNT(DISTINCT doi.deal_id) FILTER (
    WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
      AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
  ) AS prev_orders,

  -- AOV (this)
  COALESCE(
    (SUM(doi.total_price) FILTER (
       WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
         AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
     ))::numeric
    /
    NULLIF(
      COUNT(DISTINCT doi.deal_id) FILTER (
        WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
          AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
      ), 0
    ),
    0
  )::numeric(18,2) AS this_aov,

  -- AOV (prev)
  COALESCE(
    (SUM(doi.total_price) FILTER (
       WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
         AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
     ))::numeric
    /
    NULLIF(
      COUNT(DISTINCT doi.deal_id) FILTER (
        WHERE doi.reg_dt >= (SELECT prev_from_utc FROM tz)
          AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz)
      ), 0
    ),
    0
  )::numeric(18,2) AS prev_aov,

  -- 입장 인원수
  COALESCE(MAX(v.this_visitors), 0) AS this_visitors,
  COALESCE(MAX(v.prev_visitors), 0) AS prev_visitors,

  -- AI 매출
  COALESCE(MAX(nc.sales), 0) + COALESCE(MAX(ccs.sales), 0) AS ai_sales,

  ROUND(
    CASE
      WHEN COALESCE(SUM(doi.total_price) FILTER (
             WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
               AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
           ), 0) = 0
      THEN NULL
      ELSE
        (COALESCE(MAX(nc.sales), 0) + COALESCE(MAX(ccs.sales), 0))::numeric
        /
        COALESCE(SUM(doi.total_price) FILTER (
          WHERE doi.reg_dt >= (SELECT this_from_utc FROM tz)
            AND doi.reg_dt <  (SELECT this_to_utc   FROM tz)
        ), 0)::numeric * 100
    END,
    2
  ) AS ai_sales_rate,

  -- 누적 유저수 (해당 기간 this_to 기준)
  COALESCE(MAX(mc.total_members), 0) AS total_members

FROM pos.tb_deal_order_item doi
JOIN public.tb_store s                    ON s.store_no   = doi.store_no
JOIN store_filter sf                      ON sf.store_no  = doi.store_no
LEFT JOIN public.tb_store_pos tsp         ON tsp.store_no = doi.store_no
LEFT JOIN visitors v                      ON v.store_no   = doi.store_no
LEFT JOIN sellup.apilot_config_store acs  ON acs.store_no = doi.store_no
                                         AND acs.is_auto_pilot = true
LEFT JOIN sellup.basic_info bi            ON bi.store_no  = doi.store_no
                                         AND bi.is_active = true
LEFT JOIN nc_crm_sales       nc           ON nc.store_no  = doi.store_no
LEFT JOIN campaign_crm_sales ccs          ON ccs.store_no = doi.store_no
LEFT JOIN member_count       mc           ON mc.store_no  = doi.store_no
WHERE doi.order_item_status = ''OPRS_006''
  AND (
       (doi.reg_dt >= (SELECT this_from_utc FROM tz)
        AND doi.reg_dt <  (SELECT this_to_utc   FROM tz))
    OR (doi.reg_dt >= (SELECT prev_from_utc FROM tz)
        AND doi.reg_dt <  (SELECT prev_to_utc   FROM tz))
  )
GROUP BY s.store_no, s.store_nm, tsp.tbo_adult_yn
ORDER BY ai_sales_rate DESC, sales_change_pct DESC;
',
       null, null, '프랜차이즈 파트너가 관리하는 매장의 특정월에 대한 캠페인이 반영된 매출지표 요약 및 캠페인별 순매출현황을 조회 한다.' from sellup.seg_lib where seg_code='stores_sales_status_fc' and default_engine='postgres';
