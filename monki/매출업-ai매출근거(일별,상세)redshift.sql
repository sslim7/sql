
-- 일별 매출,ai매출 현황
/* ============================================================
   AI 매출 일별 근거
   Redshift

   입력
     :store_no BIGINT
     :month    VARCHAR(7)  -- '2026-08'

   AI 매출 =
       campaign_ai_sales
     + noncampaign_ai_sales

   중요:
   현재 영업현황 대시보드의 AI 매출 산정 로직을 그대로 사용.
   ============================================================ */

WITH

/* ============================================================
   PARAMS
   ============================================================ */
p0 AS (
    SELECT
        CAST(:store_no AS BIGINT) AS store_no,

        CAST(
            TO_DATE(
                CAST(:month AS VARCHAR(7)) || '-01',
                'YYYY-MM-DD'
            )
            AS DATE
        ) AS month_start_kst
),

p AS (
    SELECT
        p0.*,

        CAST(
            DATEADD(
                month,
                1,
                month_start_kst
            )
            AS DATE
        ) AS next_month_start_kst,

        CONVERT_TIMEZONE(
            'Asia/Seoul',
            'UTC',
            CAST(month_start_kst AS TIMESTAMP)
        ) AS month_start_utc_ts,

        CONVERT_TIMEZONE(
            'Asia/Seoul',
            'UTC',
            CAST(
                DATEADD(
                    month,
                    1,
                    month_start_kst
                )
                AS TIMESTAMP
            )
        ) AS next_month_start_utc_ts

    FROM p0
),

bounds AS (
    SELECT
        p.*,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                month_start_utc_ts
            )
            AS BIGINT
        ) AS month_start_epoch,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                next_month_start_utc_ts
            )
            AS BIGINT
        ) AS next_month_start_epoch

    FROM p
),

/* ============================================================
   월 달력
   매출 없는 날짜도 0으로 반환
   ============================================================ */
calendar AS (
    SELECT
        DATEADD(
            day,
            n,
            (SELECT month_start_kst FROM bounds)
        )::DATE AS sales_date

    FROM (
        SELECT 0 AS n UNION ALL
        SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL
        SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL
        SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL
        SELECT 10 UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL
        SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15 UNION ALL
        SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL
        SELECT 19 UNION ALL SELECT 20 UNION ALL SELECT 21 UNION ALL
        SELECT 22 UNION ALL SELECT 23 UNION ALL SELECT 24 UNION ALL
        SELECT 25 UNION ALL SELECT 26 UNION ALL SELECT 27 UNION ALL
        SELECT 28 UNION ALL SELECT 29 UNION ALL SELECT 30
    ) x

    WHERE DATEADD(
              day,
              n,
              (SELECT month_start_kst FROM bounds)
          )
          <
          (SELECT next_month_start_kst FROM bounds)
),

/* ============================================================
   해당 월 정상 주문아이템

   total_sales와 AI sales 양쪽에서 사용
   ============================================================ */
current_order_item AS (
    SELECT
        doi.store_no,
        doi.deal_id,
        doi.order_id,
        doi.menu_no,
        doi.reg_dt,
        doi.total_price

    FROM pos.tb_deal_order_item doi

    WHERE doi.store_no =
          (SELECT store_no FROM bounds)

      AND doi.reg_dt >=
          (SELECT month_start_epoch FROM bounds)

      AND doi.reg_dt <
          (SELECT next_month_start_epoch FROM bounds)

      AND doi.order_item_status = 'OPRS_006'
      AND doi.deleted_yn = FALSE
),

/* ============================================================
   해당 월 정상 Deal
   ============================================================ */
current_deal AS (
    SELECT
        dl.store_no,
        dl.deal_id,
        dl.reg_dt

    FROM pos.tb_deal dl

    WHERE dl.store_no =
          (SELECT store_no FROM bounds)

      AND dl.reg_dt >=
          (SELECT month_start_epoch FROM bounds)

      AND dl.reg_dt <
          (SELECT next_month_start_epoch FROM bounds)

      AND dl.deal_status = 'OPRS_006'
),

