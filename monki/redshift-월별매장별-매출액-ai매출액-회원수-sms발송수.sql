/*
 * 매장별 / 월별 매출·AI매출·회원·SMS 현황
 * Amazon Redshift
 *
 * 파라미터 (KST 기준)
 *   :p_from_date  예) 2026-01-01
 *   :p_to_date    예) 2026-09-30
 *
 * 매출액:
 *   기존 매출업 대시보드와 동일하게
 *   pos.tb_deal_order_item.reg_dt 기준
 *   order_item_status = 'OPRS_006'
 *   SUM(total_price)
 *
 * 대상:
 *   tb_store.table_order_yn = true
 *
 * 제외매장:
 *   665, 653, 641, 644, 693, 702, 786
 *
 * 매출업사용여부:
 *   sellup.basic_info.is_active = true
 *
 * 출력:
 *   해당 월(부분월 포함)에 매출액 > 0인 매장만
 */

WITH RECURSIVE

/* ============================================================
 * 1. 파라미터
 * ============================================================ */
p AS (
    SELECT
        CAST(:p_from_date AS DATE) AS from_date,
        CAST(:p_to_date   AS DATE) AS to_date
),

/* ============================================================
 * 2. 전체 조회기간 KST
 *
 * p_to_date는 포함.
 * 따라서 다음날 00:00 미만으로 처리.
 * ============================================================ */
period AS (
    SELECT
        CAST(from_date AS TIMESTAMP) AS from_kst,
        CAST(
            DATEADD(day, 1, to_date)
            AS TIMESTAMP
        ) AS to_kst
    FROM p
),

/* ============================================================
 * 3. 조회기간의 월 생성
 * ============================================================ */
month_list(month_from_kst) AS (
    SELECT
        DATE_TRUNC('month', from_kst)
    FROM period

    UNION ALL

    SELECT
        DATEADD(
            month,
            1,
            ml.month_from_kst
        )
    FROM month_list ml
    CROSS JOIN period p
    WHERE DATEADD(
              month,
              1,
              ml.month_from_kst
          ) < p.to_kst
),

/* ============================================================
 * 4. 각 월의 실제 KST 집계범위
 *
 * 예: 2026-03-15 ~ 2026-06-20
 *
 * 3월 : 03/15 00:00 ~ 04/01 00:00
 * 4월 : 04/01 00:00 ~ 05/01 00:00
 * 5월 : 05/01 00:00 ~ 06/01 00:00
 * 6월 : 06/01 00:00 ~ 06/21 00:00
 * ============================================================ */
months_kst AS (
    SELECT
        ml.month_from_kst,

        GREATEST(
            ml.month_from_kst,
            p.from_kst
        ) AS range_from_kst,

        LEAST(
            DATEADD(
                month,
                1,
                ml.month_from_kst
            ),
            p.to_kst
        ) AS range_to_kst

    FROM month_list ml
    CROSS JOIN period p
),

/* ============================================================
 * 5. KST wall-clock → UTC TIMESTAMP
 * ============================================================ */
months_utc AS (
    SELECT
        month_from_kst,
        range_from_kst,
        range_to_kst,

        CONVERT_TIMEZONE(
            'Asia/Seoul',
            'UTC',
            range_from_kst
        ) AS range_from_utc_ts,

        CONVERT_TIMEZONE(
            'Asia/Seoul',
            'UTC',
            range_to_kst
        ) AS range_to_utc_ts

    FROM months_kst
),

/* ============================================================
 * 6. POS reg_dt 비교용 UTC epoch seconds
 * ============================================================ */
months AS (
    SELECT
        month_from_kst,
        range_from_kst,
        range_to_kst,
        range_from_utc_ts,
        range_to_utc_ts,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                range_from_utc_ts
            )
            AS BIGINT
        ) AS from_epoch,

        CAST(
            DATEDIFF(
                second,
                TIMESTAMP '1970-01-01 00:00:00',
                range_to_utc_ts
            )
            AS BIGINT
        ) AS to_epoch

    FROM months_utc
),

