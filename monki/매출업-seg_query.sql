
--seg_lib,seg_lib_sql에 쿼리를 추가한다

INSERT INTO sellup.seg_lib (seg_lib_id, seg_name, target, description, ai_hint, params_schema, status, tags, seg_code, default_engine)
VALUES (uuid_generate_v4(), '특정매장,특정메뉴의 상세 영업분석', '특정월에 대한 특정 메뉴의 매출현황 상세 분석',
        '최근 30일 매출추이등 한메뉴에 대한 상세한 영업내역을 조회한다.',
        '{}',
        '{"type": "object", "required": ["store_no", "menu_no", "base_date", "period"], "properties": {"store_no": {"type": "integer", "description": "매장 번호"}, "menu_no": {"type": "integer", "description": "메뉴 번호"}, "base_date": {"type": "string", "format": "date"},"period": {"type": "string"}}}',
        'active',
        '{menu sales,menu sales trend}',
        'menu_sales_status',
        'postgres');
select * from sellup.seg_lib where seg_code='menu_sales_status';
{"type": "object", "required": ["store_no", "base_date"], "properties": {"store_no": {"type": "integer", "description": "매장 번호"}, "base_date": {"type": "string", "format": "date", "description": "기준일 (YYYY-MM-DD)"}, "horizon_days": {"type": "integer", "default": 30, "description": "예측 기간(일)"}, "model_version": {"type": "string", "default": "rb-v0.3", "description": "모델 버전"}}}

INSERT INTO sellup.seg_lib (seg_lib_id, seg_code, seg_name, target, description, ai_hint, params_schema, status, tags, default_engine)
VALUES (uuid_generate_v4(), 'abc_kpi_guest_pareto_ratio', 'abc-kpis 비회원 파레토(70%) 비율 (this vs prev)', '비회원 고객의 파레토비율 비교', '비교구간(this/prev)의 매출중 비회원 고객의 파레토 비교', '{"notes": "비교구간 매출 상위 70% 비회원 기준으로 this/prev 파레토 비중을 비교합니다.", "visual": "card", "metrics": ["this_total_deals","prev_total_deals","this_a_deals","prev_a_deals","this_total_sales","prev_total_sales","this_a_sales","prev_a_sales","this_a_deal_ratio_pct","prev_a_deal_ratio_pct","this_a_sales_share_pct","prev_a_sales_share_pct","delta_pp","ratio_vs_prev_pct","diff_a_sales","a_sales_ratio_vs_prev_pct"], "purpose": "abc_analysis"}', '{"type": "object", "required": ["store_no", "base_date", "period"], "properties": {"period": {"enum": ["day", "weekday", "week", "month", "quarter","mtd","mtdhms"], "type": "string"}, "store_no": {"type": "integer"}, "base_date": {"type": "string", "format": "date"}}}', 'active', '{abc,a_ratio,guest_pareto,kpi,this_prev}', 'postgres');

INSERT INTO sellup.seg_lib_sql (seg_lib_sql_id, seg_lib_id, engine, sql_base, sql_preview_override, sql_materialize_override, notes)
select uuid_generate_v4(),seg_lib_id,'postgres',e'/* seg_code: abc_kpi_guest_pareto_deal_ratio
   비회원 Pareto deal ratio 분석

   정의
   - 비회원: table_order.user_points 에 연결되지 않은 deal
   - A deal : 각 비교구간 내에서 deal 매출을 내림차순 정렬했을 때,
              누적 매출 70%까지 포함되는 deal 집합
   - 해석
     * A deal 비율이 낮을수록: 더 적은 주문이 매출 70%를 만들어냄 = 집중도 높음
     * A deal 비율이 높을수록: 더 많은 주문이 매출 70%를 나눠 만듦 = 분산도 높음

   반환
   - this/prev 총 deal 수
   - this/prev A deal 수
   - this/prev 총 매출
   - this/prev A deal 매출
   - this/prev A deal 비율(%)
   - this/prev A deal 매출 비중(%)
   - delta_pp / ratio_vs_prev_pct