/* ============================================================
   1) 전체 일별 매출

   대시보드 this_sales 기준과 동일하게
   order_item_status='OPRS_006' 아이템 합계
   ============================================================ */
daily_total_sales AS (
    SELECT
        CAST(
            CONVERT_TIMEZONE(
                'UTC',
                'Asia/Seoul',
                DATEADD(
                    second,
                    coi.reg_dt,
                    TIMESTAMP '1970-01-01 00:00:00'
                )
            )
            AS DATE
        ) AS sales_date,

        CAST(
            SUM(coi.total_price)
            AS BIGINT
        ) AS total_sales

    FROM current_order_item coi

    GROUP BY
        CAST(
            CONVERT_TIMEZONE(
                'UTC',
                'Asia/Seoul',
                DATEADD(
                    second,
                    coi.reg_dt,
                    TIMESTAMP '1970-01-01 00:00:00'
                )
            )
            AS DATE
        )
),

/* ============================================================
   캠페인에서 생성한 쿠폰의 user_coupon ID

   비캠페인 쿠폰 제외용
   ============================================================ */
campaign_discount_ref AS (
    SELECT DISTINCT
        uc.id AS discount_ref_id

    FROM table_order.user_coupon uc

    JOIN sellup.campaign cp
      ON cp.coupon_id = uc.coupon_id
     AND cp.store_no = uc.store_no

    WHERE cp.store_no =
          (SELECT store_no FROM bounds)

      AND cp.coupon_id IS NOT NULL
),

/* ============================================================
   비캠페인 쿠폰/포인트 사용 주문

   현재 대시보드 discount_base와 같은 의미
   ============================================================ */
discount_base AS (
    SELECT DISTINCT
        dd.store_no,
        dd.deal_id,
        dd.order_id

    FROM table_order.deal_discount dd

    LEFT JOIN campaign_discount_ref cdr
      ON cdr.discount_ref_id = dd.discount_ref_id

    WHERE dd.store_no =
          (SELECT store_no FROM bounds)

      AND dd.created_at >=
          (SELECT month_start_utc_ts FROM bounds)

      AND dd.created_at <
          (SELECT next_month_start_utc_ts FROM bounds)

      AND dd.discount_type IN ('COUPON', 'POINT')
      AND dd.discount_amount > 0

      AND (
            dd.discount_type = 'POINT'

            OR

            (
                dd.discount_type = 'COUPON'
                AND cdr.discount_ref_id IS NULL
            )
          )
),

/* ============================================================
   비캠페인 AI 매출 item

   db.order_id = 0
     → deal 전체

   db.order_id != 0
     → 해당 order만
   ============================================================ */
noncampaign_ai_item AS (
    SELECT
        db.store_no,
        coi.deal_id,
        coi.order_id,
        coi.reg_dt,
        coi.total_price

    FROM discount_base db

    JOIN current_deal cd
      ON cd.store_no = db.store_no
     AND cd.deal_id = db.deal_id

    JOIN current_order_item coi
      ON coi.store_no = db.store_no
     AND coi.deal_id = db.deal_id

     AND (
            db.order_id = 0
            OR coi.order_id = db.order_id
         )
),

noncampaign_daily AS (
    SELECT
        CAST(
            CONVERT_TIMEZONE(
                'UTC',
                'Asia/Seoul',
                DATEADD(
                    second,
                    reg_dt,
                    TIMESTAMP '1970-01-01 00:00:00'
                )
            )
            AS DATE
        ) AS sales_date,

        CAST(
            SUM(total_price)
            AS BIGINT
        ) AS noncampaign_ai_sales

    FROM noncampaign_ai_item

    GROUP BY
        CAST(
            CONVERT_TIMEZONE(
                'UTC',
                'Asia/Seoul',
                DATEADD(
                    second,
                    reg_dt,
                    TIMESTAMP '1970-01-01 00:00:00'
                )
            )
            AS DATE
        )
),