/* ============================================================
 * 7. 대상 매장
 *
 * 기존 기준 쿼리와 동일:
 * table_order_yn = true
 *
 * 요청한 6개 매장 제외
 * ============================================================ */
store_filter AS (
    SELECT
        s.store_no,
        s.store_nm

    FROM public.tb_store s

    WHERE s.table_order_yn = true
      AND s.store_no NOT IN (
          665,
          653,
          641,
          644,
          693,
          702,
          786
      )
),

/* ============================================================
 * 8. 월별 매출
 *
 * ★ 첨부한 기존 Redshift 쿼리 sales_agg와 동일한 기준
 *
 * pos.tb_deal_order_item.reg_dt 기준
 * order_item_status = 'OPRS_006'
 *
 * deal_status / order_status / deleted_yn 조건을
 * 추가하지 않는다.
 * ============================================================ */
monthly_sales AS (
    SELECT
        m.month_from_kst,
        doi.store_no,

        CAST(
            COALESCE(
                SUM(doi.total_price),
                0
            )
            AS BIGINT
        ) AS sales_amount

    FROM months m

    JOIN pos.tb_deal_order_item doi
      ON doi.reg_dt >= m.from_epoch
     AND doi.reg_dt <  m.to_epoch
     AND doi.order_item_status = 'OPRS_006'

    JOIN store_filter sf
      ON sf.store_no = doi.store_no

    GROUP BY
        m.month_from_kst,
        doi.store_no

    HAVING SUM(doi.total_price) > 0
),

/* ============================================================
 * 9. 실제 매출이 존재하는 매장/월
 *
 * 최종 리포트의 기준 테이블.
 * ============================================================ */
sales_store_months AS (
    SELECT
        ms.month_from_kst,
        ms.store_no,
        sf.store_nm,
        ms.sales_amount

    FROM monthly_sales ms

    JOIN store_filter sf
      ON sf.store_no = ms.store_no
),

/* ============================================================
 * 10. 매출업 활성 매장
 *
 * 기존 기준 쿼리와 동일:
 * basic_info.is_active = true
 * ============================================================ */
sellup_stores AS (
    SELECT DISTINCT
        bi.store_no

    FROM sellup.basic_info bi

    WHERE bi.is_active = true
),

/* ============================================================
 * 11. 비캠페인 CRM 대상 할인
 *
 * POINT
 *
 * 또는
 *
 * COUPON 중 sellup.campaign에서 생성한 쿠폰이 아닌 것
 *
 * 기존 nc_crm_sales 로직 유지
 * ============================================================ */
nc_discount_base AS (
    SELECT DISTINCT
        m.month_from_kst,
        dd.store_no,
        dd.deal_id,
        dd.order_id

    FROM months m

    JOIN table_order.deal_discount dd
      ON dd.created_at >= m.range_from_utc_ts
     AND dd.created_at <  m.range_to_utc_ts

    JOIN store_filter sf
      ON sf.store_no = dd.store_no

    WHERE dd.discount_type IN (
              'COUPON',
              'POINT'
          )

      AND dd.discount_amount > 0

      AND (
            dd.discount_type = 'POINT'

            OR (
                dd.discount_type = 'COUPON'

                AND NOT EXISTS (
                    SELECT 1

                    FROM table_order.user_coupon uc

                    JOIN sellup.campaign cp
                      ON cp.coupon_id = uc.coupon_id
                     AND cp.store_no  = uc.store_no

                    WHERE uc.id = dd.discount_ref_id
                )
            )
      )
),

/* ============================================================
 * 12. 월별 비캠페인 CRM 매출
 *
 * 첨부 기준 쿼리 nc_crm_sales와 동일한 집계 방식
 * ============================================================ */
monthly_nc_crm AS (
    SELECT
        b.month_from_kst,
        b.store_no,

        CAST(
            COALESCE(
                SUM(doi.total_price),
                0
            )
            AS BIGINT
        ) AS nc_crm_sales

    FROM nc_discount_base b

    JOIN pos.tb_deal dl
      ON dl.deal_id     = b.deal_id
     AND dl.store_no    = b.store_no
     AND dl.deal_status = 'OPRS_006'

    JOIN pos.tb_deal_order_item doi
      ON doi.deal_id            = b.deal_id
     AND doi.store_no           = b.store_no
     AND doi.order_item_status  = 'OPRS_006'
     AND doi.deleted_yn         = false
     AND (
            b.order_id = 0
            OR doi.order_id = b.order_id
         )

    GROUP BY
        b.month_from_kst,
        b.store_no
),

