store_daily_sales_summary
store_weekday_sales_summary
store_hourly_sales_summary
store_monthly_sales_summary
store_month_sales_summary

--seg_lib,seg_lib_sql에 쿼리를 추가한다
select * from sellup.seg_lib where seg_code='store_month_sales_summary';
INSERT INTO sellup.seg_lib (seg_lib_id, seg_code, seg_name, params_schema, target, description, ai_hint, status, tags, default_engine)
VALUES (uuid_generate_v4(), 'store_monthly_sales_summary', '매장의 년간 월별 영업분석', '{"type": "object", "required": ["base_year", "store_no"], "properties": {"base_yymm": {"type": "string", "pattern": "^\\d{4}-(0[1-9]|1[0-2])$", "examples": ["2026"]}, "store_no": {"type": "integer"}}}', '매장의 년간 월별 매출,할인,순매출을 조회', '매장의 년간 월별 매출,할인,순매출을 조회 (거래건수,손님수,주문수,주문금액,쿠폰할인액,포인트사용액,순매출액)', '{}', 'active', '{sales report monthly,deal_count,customer_count,order_count,order_amount,coupon_discount,point_used,net_sales}', 'postgres');

INSERT INTO sellup.seg_lib_sql (seg_lib_sql_id, seg_lib_id, engine, sql_base, sql_preview_override, sql_materialize_override, notes)
select uuid_generate_v4(),seg_lib_id,'postgres',e'WITH
params AS (
    SELECT
        MAKE_DATE(:base_year::integer, 1, 1) AS year_from_kst,
        :store_no::bigint                    AS store_no
),

bounds AS (
    SELECT
        p.year_from_kst,
        (p.year_from_kst + INTERVAL ''1 year'')::date AS year_to_kst,
        p.store_no
    FROM params p
),

epoch_bounds AS (
    SELECT
        b.year_from_kst,
        b.year_to_kst,
        b.store_no,

        EXTRACT(
            EPOCH FROM (
                b.year_from_kst::timestamp
                AT TIME ZONE ''Asia/Seoul''
            )
        )::bigint AS from_utc,

        EXTRACT(
            EPOCH FROM (
                b.year_to_kst::timestamp
                AT TIME ZONE ''Asia/Seoul''
            )
        )::bigint AS to_utc

    FROM bounds b
),

/*
 * 1월~12월 기본 행
 * 해당 월에 매출이 없어도 0으로 반환
 */
month_dimension AS (
    SELECT
        gs AS month_no,
        gs::text || ''월'' AS month_name
    FROM GENERATE_SERIES(1, 12) AS gs
),

/*
 * 완료 딜 + 완료 주문 + 완료 주문상품
 * 주문상품은 주문 단위로 합산
 */
valid_orders AS (
    SELECT
        d.store_no,
        d.deal_id,
        o.order_id,

        EXTRACT(
            MONTH FROM (
                TO_TIMESTAMP(o.reg_dt)
                AT TIME ZONE ''Asia/Seoul''
            )
        )::integer AS month_no,

        COALESCE(d.number_of_adult, 0)
        + COALESCE(d.number_of_child, 0) AS customer_count,

        SUM(
            COALESCE(oi.total_price, 0)
        )::bigint AS order_amount

    FROM pos.tb_deal_order o

    JOIN pos.tb_deal d
      ON d.store_no = o.store_no
     AND d.deal_id = o.deal_id
     AND d.deal_status = ''OPRS_006''
     AND d.deleted_yn IS NOT TRUE

    JOIN pos.tb_deal_order_item oi
      ON oi.store_no = o.store_no
     AND oi.deal_id = o.deal_id
     AND oi.order_id = o.order_id
     AND oi.order_item_status = ''OPRS_006''
     AND oi.deleted_yn IS NOT TRUE

    CROSS JOIN epoch_bounds eb

    WHERE o.store_no = eb.store_no
      AND o.order_status = ''OPRS_006''
      AND o.deleted_yn IS NOT TRUE
      AND o.reg_dt >= eb.from_utc
      AND o.reg_dt <  eb.to_utc

    GROUP BY
        d.store_no,
        d.deal_id,
        o.order_id,
        o.reg_dt,
        d.number_of_adult,
        d.number_of_child
),

/*
 * 월별 딜·주문·주문금액
 */
sales_agg AS (
    SELECT
        vo.month_no,

        COUNT(DISTINCT vo.deal_id)::bigint
            AS deal_count,

        COUNT(DISTINCT vo.order_id)::bigint
            AS order_count,

        COALESCE(
            SUM(vo.order_amount),
            0
        )::bigint AS order_amount

    FROM valid_orders vo
    GROUP BY vo.month_no
),

/*
 * 손님 수는 같은 월 내 딜별 한 번만 합산
 */
customer_agg AS (
    SELECT
        x.month_no,
        SUM(x.customer_count)::bigint AS customer_count

    FROM (
        SELECT DISTINCT ON (
            vo.month_no,
            vo.deal_id
        )
            vo.month_no,
            vo.deal_id,
            vo.customer_count

        FROM valid_orders vo

        ORDER BY
            vo.month_no,
            vo.deal_id,
            vo.order_id
    ) x

    GROUP BY x.month_no
),

/*
 * 유효 주문에 연결된 쿠폰·포인트 할인
 */
discount_agg AS (
    SELECT
        vo.month_no,

        SUM(
            CASE
                WHEN dd.discount_type = ''COUPON''
                THEN ABS(COALESCE(dd.discount_amount, 0))
                ELSE 0
            END
        )::bigint AS coupon_discount,

        SUM(
            CASE
                WHEN dd.discount_type = ''POINT''
                THEN ABS(COALESCE(dd.discount_amount, 0))
                ELSE 0
            END
        )::bigint AS point_used

    FROM valid_orders vo

    JOIN table_order.deal_discount dd
      ON dd.store_no = vo.store_no
     AND dd.order_id = vo.order_id
     AND dd.deleted_at IS NULL
     AND dd.is_mock = false
     AND dd.discount_type IN (''COUPON'', ''POINT'')

    GROUP BY vo.month_no
)

SELECT
    md.month_no,
    md.month_name,

    COALESCE(sa.deal_count, 0)::bigint
        AS deal_count,

    COALESCE(ca.customer_count, 0)::bigint
        AS customer_count,

    COALESCE(sa.order_count, 0)::bigint
        AS order_count,

    COALESCE(sa.order_amount, 0)::bigint
        AS order_amount,

    COALESCE(da.coupon_discount, 0)::bigint
        AS coupon_discount,

    COALESCE(da.point_used, 0)::bigint
        AS point_used,

    (
        COALESCE(sa.order_amount, 0)
        - COALESCE(da.coupon_discount, 0)
        - COALESCE(da.point_used, 0)
    )::bigint AS net_sales

FROM month_dimension md

LEFT JOIN sales_agg sa
       ON sa.month_no = md.month_no

LEFT JOIN customer_agg ca
       ON ca.month_no = md.month_no

LEFT JOIN discount_agg da
       ON da.month_no = md.month_no

ORDER BY md.month_no;
',
       null, null, '매장의 년간 월별 매출,할인,순매출을 조회 (거래건수,손님수,주문수,주문금액,쿠폰할인액,포인트사용액,순매출액)' from sellup.seg_lib where seg_code='store_monthly_sales_summary' and default_engine='postgres';