/* ============================================================
   캠페인
   ============================================================ */
campaign_base AS (
    SELECT
        c.campaign_id,
        c.store_no,
        c.coupon_id

    FROM sellup.campaign c

    WHERE c.store_no =
          (SELECT store_no FROM bounds)

      AND c.coupon_id IS NOT NULL
),

campaign_coupon_key AS (
    SELECT DISTINCT
        store_no,
        coupon_id

    FROM campaign_base
),

/* ============================================================
   캠페인 쿠폰 실제 유효기간 ∩ 조회월
   ============================================================ */
campaign_coupon_window AS (
    SELECT
        ck.store_no,
        ck.coupon_id,

        GREATEST(
            MIN(cp.created_at),
            (SELECT month_start_utc_ts FROM bounds)
        ) AS win_start_utc,

        LEAST(
            MAX(uc.expire_at),
            (SELECT next_month_start_utc_ts FROM bounds)
        ) AS win_end_utc

    FROM campaign_coupon_key ck

    JOIN table_order.coupon cp
      ON cp.store_no = ck.store_no
     AND cp.id = ck.coupon_id

    JOIN table_order.user_coupon uc
      ON uc.store_no = ck.store_no
     AND uc.coupon_id = ck.coupon_id

    GROUP BY
        ck.store_no,
        ck.coupon_id
),

campaign_coupon_window_epoch AS (
    SELECT
        store_no,
        coupon_id,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                CAST(win_start_utc AS TIMESTAMP)
            )
            AS BIGINT
        ) AS win_start_epoch,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                CAST(win_end_utc AS TIMESTAMP)
            )
            AS BIGINT
        ) AS win_end_epoch

    FROM campaign_coupon_window

    WHERE win_start_utc < win_end_utc
),

/* ============================================================
   캠페인 실제 타겟
   holdout = false
   ============================================================ */
campaign_target AS (
    SELECT
        cb.campaign_id,
        cb.store_no,
        cu.user_id,

        cw.win_start_epoch,
        cw.win_end_epoch

    FROM campaign_base cb

    JOIN sellup.campaign_user cu
      ON cu.campaign_id = cb.campaign_id
     AND cu.holdout = FALSE

    JOIN campaign_coupon_window_epoch cw
      ON cw.store_no = cb.store_no
     AND cw.coupon_id = cb.coupon_id
),

/* ============================================================
   해당 매장의 ACCUMULATE

   store predicate를 직접 걸어 full scan 방지
   ============================================================ */
store_points AS (
    SELECT
        up.store_no,
        up.user_id,
        up.order_id

    FROM table_order.user_points up

    WHERE up.store_no =
          (SELECT store_no FROM bounds)

      AND up.change_type = 'ACCUMULATE'
),

/* ============================================================
   캠페인 AI 매출 item
   ============================================================ */
campaign_ai_item AS (
    SELECT
        ct.store_no,
        ct.campaign_id,

        coi.deal_id,
        coi.order_id,
        coi.reg_dt,
        coi.total_price

    FROM campaign_target ct

    JOIN store_points up
      ON up.store_no = ct.store_no
     AND up.user_id = ct.user_id

    JOIN current_order_item coi
      ON coi.store_no = up.store_no
     AND coi.order_id = up.order_id

    JOIN current_deal cd
      ON cd.store_no = coi.store_no
     AND cd.deal_id = coi.deal_id

     AND cd.reg_dt >= ct.win_start_epoch
     AND cd.reg_dt <= ct.win_end_epoch
),