/* ============================================================
 * 13. 캠페인 쿠폰의 월별 유효 Window
 *
 * 기존 쿼리:
 *
 * GREATEST(MIN(coupon.created_at), 조회시작)
 * LEAST(MAX(user_coupon.expire_at), 조회종료)
 *
 * 를 각 월별로 적용.
 *
 * coupon.created_at / user_coupon.expire_at은 TIMESTAMPTZ.
 * ============================================================ */
campaign_coupon_window AS (
    SELECT
        m.month_from_kst,
        cp.store_no,
        uc.coupon_id,

        GREATEST(
            MIN(cp.created_at),
            m.range_from_utc_ts
        ) AS win_start_utc,

        LEAST(
            MAX(uc.expire_at),
            m.range_to_utc_ts
        ) AS win_end_utc

    FROM months m

    CROSS JOIN table_order.coupon cp

    JOIN table_order.user_coupon uc
      ON uc.coupon_id = cp.id
     AND uc.store_no  = cp.store_no

    JOIN store_filter sf
      ON sf.store_no = cp.store_no

    GROUP BY
        m.month_from_kst,
        cp.store_no,
        uc.coupon_id,
        m.range_from_utc_ts,
        m.range_to_utc_ts
),

/* ============================================================
 * 14. 캠페인 Window → UTC epoch
 *
 * 기존 기준 쿼리와 동일하게
 * TIMESTAMPTZ → TIMESTAMP CAST 후 DATEDIFF.
 * ============================================================ */