*/

WITH
p AS (
  SELECT
    :store_no::bigint    AS store_no,
    :base_date::date     AS base_date,
    lower(:period)::text AS period,
    0.7::numeric         AS a_cut
),

base_window AS (
  SELECT
    store_no,
    period,
    base_date,

    -- THIS from (KST)
    CASE
      WHEN period = ''day''     THEN base_date
      WHEN period = ''weekday'' THEN base_date
      WHEN period = ''week''    THEN (base_date - interval ''6 day'')::date
      WHEN period = ''month''   THEN (base_date - interval ''1 month'' + interval ''1 day'')::date
      WHEN period = ''quarter'' THEN (base_date - interval ''3 month'' + interval ''1 day'')::date
      WHEN period = ''mtd''     THEN date_trunc(''month'', base_date)::date
      WHEN period = ''mtdhms''  THEN date_trunc(''month'', base_date)::date
      ELSE base_date
    END AS this_from_kst,

    -- THIS to (KST, exclusive)
    CASE
      WHEN period = ''mtdhms'' THEN
        base_date::timestamp + (now() AT TIME ZONE ''Asia/Seoul'')::time
      WHEN period = ''mtd'' THEN
        (base_date + interval ''1 day'')::timestamp
      ELSE
        (base_date + interval ''1 day'')::timestamp
    END AS this_to_kst,

    -- PREV from (KST)
    CASE
      WHEN period = ''day''     THEN (base_date - interval ''1 day'')::date
      WHEN period = ''weekday'' THEN (base_date - interval ''7 day'')::date
      WHEN period = ''week''    THEN (base_date - interval ''13 day'')::date
      WHEN period = ''month''   THEN (base_date - interval ''2 month'' + interval ''1 day'')::date
      WHEN period = ''quarter'' THEN (base_date - interval ''6 month'' + interval ''1 day'')::date
      WHEN period = ''mtd''     THEN (date_trunc(''month'', base_date) - interval ''1 month'')::date
      WHEN period = ''mtdhms''  THEN (date_trunc(''month'', base_date) - interval ''1 month'')::date
      ELSE (base_date - interval ''1 day'')::date
    END AS prev_from_kst,

    -- PREV to (KST, exclusive)
    CASE
      WHEN period = ''day'' THEN
        base_date::timestamp

      WHEN period = ''weekday'' THEN
        (base_date - interval ''6 day'')::timestamp

      WHEN period = ''week'' THEN
        (base_date - interval ''6 day'')::timestamp

      WHEN period = ''month'' THEN
        (base_date - interval ''1 month'' + interval ''1 day'')::timestamp

      WHEN period = ''quarter'' THEN
        (base_date - interval ''3 month'' + interval ''1 day'')::timestamp

      WHEN period = ''mtd'' THEN
        CASE
          WHEN base_date = (
            (date_trunc(''month'', base_date) + interval ''1 month'')::date
            - interval ''1 day''
          )::date
          THEN date_trunc(''month'', base_date)::timestamp
          ELSE (
            (date_trunc(''month'', base_date) - interval ''1 month'')::date
            + (base_date - date_trunc(''month'', base_date)::date + 1)
          )::timestamp
        END

      WHEN period = ''mtdhms'' THEN
        LEAST(
          (
            (date_trunc(''month'', base_date) - interval ''1 month'')::date
            + (base_date - date_trunc(''month'', base_date)::date)
          )::timestamp
          + (now() AT TIME ZONE ''Asia/Seoul'')::time,
          date_trunc(''month'', base_date)::timestamp
        )

      ELSE base_date::timestamp
    END AS prev_to_kst
  FROM p
),