campaign_daily AS (
    SELECT
        CAST(
            CONVERT_TIMEZONE(
                'UTC',
                'Asia/Seoul',
                DATEADD(
                    second,
                    reg_dt,
                    TIMESTAMP '1970-01-01 00:00:00'
                )
            )
            AS DATE
        ) AS sales_date,

        CAST(
            SUM(total_price)
            AS BIGINT
        ) AS campaign_ai_sales

    FROM campaign_ai_item

    GROUP BY
        CAST(
            CONVERT_TIMEZONE(
                'UTC',
                'Asia/Seoul',
                DATEADD(
                    second,
                    reg_dt,
                    TIMESTAMP '1970-01-01 00:00:00'
                )
            )
            AS DATE
        )
)

/* ============================================================
   FINAL
   ============================================================ */
SELECT
    c.sales_date,

    COALESCE(ts.total_sales, 0)
        AS total_sales,

    COALESCE(ca.campaign_ai_sales, 0)
        +
    COALESCE(nc.noncampaign_ai_sales, 0)
        AS ai_sales,

--     COALESCE(ca.campaign_ai_sales, 0)
--         AS campaign_ai_sales,
--
--     COALESCE(nc.noncampaign_ai_sales, 0)
--         AS noncampaign_ai_sales,

    CASE
        WHEN COALESCE(ts.total_sales, 0) = 0
            THEN NULL

        ELSE ROUND(
            CAST(
                COALESCE(ca.campaign_ai_sales, 0)
                +
                COALESCE(nc.noncampaign_ai_sales, 0)
                AS DECIMAL(18,6)
            )
            * 100.0
            /
            CAST(
                ts.total_sales
                AS DECIMAL(18,6)
            ),
            2
        )
    END AS ai_sales_rate

FROM calendar c

LEFT JOIN daily_total_sales ts
  ON ts.sales_date = c.sales_date

LEFT JOIN campaign_daily ca
  ON ca.sales_date = c.sales_date

LEFT JOIN noncampaign_daily nc
  ON nc.sales_date = c.sales_date

ORDER BY
    c.sales_date;

-- ai매출 건별 상세
/* ============================================================
   AI 매출 상세 근거 - DEAL 단위
   Amazon Redshift

   입력
     :store_no BIGINT
     :month    VARCHAR(7)       -- 예: '2026-07'

   AI 매출 정의
     1. CAMPAIGN
        캠페인 대상 고객이 캠페인 쿠폰 유효기간 내 발생시킨 매출

     2. NON_CAMPAIGN
        캠페인 쿠폰이 아닌 쿠폰 또는 포인트 사용 주문 매출

   중요
     - 현재 일별 AI매출 쿼리와 동일한 산정 로직
     - AI금액을 먼저 확정한 후 deal_id 단위 집계
     - 상품/테이블/전화번호는 마지막에 표시용으로 조인
     - CAMPAIGN + NON_CAMPAIGN에 동시에 해당하면 둘 다 합산
       → 현재 KPI의 nc.sales + ccs.sales와 동일

   최종
     SUM(sales_amount)
       = 월 일별 집계의 SUM(ai_sales)
   ============================================================ */

WITH

/* ============================================================
   PARAMS
   ============================================================ */
p0 AS (
    SELECT
        CAST(:store_no AS BIGINT) AS store_no,

        CAST(
            TO_DATE(
                CAST(:month AS VARCHAR(7)) || '-01',
                'YYYY-MM-DD'
            )
            AS DATE
        ) AS month_start_kst
),

p AS (
    SELECT
        p0.*,

        CAST(
            DATEADD(
                month,
                1,
                month_start_kst
            )
            AS DATE
        ) AS next_month_start_kst,

        CONVERT_TIMEZONE(
            'Asia/Seoul',
            'UTC',
            CAST(month_start_kst AS TIMESTAMP)
        ) AS month_start_utc_ts,

        CONVERT_TIMEZONE(
            'Asia/Seoul',
            'UTC',
            CAST(
                DATEADD(
                    month,
                    1,
                    month_start_kst
                )
                AS TIMESTAMP
            )
        ) AS next_month_start_utc_ts

    FROM p0
),

bounds AS (
    SELECT
        p.*,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                month_start_utc_ts
            )
            AS BIGINT
        ) AS month_start_epoch,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                next_month_start_utc_ts
            )
            AS BIGINT
        ) AS next_month_start_epoch

    FROM p
),