campaign_coupon_window_epoch AS (
    SELECT
        month_from_kst,
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
 * 15. 월별 캠페인 CRM 매출
 *
 * 기존 campaign_crm_sales 로직 유지
 * ============================================================ */
monthly_campaign_crm AS (
    SELECT
        cw.month_from_kst,
        c.store_no,

        CAST(
            COALESCE(
                SUM(doi.total_price),
                0
            )
            AS BIGINT
        ) AS campaign_crm_sales

    FROM sellup.campaign_user cu

    JOIN sellup.campaign c
      ON c.campaign_id = cu.campaign_id

    JOIN store_filter sf
      ON sf.store_no = c.store_no

    JOIN campaign_coupon_window_epoch cw
      ON cw.coupon_id = c.coupon_id
     AND cw.store_no  = c.store_no

    JOIN pos.tb_deal dl
      ON dl.store_no    = c.store_no
     AND dl.deal_status = 'OPRS_006'

    JOIN pos.tb_deal_order tdo
      ON tdo.deal_id  = dl.deal_id
     AND tdo.store_no = dl.store_no

    LEFT JOIN table_order.user_points up
      ON up.store_no    = dl.store_no
     AND up.order_id    = tdo.order_id
     AND up.change_type = 'ACCUMULATE'

    JOIN pos.tb_deal_order_item doi
      ON doi.store_no          = tdo.store_no
     AND doi.order_id          = tdo.order_id
     AND doi.order_item_status = 'OPRS_006'

    WHERE cu.holdout = false

      AND up.user_id = cu.user_id

      AND dl.reg_dt >= cw.win_start_epoch
      AND dl.reg_dt <= cw.win_end_epoch

    GROUP BY
        cw.month_from_kst,
        c.store_no
),

/* ============================================================
 * 16. AI 매출 구성
 *
 * 비캠페인 CRM
 * +
 * 캠페인 CRM
 * ============================================================ */
ai_sales_parts AS (
    SELECT
        month_from_kst,
        store_no,
        nc_crm_sales AS ai_sales_amount

    FROM monthly_nc_crm

    UNION ALL

    SELECT
        month_from_kst,
        store_no,
        campaign_crm_sales AS ai_sales_amount

    FROM monthly_campaign_crm
),

/* ============================================================
 * 17. 월별 AI 매출
 * ============================================================ */
monthly_ai_sales AS (
    SELECT
        month_from_kst,
        store_no,

        CAST(
            SUM(ai_sales_amount)
            AS BIGINT
        ) AS ai_sales_amount

    FROM ai_sales_parts

    GROUP BY
        month_from_kst,
        store_no
),

/* ============================================================
 * 18. 월별 SMS 발송 건수
 * ============================================================ */
monthly_sms AS (
    SELECT
        m.month_from_kst,
        ssl.store_no,

        COUNT(*) AS sms_count

    FROM months m

    JOIN table_order.sms_send_log ssl
      ON ssl.created_at >= m.range_from_utc_ts
     AND ssl.created_at <  m.range_to_utc_ts

    JOIN store_filter sf
      ON sf.store_no = ssl.store_no

    GROUP BY
        m.month_from_kst,
        ssl.store_no
),

/* ============================================================
 * 19. 월별 누적 회원수
 *
 * 기존 대시보드 member_count 기준:
 *
 * created_at < 조회종료
 * deleted_at IS NULL
 * COUNT(*)
 *
 * 조회 첫/마지막 월이 부분월이면
 * 해당 실제 range_to 시점까지의 회원수.
 * ============================================================ */
monthly_members AS (
    SELECT
        m.month_from_kst,
        us.store_no,

        CAST(
            COUNT(*)
            AS BIGINT
        ) AS member_count

    FROM months m

    JOIN table_order.user_stores us
      ON us.created_at < m.range_to_utc_ts
     AND us.deleted_at IS NULL

    JOIN store_filter sf
      ON sf.store_no = us.store_no

    GROUP BY
        m.month_from_kst,
        us.store_no
),

/* ============================================================
 * 20. 최종 결합
 *
 * sales_store_months가 BASE.
 *
 * 따라서 매출 없는 매장/월은 결과에 없음.
 * ============================================================ */
report AS (
    SELECT
        sm.store_no,
        sm.store_nm,
        sm.month_from_kst,

        sm.sales_amount,

        COALESCE(
            ai.ai_sales_amount,
            0
        ) AS ai_sales_amount,

        COALESCE(
            mm.member_count,
            0
        ) AS member_count,

        COALESCE(
            sms.sms_count,
            0
        ) AS sms_count,

        CASE
            WHEN su.store_no IS NOT NULL
                THEN 'Y'
            ELSE 'N'
        END AS sellup_used

    FROM sales_store_months sm

    LEFT JOIN monthly_ai_sales ai
      ON ai.store_no = sm.store_no
     AND ai.month_from_kst = sm.month_from_kst

    LEFT JOIN monthly_members mm
      ON mm.store_no = sm.store_no
     AND mm.month_from_kst = sm.month_from_kst

    LEFT JOIN monthly_sms sms
      ON sms.store_no = sm.store_no
     AND sms.month_from_kst = sm.month_from_kst

    LEFT JOIN sellup_stores su
      ON su.store_no = sm.store_no
)

/* ============================================================
 * 21. 최종 결과
 * ============================================================ */
SELECT
    store_no AS "매장코드",

    store_nm AS "매장명",

    TO_CHAR(
        month_from_kst,
        'YYYY-MM'
    ) AS "년월",

    sales_amount AS "매출액",

    ai_sales_amount AS "ai매출액",

    CAST(
        ROUND(
            CAST(
                ai_sales_amount
                AS DECIMAL(28, 6)
            )
            /
            NULLIF(
                sales_amount,
                0
            )
            * 100,
            2
        )
        AS DECIMAL(28, 2)
    ) AS "ai매출비중",

    member_count AS "회원수",

    sms_count AS "sms발송건수",

    CAST(
        ROUND(
            CAST(
                sms_count
                AS DECIMAL(28, 6)
            )
            /
            NULLIF(
                member_count,
                0
            ),
            2
        )
        AS DECIMAL(28, 2)
    ) AS "회원당sms발송건수",

    sellup_used AS "매출업사용여부"

FROM report

ORDER BY
    store_no,
    month_from_kst;