tz AS (
  SELECT
    bw.*,
    EXTRACT(EPOCH FROM (bw.this_from_kst::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS this_from_utc,
    EXTRACT(EPOCH FROM (bw.this_to_kst  ::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS this_to_utc,
    EXTRACT(EPOCH FROM (bw.prev_from_kst::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS prev_from_utc,
    EXTRACT(EPOCH FROM (bw.prev_to_kst  ::timestamp AT TIME ZONE ''Asia/Seoul''))::bigint AS prev_to_utc
  FROM base_window bw
),

scope AS (
  SELECT
    store_no,
    LEAST(this_from_utc, prev_from_utc) AS scope_from_utc,
    GREATEST(this_to_utc, prev_to_utc)  AS scope_to_utc
  FROM tz
),

/* 스코프 내 비회원 deal별 매출 */
guest_deal_sales AS (
  SELECT
    CASE
      WHEN doi.reg_dt >= t.this_from_utc AND doi.reg_dt < t.this_to_utc THEN ''this''
      WHEN doi.reg_dt >= t.prev_from_utc AND doi.reg_dt < t.prev_to_utc THEN ''prev''
      ELSE NULL
    END AS bucket,
    doi.deal_id,
    SUM(doi.total_price)::bigint AS order_total
  FROM tz t
  JOIN pos.tb_deal_order_item doi
    ON doi.store_no = t.store_no
   AND doi.order_item_status = ''OPRS_006''
   AND doi.reg_dt >= (SELECT s.scope_from_utc FROM scope s WHERE s.store_no = t.store_no)
   AND doi.reg_dt <  (SELECT s.scope_to_utc   FROM scope s WHERE s.store_no = t.store_no)
  LEFT JOIN table_order.user_points up
    ON up.store_no = doi.store_no
   AND up.deal_id  = doi.deal_id
  WHERE up.deal_id IS NULL
  GROUP BY bucket, doi.deal_id
),

guest_deal_sales_clean AS (
  SELECT *
  FROM guest_deal_sales
  WHERE bucket IN (''this'', ''prev'')
),

/* bucket별 매출순 정렬 + 누적매출 */
ranked AS (
  SELECT
    bucket,
    deal_id,
    order_total,
    SUM(order_total) OVER (
      PARTITION BY bucket
      ORDER BY order_total DESC, deal_id
    ) AS cum_sales,
    SUM(order_total) OVER (PARTITION BY bucket) AS total_sales,
    COUNT(*)        OVER (PARTITION BY bucket) AS total_deals
  FROM guest_deal_sales_clean
),

/* A deal = 누적매출 70%까지 */
a_set AS (
  SELECT
    r.bucket,
    r.deal_id
  FROM ranked r
  CROSS JOIN p
  WHERE r.total_sales > 0
    AND (r.cum_sales::numeric / r.total_sales) <= p.a_cut
),

metrics AS (
  SELECT
    r.bucket,
    MAX(r.total_deals)::int      AS total_deals,
    COUNT(a.deal_id)::int        AS a_deals,
    MAX(r.total_sales)::bigint   AS total_sales,
    COALESCE(
      SUM(r.order_total) FILTER (WHERE a.deal_id IS NOT NULL),
      0
    )::bigint AS a_sales
  FROM ranked r
  LEFT JOIN a_set a
    ON a.bucket = r.bucket
   AND a.deal_id = r.deal_id
  GROUP BY r.bucket
)

SELECT
  -- deal 수
  COALESCE(MAX(total_deals) FILTER (WHERE bucket = ''this''), 0) AS this_total_deals,
  COALESCE(MAX(total_deals) FILTER (WHERE bucket = ''prev''), 0) AS prev_total_deals,

  COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''this''), 0) AS this_a_deals,
  COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''prev''), 0) AS prev_a_deals,

  -- 매출액
  COALESCE(MAX(total_sales) FILTER (WHERE bucket = ''this''), 0) AS this_total_sales,
  COALESCE(MAX(total_sales) FILTER (WHERE bucket = ''prev''), 0) AS prev_total_sales,

  COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''this''), 0) AS this_a_sales,
  COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''prev''), 0) AS prev_a_sales,

  -- A deal 비율
  CASE
    WHEN COALESCE(MAX(total_deals) FILTER (WHERE bucket = ''this''), 0) = 0 THEN 0
    ELSE ROUND(
      COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''this''), 0)::numeric
      / NULLIF(MAX(total_deals) FILTER (WHERE bucket = ''this''), 0)
      * 100
    , 2)
  END AS this_a_deal_ratio_pct,

  CASE
    WHEN COALESCE(MAX(total_deals) FILTER (WHERE bucket = ''prev''), 0) = 0 THEN 0
    ELSE ROUND(
      COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''prev''), 0)::numeric
      / NULLIF(MAX(total_deals) FILTER (WHERE bucket = ''prev''), 0)
      * 100
    , 2)
  END AS prev_a_deal_ratio_pct,

  -- A deal 매출 비중
  CASE
    WHEN COALESCE(MAX(total_sales) FILTER (WHERE bucket = ''this''), 0) = 0 THEN 0
    ELSE ROUND(
      COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''this''), 0)::numeric
      / NULLIF(MAX(total_sales) FILTER (WHERE bucket = ''this''), 0)
      * 100
    , 2)
  END AS this_a_sales_share_pct,

  CASE
    WHEN COALESCE(MAX(total_sales) FILTER (WHERE bucket = ''prev''), 0) = 0 THEN 0
    ELSE ROUND(
      COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''prev''), 0)::numeric
      / NULLIF(MAX(total_sales) FILTER (WHERE bucket = ''prev''), 0)
      * 100
    , 2)
  END AS prev_a_sales_share_pct,

  -- deal 비율 delta
  ROUND(
    (
      COALESCE(
        (MAX(a_deals) FILTER (WHERE bucket = ''this''))::numeric
        / NULLIF(MAX(total_deals) FILTER (WHERE bucket = ''this''), 0),
        0
      )
      -
      COALESCE(
        (MAX(a_deals) FILTER (WHERE bucket = ''prev''))::numeric
        / NULLIF(MAX(total_deals) FILTER (WHERE bucket = ''prev''), 0),
        0
      )
    ) * 100
  , 2) AS delta_pp,

  -- deal 비율 전기 대비
  CASE
    WHEN COALESCE(MAX(total_deals) FILTER (WHERE bucket = ''prev''), 0) = 0
      OR COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''prev''), 0) = 0
    THEN NULL
    ELSE ROUND(
      (
        (
          COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''this''), 0)::numeric
          / NULLIF(MAX(total_deals) FILTER (WHERE bucket = ''this''), 0)
        )
        /
        NULLIF(
          COALESCE(MAX(a_deals) FILTER (WHERE bucket = ''prev''), 0)::numeric
          / NULLIF(MAX(total_deals) FILTER (WHERE bucket = ''prev''), 0),
          0
        )
      ) * 100
    , 2)
  END AS ratio_vs_prev_pct,

  -- A 매출액 증감
  COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''this''), 0)
  - COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''prev''), 0) AS diff_a_sales,

  CASE
    WHEN COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''prev''), 0) = 0 THEN NULL
    ELSE ROUND(
      (
        COALESCE(MAX(a_sales) FILTER (WHERE bucket = ''this''), 0)::numeric
        / NULLIF(MAX(a_sales) FILTER (WHERE bucket = ''prev''), 0)
      ) * 100
    , 2)
  END AS a_sales_ratio_vs_prev_pct

FROM metrics;
',
       null, null, 'abc-kpis 비회원 파레토(70%) 비율 (this vs prev)' from sellup.seg_lib where seg_code='abc_kpi_guest_pareto_ratio' and default_engine='postgres';