/* ============================================================
   THIS MONTH 정상 Deal
   ============================================================ */
current_deal AS (
    SELECT
        dl.store_no,
        dl.deal_id,
        dl.reg_dt

    FROM pos.tb_deal dl

    WHERE dl.store_no =
          (SELECT store_no FROM bounds)

      AND dl.reg_dt >=
          (SELECT month_start_epoch FROM bounds)

      AND dl.reg_dt <
          (SELECT next_month_start_epoch FROM bounds)

      AND dl.deal_status = 'OPRS_006'
),

/* ============================================================
   THIS MONTH 정상 Order Item

   일별 집계 current_order_item과 동일
   ============================================================ */
current_order_item AS (
    SELECT
        doi.store_no,
        doi.deal_id,
        doi.order_id,
        doi.menu_no,
        doi.reg_dt,
        doi.total_price

    FROM pos.tb_deal_order_item doi

    WHERE doi.store_no =
          (SELECT store_no FROM bounds)

      AND doi.reg_dt >=
          (SELECT month_start_epoch FROM bounds)

      AND doi.reg_dt <
          (SELECT next_month_start_epoch FROM bounds)

      AND doi.order_item_status = 'OPRS_006'
      AND doi.deleted_yn = FALSE
),

/* ============================================================
   캠페인 발급 쿠폰 user_coupon ID

   NON_CAMPAIGN 판정용
   ============================================================ */
campaign_discount_ref AS (
    SELECT DISTINCT
        uc.id AS discount_ref_id

    FROM table_order.user_coupon uc

    JOIN sellup.campaign cp
      ON cp.coupon_id = uc.coupon_id
     AND cp.store_no = uc.store_no

    WHERE cp.store_no =
          (SELECT store_no FROM bounds)

      AND cp.coupon_id IS NOT NULL
),

/* ============================================================
   NON_CAMPAIGN 할인 대상

   현재 일별 집계 discount_base와 동일
   ============================================================ */
discount_base AS (
    SELECT DISTINCT
        dd.store_no,
        dd.deal_id,
        dd.order_id

    FROM table_order.deal_discount dd

    LEFT JOIN campaign_discount_ref cdr
      ON cdr.discount_ref_id = dd.discount_ref_id

    WHERE dd.store_no =
          (SELECT store_no FROM bounds)

      AND dd.created_at >=
          (SELECT month_start_utc_ts FROM bounds)

      AND dd.created_at <
          (SELECT next_month_start_utc_ts FROM bounds)

      AND dd.discount_type IN (
          'COUPON',
          'POINT'
      )

      AND dd.discount_amount > 0

      AND (
            dd.discount_type = 'POINT'

            OR

            (
                dd.discount_type = 'COUPON'
                AND cdr.discount_ref_id IS NULL
            )
          )
),

/* ============================================================
   NON_CAMPAIGN AI 매출 원본

   중요:
     order_id = 0 → 해당 deal 전체
     order_id != 0 → 해당 order만

   일별 집계와 동일
   ============================================================ */
noncampaign_ai_item AS (
    SELECT
        db.store_no,
        coi.deal_id,
        coi.order_id,
        coi.reg_dt,
        coi.total_price

    FROM discount_base db

    JOIN current_deal cd
      ON cd.store_no = db.store_no
     AND cd.deal_id = db.deal_id

    JOIN current_order_item coi
      ON coi.store_no = db.store_no
     AND coi.deal_id = db.deal_id

     AND (
            db.order_id = 0
            OR coi.order_id = db.order_id
         )
),

/* ============================================================
   NON_CAMPAIGN deal 단위

   여기서 금액을 먼저 확정
   ============================================================ */
noncampaign_deal_sales AS (
    SELECT
        store_no,
        deal_id,

        CAST(
            SUM(total_price)
            AS BIGINT
        ) AS sales_amount

    FROM noncampaign_ai_item

    GROUP BY
        store_no,
        deal_id
),

/* ============================================================
   CAMPAIGN BASE
   ============================================================ */
campaign_base AS (
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.store_no,
        c.coupon_id

    FROM sellup.campaign c

    WHERE c.store_no =
          (SELECT store_no FROM bounds)

      AND c.coupon_id IS NOT NULL
),

campaign_coupon_key AS (
    SELECT DISTINCT
        store_no,
        coupon_id

    FROM campaign_base
),

/* ============================================================
   캠페인 쿠폰 유효기간 ∩ 조회월
   ============================================================ */
campaign_coupon_window AS (
    SELECT
        ck.store_no,
        ck.coupon_id,

        GREATEST(
            MIN(cp.created_at),
            (SELECT month_start_utc_ts FROM bounds)
        ) AS win_start_utc,

        LEAST(
            MAX(uc.expire_at),
            (SELECT next_month_start_utc_ts FROM bounds)
        ) AS win_end_utc

    FROM campaign_coupon_key ck

    JOIN table_order.coupon cp
      ON cp.store_no = ck.store_no
     AND cp.id = ck.coupon_id

    JOIN table_order.user_coupon uc
      ON uc.store_no = ck.store_no
     AND uc.coupon_id = ck.coupon_id

    GROUP BY
        ck.store_no,
        ck.coupon_id
),

campaign_coupon_window_epoch AS (
    SELECT
        store_no,
        coupon_id,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                CAST(win_start_utc AS TIMESTAMP)
            )
            AS BIGINT
        ) AS win_start_epoch,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                CAST(win_end_utc AS TIMESTAMP)
            )
            AS BIGINT
        ) AS win_end_epoch

    FROM campaign_coupon_window

    WHERE win_start_utc < win_end_utc
),

/* ============================================================
   CAMPAIGN TARGET

   DISTINCT 넣지 않음.
   현재 AI 매출 집계와 동일하게 campaign_user 구조 유지.
   ============================================================ */
campaign_target AS (
    SELECT
        cb.campaign_id,
        cb.campaign_name,
        cb.store_no,
        cu.user_id,

        cw.win_start_epoch,
        cw.win_end_epoch

    FROM campaign_base cb

    JOIN sellup.campaign_user cu
      ON cu.campaign_id = cb.campaign_id
     AND cu.holdout = FALSE

    JOIN campaign_coupon_window_epoch cw
      ON cw.store_no = cb.store_no
     AND cw.coupon_id = cb.coupon_id
),

/* ============================================================
   STORE POINTS

   DISTINCT 금지.
   현재 AI 매출 집계와 동일
   ============================================================ */
store_points AS (
    SELECT
        up.store_no,
        up.user_id,
        up.order_id

    FROM table_order.user_points up

    WHERE up.store_no =
          (SELECT store_no FROM bounds)

      AND up.change_type = 'ACCUMULATE'
),

/* ============================================================
   CAMPAIGN AI 매출 원본

   일별 AI 집계와 동일
   ============================================================ */
campaign_ai_item AS (
    SELECT
        ct.store_no,
        ct.campaign_id,
        ct.campaign_name,

        coi.deal_id,
        coi.order_id,
        coi.reg_dt,
        coi.total_price

    FROM campaign_target ct

    JOIN store_points up
      ON up.store_no = ct.store_no
     AND up.user_id = ct.user_id

    JOIN current_order_item coi
      ON coi.store_no = up.store_no
     AND coi.order_id = up.order_id

    JOIN current_deal cd
      ON cd.store_no = coi.store_no
     AND cd.deal_id = coi.deal_id

     AND cd.reg_dt >= ct.win_start_epoch
     AND cd.reg_dt <= ct.win_end_epoch
),

/* ============================================================
   CAMPAIGN deal 단위

   금액을 먼저 확정
   ============================================================ */
campaign_deal_sales AS (
    SELECT
        store_no,
        deal_id,

        CAST(
            SUM(total_price)
            AS BIGINT
        ) AS sales_amount

    FROM campaign_ai_item

    GROUP BY
        store_no,
        deal_id
),

/* ============================================================
   deal별 캠페인명
   표시용일 뿐 금액 계산에 관여하지 않음
   ============================================================ */
campaign_deal_names AS (
    SELECT
        store_no,
        deal_id,

        LISTAGG(
            DISTINCT campaign_name,
            ', '
        )
        WITHIN GROUP (
            ORDER BY campaign_name
        ) AS campaign_name

    FROM campaign_ai_item

    WHERE campaign_name IS NOT NULL

    GROUP BY
        store_no,
        deal_id
),

/* ============================================================
   AI EVENT

   현재 KPI:
       campaign + noncampaign

   를 그대로 UNION ALL
   ============================================================ */
ai_deal_event AS (

    SELECT
        store_no,
        deal_id,

        CAST(
            'CAMPAIGN'
            AS VARCHAR(20)
        ) AS ai_type,

        sales_amount

    FROM campaign_deal_sales

    UNION ALL

    SELECT
        store_no,
        deal_id,

        CAST(
            'NON_CAMPAIGN'
            AS VARCHAR(20)
        ) AS ai_type,

        sales_amount

    FROM noncampaign_deal_sales
),

/* ============================================================
   최종 AI매출을 DEAL 한 줄로 합산

   같은 deal이 양쪽이면:
       CAMPAIGN + NON_CAMPAIGN

   금액도 둘을 합산.
   ============================================================ */
ai_deal_sales AS (
    SELECT
        store_no,
        deal_id,

        CAST(
            SUM(sales_amount)
            AS BIGINT
        ) AS sales_amount,

        MAX(
            CASE
                WHEN ai_type = 'CAMPAIGN'
                THEN 1
                ELSE 0
            END
        ) AS campaign_flag,

        MAX(
            CASE
                WHEN ai_type = 'NON_CAMPAIGN'
                THEN 1
                ELSE 0
            END
        ) AS noncampaign_flag

    FROM ai_deal_event

    GROUP BY
        store_no,
        deal_id
),

/* ============================================================
   주문시간
   표시용.

   deal 시작시각을 사용.
   AI 금액 산정에는 영향 없음.
   ============================================================ */
deal_time AS (
    SELECT
        cd.store_no,
        cd.deal_id,

        CONVERT_TIMEZONE(
            'UTC',
            'Asia/Seoul',
            DATEADD(
                second,
                cd.reg_dt,
                TIMESTAMP '1970-01-01 00:00:00'
            )
        ) AS order_date

    FROM current_deal cd
),

/* ============================================================
   전화번호 마지막 4자리

   deal 단위 1행화 후 조인 → 매출 증식 없음
   ============================================================ */
deal_phone AS (
    SELECT
        o.store_no,
        o.deal_id,

        MAX(
            RIGHT(
                COALESCE(
                    NULLIF(up.phone, ''),
                    NULLIF(u.phone, '')
                ),
                4
            )
        ) AS phone_last4

    FROM pos.tb_deal_order o

    JOIN table_order.user_points up
      ON up.store_no = o.store_no
     AND up.order_id = o.order_id
     AND up.change_type = 'ACCUMULATE'

    LEFT JOIN table_order.users u
      ON u.id = up.user_id

    WHERE o.store_no =
          (SELECT store_no FROM bounds)

      AND o.deleted_yn = FALSE

    GROUP BY
        o.store_no,
        o.deal_id
),

/* ============================================================
   테이블 정보

   deal 단위 1행화
   ============================================================ */
deal_table AS (
    SELECT
        o.store_no,
        o.deal_id,

        MAX(
            gr.resource_name
        ) AS table_name

    FROM pos.tb_deal_order o

    LEFT JOIN pos.tb_ground_resource gr
      ON gr.store_no = o.store_no
     AND gr.resource_id = o.resource_id
     AND gr.deleted_yn = FALSE

    WHERE o.store_no =
          (SELECT store_no FROM bounds)

      AND o.deleted_yn = FALSE

    GROUP BY
        o.store_no,
        o.deal_id
),

/* ============================================================
   상품별 deal 매출

   0원 메뉴 제외.
   메뉴를 deal 내 금액 기준으로 먼저 합산.
   ============================================================ */
deal_menu_sales AS (
    SELECT
        coi.store_no,
        coi.deal_id,
        coi.menu_no,

        MAX(
            NULLIF(
                TRIM(m.menu_nm),
                ''
            )
        ) AS menu_name,

        SUM(
            coi.total_price
        ) AS menu_sales

    FROM current_order_item coi

    LEFT JOIN public.tb_menu m
      ON m.store_no = coi.store_no
     AND m.menu_no = coi.menu_no

    WHERE coi.total_price > 0

    GROUP BY
        coi.store_no,
        coi.deal_id,
        coi.menu_no
),

/* ============================================================
   대표상품 선정

   deal에서 금액이 가장 큰 메뉴를 대표상품으로 사용
   ============================================================ */
deal_menu_ranked AS (
    SELECT
        dms.*,

        ROW_NUMBER()
        OVER (
            PARTITION BY
                store_no,
                deal_id

            ORDER BY
                menu_sales DESC,
                menu_name
        ) AS rn,

        COUNT(*)
        OVER (
            PARTITION BY
                store_no,
                deal_id
        ) AS menu_count

    FROM deal_menu_sales dms

    WHERE menu_name IS NOT NULL
),

deal_product AS (
    SELECT
        store_no,
        deal_id,

        MAX(
            CASE
                WHEN rn = 1
                THEN
                    CASE
                        WHEN menu_count > 1
                            THEN menu_name || ' 외'
                        ELSE menu_name
                    END
            END
        ) AS product

    FROM deal_menu_ranked

    GROUP BY
        store_no,
        deal_id
)

/* ============================================================
   FINAL

   1 deal = 1 row

   검증:
       SELECT SUM(sales_amount)
       FROM (이 쿼리)

   2026-07 데이터라면
       일별 SUM(ai_sales) = 상세 SUM(sales_amount)
   가 되어야 함.
   ============================================================ */
SELECT
    dt.order_date,

    COALESCE(
        dp.phone_last4,
        '----'
    ) AS customer,

    COALESCE(
        dtab.table_name,
        '-'
    ) AS table_name,

    COALESCE(
        prod.product,
        '-'
    ) AS product,

    ads.sales_amount
--        ,

--     CASE
--         WHEN ads.campaign_flag = 1
--          AND ads.noncampaign_flag = 1
--             THEN 'CAMPAIGN+NON_CAMPAIGN'
--
--         WHEN ads.campaign_flag = 1
--             THEN 'CAMPAIGN'
--
--         ELSE 'NON_CAMPAIGN'
--     END AS ai_type,
--
--     CASE
--         WHEN ads.campaign_flag = 1
--             THEN cdn.campaign_name
--         ELSE NULL
--     END AS campaign_name,
--
--     ads.deal_id

FROM ai_deal_sales ads

LEFT JOIN deal_time dt
  ON dt.store_no = ads.store_no
 AND dt.deal_id = ads.deal_id

LEFT JOIN deal_phone dp
  ON dp.store_no = ads.store_no
 AND dp.deal_id = ads.deal_id

LEFT JOIN deal_table dtab
  ON dtab.store_no = ads.store_no
 AND dtab.deal_id = ads.deal_id

LEFT JOIN deal_product prod
  ON prod.store_no = ads.store_no
 AND prod.deal_id = ads.deal_id

LEFT JOIN campaign_deal_names cdn
  ON cdn.store_no = ads.store_no
 AND cdn.deal_id = ads.deal_id

ORDER BY
    dt.order_date DESC,
    ads.deal_id DESC;