-- campaign_briefing_roi 원본 SQL (변경 전)
-- 출처: 세션 c3e63c78 (2026-03-04), line 627
-- 이 시점에서 seg_lib_sql에서 조회한 원본 그대로입니다.
-- 변경점: params CTE의 month_end_kst, month_end_utc가 월말 고정
--

WITH
params AS (
  SELECT
    :store_no::bigint AS store_no,
    :base_date::date  AS base_date,

    14::int AS h_days,
    0::int  AS sms_cost_per_send,  -- 필요시 조정

    -- KST 기준: 해당 월의 1일 ~ 말일
    date_trunc('month', :base_date::date)::date AS month_start_kst,
    (
      date_trunc('month', :base_date::date)
      + INTERVAL '1 month'
      - INTERVAL '1 day'
    )::date AS month_end_kst,

    -- KST 00:00 기준 epoch: [month_start_utc, month_end_utc) = 그 달 전체
    EXTRACT(
      EPOCH FROM (
        (date_trunc('month', :base_date::date))::timestamp
        AT TIME ZONE 'Asia/Seoul'
      )
    )::bigint AS month_start_utc,

    EXTRACT(
      EPOCH FROM (
        (
          (date_trunc('month', :base_date::date)
           + INTERVAL '1 month'
          )::date::timestamp
        ) AT TIME ZONE 'Asia/Seoul'
      )
    )::bigint AS month_end_utc,

    (now() AT TIME ZONE 'Asia/Seoul') AS now_kst
),

/* 0) 캠페인별 쿠폰 발급/만료 범위 (KST 기준) */
coupon_bounds AS (
  SELECT
    c.campaign_id,
    c.store_no,
    any_value(cp.created_at AT TIME ZONE 'Asia/Seoul') AS first_issue_kst,
    any_value(uc.expire_at AT TIME ZONE 'Asia/Seoul') AS last_expire_kst
  FROM sellup.campaign c
  JOIN params p
    ON p.store_no = c.store_no
      JOIN table_order.coupon cp
      ON c.coupon_id=cp.id AND p.store_no=cp.store_no
  JOIN table_order.user_coupon uc
    ON uc.coupon_id = cp.id
   AND uc.store_no  = p.store_no
  GROUP BY c.campaign_id, c.store_no
),

/* 1) 조회 대상 캠페인: \"쿠폰 유효기간\"이 [month_start, month_end] 와 1일이라도 겹침 */
selected_campaigns AS (
  SELECT
    c.campaign_id,
    c.store_no,
    c.campaign_name,
    c.category,
    c.coupon_id,
    c.exec_date,
    c.targets->>'target_name'   AS target_name,
    c.offers->>'coupon_name'    AS coupon_name,
    COALESCE((c.offers->>'ttl_days')::int, 1) AS ttl_days,

    -- 쿠폰 기준 캠페인 시작/종료 (KST)
    cb.first_issue_kst AS sent_at_kst,
    cb.last_expire_kst AS expires_at_kst
  FROM sellup.campaign c
  JOIN params p
    ON p.store_no = c.store_no
  JOIN coupon_bounds cb
    ON cb.campaign_id = c.campaign_id
  WHERE
    cb.last_expire_kst::date  >= p.month_start_kst   -- 만료일이 월 시작 이후
    AND cb.first_issue_kst::date <= p.month_end_kst  -- 발급 시작이 base_date 이전
),

/* 2) 캠페인별 실제 집계 기간 (쿠폰 기간 ∩ [month_start, base_date]) */
campaign_window AS (
  SELECT
    sc.campaign_id,
    sc.store_no,
    sc.campaign_name,
    sc.category,
    sc.target_name,
    sc.coupon_id,
    sc.coupon_name,
    sc.exec_date,
    sc.ttl_days,

    -- 원본 timestamp
    sc.sent_at_kst,
    sc.expires_at_kst,

    -- 보고용 시작/끝 날짜
    sc.sent_at_kst::date                        AS sent_date_kst,
    (sc.expires_at_kst - INTERVAL '1 second')::date AS end_date_kst,

    -- 조회 기간과의 교집합
    GREATEST(sc.sent_at_kst,
             p.month_start_kst) AS win_start_kst,
    LEAST((sc.expires_at_kst - INTERVAL '1 second'),
--       LEAST((DATE(sc.expires_at_kst) + INTERVAL '23 hours 59 minutes 59 seconds'),
          p.month_end_kst)      AS win_end_kst
  FROM selected_campaigns sc
  JOIN params p
    ON p.store_no = sc.store_no
),

/* 3) 캠페인 대상 유저 */
campaign_users AS (
  SELECT
    cu.campaign_id,
    cu.user_id,
    cu.holdout
  FROM sellup.campaign_user cu
  JOIN campaign_window cw
    ON cw.campaign_id = cu.campaign_id
),
treated_users AS (
  SELECT campaign_id, user_id
  FROM campaign_users
  WHERE holdout = FALSE
),
control_users AS (
  SELECT campaign_id, user_id
  FROM campaign_users
  WHERE holdout = TRUE
),

/* treated_users(발송유저수) */
treated_counts AS (
  SELECT
    campaign_id,
    COUNT(DISTINCT user_id)::int AS treated_users
  FROM treated_users
  GROUP BY campaign_id
),

/* 4) [1일 ~ base_date] 전체 주문(회원 기준) – 이후 캠페인 window로 필터 */
all_deal_user AS (
  SELECT
    dl.store_no,
    dl.deal_id,
    dl.reg_dt,
    (to_timestamp(dl.reg_dt) AT TIME ZONE 'Asia/Seoul')       AS order_time_kst,
    (to_timestamp(dl.reg_dt) AT TIME ZONE 'Asia/Seoul')::date AS order_date_kst,
    up.user_id,
    SUM(doi.total_price)::bigint AS order_total
  FROM pos.tb_deal dl
  JOIN pos.tb_deal_order tdo
    ON dl.deal_id = tdo.deal_id
  LEFT JOIN table_order.user_points up
    ON up.store_no    = dl.store_no
   AND up.order_id    = tdo.order_id
   AND up.change_type = 'ACCUMULATE'
  JOIN pos.tb_deal_order_item doi
    ON doi.store_no         = tdo.store_no
   AND doi.order_id         = tdo.order_id
   AND doi.order_item_status = 'OPRS_006'
  JOIN params p
    ON p.store_no = dl.store_no
  WHERE
    dl.store_no   = p.store_no
    AND dl.deal_status = 'OPRS_006'
    AND dl.reg_dt >= p.month_start_utc
    AND dl.reg_dt <  p.month_end_utc
  GROUP BY
    dl.store_no,
    dl.deal_id,
    dl.reg_dt,
    up.user_id
),

/* 5) treated: 캠페인 window 내 매출 */
treated_user_deals AS (
  SELECT
    tu.campaign_id,
    du.user_id,
    du.deal_id,
    du.order_total
  FROM treated_users tu
  JOIN campaign_window cw
    ON cw.campaign_id = tu.campaign_id
  JOIN all_deal_user du
    ON du.user_id = tu.user_id
   AND du.order_time_kst BETWEEN cw.win_start_kst AND cw.win_end_kst
),
treated_sales AS (
  SELECT
    tud.campaign_id,
    SUM(tud.order_total)::bigint AS treated_sales_amount,
    COUNT(DISTINCT tud.user_id)  AS treated_sales_users
  FROM treated_user_deals tud
  GROUP BY tud.campaign_id
),

/* 6) treated 쿠폰 사용: 캠페인 window 내 사용만 */
coupon_stats AS (
  SELECT
    cw.campaign_id,
    COUNT(DISTINCT uc.id)::int      AS coupon_used_count,
    SUM(dd.discount_amount)::bigint AS cost
  FROM campaign_window cw
  JOIN params p
    ON p.store_no = cw.store_no
  JOIN treated_users tu
    ON tu.campaign_id = cw.campaign_id
  JOIN table_order.user_coupon uc
    ON uc.user_id    = tu.user_id
   AND uc.coupon_id  = cw.coupon_id
   AND uc.use_status = 'USED'
   AND uc.store_no   = p.store_no
   AND uc.order_id  <> 0
   AND (uc.used_at AT TIME ZONE 'Asia/Seoul')::date
         BETWEEN cw.win_start_kst AND cw.win_end_kst
  JOIN table_order.deal_discount dd
    ON dd.discount_ref_id = uc.id
   AND dd.discount_type   = 'COUPON'
   AND dd.discount_amount > 0
   AND dd.store_no        = p.store_no
  GROUP BY cw.campaign_id
),

/* 7) control: 여러 캠페인 참여 → 1/N 분배용 */
control_memberships AS (
  SELECT DISTINCT
    cu.user_id,
    cu.campaign_id
  FROM control_users cu
),
control_campaign_counts AS (
  SELECT
    user_id,
    COUNT(*)::int AS campaign_cnt
  FROM control_memberships
  GROUP BY user_id
),

/* control_users(홀드유저수) */
control_counts AS (
  SELECT
    campaign_id,
    COUNT(DISTINCT user_id)::int AS control_users
  FROM control_users
  GROUP BY campaign_id
),

/* 8) control 유저의 캠페인 window 내 매출 */
control_user_deals AS (
  SELECT
    cu.campaign_id,
    cu.user_id,
    du.deal_id,
    du.order_total
  FROM control_users cu
  JOIN campaign_window cw
    ON cw.campaign_id = cu.campaign_id
  JOIN all_deal_user du
    ON du.user_id = cu.user_id
   AND du.order_date_kst BETWEEN cw.win_start_kst AND cw.win_end_kst
),

control_user_sales_by_campaign AS (
  SELECT
    cud.campaign_id,
    cud.user_id,
    SUM(cud.order_total)::numeric AS sales_amount
  FROM control_user_deals cud
  GROUP BY cud.campaign_id, cud.user_id
),

control_user_sales_weighted AS (
  SELECT
    cus.campaign_id,
    cus.user_id,
    CASE
      WHEN ccc.campaign_cnt > 0
      THEN cus.sales_amount / ccc.campaign_cnt
      ELSE 0
    END AS weighted_sales_amount
  FROM control_user_sales_by_campaign cus
  JOIN control_campaign_counts ccc
    ON ccc.user_id = cus.user_id
),

control_sales AS (
  SELECT
    campaign_id,
    COALESCE(SUM(weighted_sales_amount), 0)::bigint AS control_sales_amount
  FROM control_user_sales_weighted
  GROUP BY campaign_id
),

control_sales_users_cte AS (
  SELECT
    campaign_id,
    COUNT(
      DISTINCT CASE WHEN weighted_sales_amount > 0 THEN user_id END
    )::int AS control_sales_users
  FROM control_user_sales_weighted
  GROUP BY campaign_id
),

/* 9) 월(1일~base_date) 전체 매출 (denominator) */
month_deal_total AS (
  SELECT
    doi.store_no,
    doi.deal_id,
    SUM(doi.total_price)::bigint AS order_total
  FROM pos.tb_deal_order_item doi
  JOIN params p
    ON p.store_no = doi.store_no
  WHERE
    doi.reg_dt >= p.month_start_utc
    AND doi.reg_dt <  p.month_end_utc
    AND doi.order_item_status = 'OPRS_006'
  GROUP BY doi.store_no, doi.deal_id
),
month_sales AS (
  SELECT COALESCE(SUM(mdt.order_total),0)::bigint AS month_total_sales
  FROM month_deal_total mdt
),

/* 10) 캠페인별 ROI 집계 */
per_campaign AS (
  SELECT
    cw.campaign_id,
    cw.campaign_name,
    cw.category,
    cw.target_name,
    cw.coupon_name,
    cw.coupon_id,
    cw.exec_date AS exec_date,
    cw.sent_date_kst AS sent_date,
    cw.end_date_kst  AS end_date,

    COALESCE(tcnt.treated_users, 0)        AS treated_target_count,
    COALESCE(ts.treated_sales_users, 0)    AS treated_sales_users,
    COALESCE(cc.control_users, 0)          AS control_users,
    COALESCE(css.control_sales_users, 0)   AS control_sales_users,

    COALESCE(ts.treated_sales_amount, 0)   AS treated_sales,
    COALESCE(cts.control_sales_amount, 0)  AS control_sales,

    COALESCE(cs.coupon_used_count, 0)      AS coupon_used_count,
    COALESCE(cs.cost, 0)                   AS coupon_cost,

    -- SMS 비용: 발송 타겟 기준
    (COALESCE(tcnt.treated_users, 0)
       * (SELECT sms_cost_per_send FROM params)
    )::bigint AS sms_cost,

    (
      COALESCE(cs.cost, 0)
      + (COALESCE(tcnt.treated_users, 0)
           * (SELECT sms_cost_per_send FROM params)
        )::bigint
    )::bigint AS total_cost,

    -- 증분 매출: 쿠폰 사용 매출 유저 vs holdout 전체 인원
    CASE
      WHEN COALESCE(cc.control_users, 0) > 0 THEN
        (
          COALESCE(ts.treated_sales_amount, 0)
          - COALESCE(ts.treated_sales_users, 0) * (
              COALESCE(cts.control_sales_amount, 0)::numeric
              / NULLIF(cc.control_users, 0)
            )
        )::bigint
      ELSE COALESCE(ts.treated_sales_amount, 0)  -- control 없으면 treated 전액
    END AS incremental_sales,

    -- 순이익(=증분매출 - 비용)
    (
      COALESCE(
        CASE
          WHEN COALESCE(cc.control_users, 0) > 0 THEN
            (
              COALESCE(ts.treated_sales_amount, 0)
              - COALESCE(ts.treated_sales_users, 0) * (
                  COALESCE(cts.control_sales_amount, 0)::numeric
                  / NULLIF(cc.control_users, 0)
                )
            )::bigint
          ELSE COALESCE(ts.treated_sales_amount, 0)  -- control 없으면 treated 전액
        END,
        0
      )
      - (
          COALESCE(cs.cost, 0)
          + (COALESCE(tcnt.treated_users, 0)
               * (SELECT sms_cost_per_send FROM params)
            )::bigint
        )::bigint
    )::bigint AS roi_net
  FROM campaign_window cw
  LEFT JOIN treated_counts          tcnt ON tcnt.campaign_id = cw.campaign_id
  LEFT JOIN treated_sales           ts   ON ts.campaign_id   = cw.campaign_id
  LEFT JOIN coupon_stats            cs   ON cs.campaign_id   = cw.campaign_id
  LEFT JOIN control_counts          cc   ON cc.campaign_id   = cw.campaign_id
  LEFT JOIN control_sales           cts  ON cts.campaign_id  = cw.campaign_id
  LEFT JOIN control_sales_users_cte css  ON css.campaign_id  = cw.campaign_id
),

/* 11) uplift 비율 (월 매출 대비) */
per_campaign_w_ms AS (
  SELECT
    pc.*,
    ms.month_total_sales,
    CASE
      WHEN ms.month_total_sales > 0
      THEN ROUND(pc.incremental_sales::numeric / ms.month_total_sales * 100, 2)
      ELSE NULL
    END AS uplift_contrib_pct
  FROM per_campaign pc
  CROSS JOIN month_sales ms
),

/* 12) 월 단위 요약 (SUMMARY용) */
monthly AS (
  SELECT
    ms.month_total_sales,
    pcs.month_campaign_sales,
    pcs.month_incremental_sales,
    pcs.month_total_cost,
    (pcs.month_incremental_sales - pcs.month_total_cost)::bigint AS month_roi_net
  FROM month_sales ms
  CROSS JOIN (
    SELECT
      COALESCE(SUM(treated_sales),0)::bigint     AS month_campaign_sales,
      COALESCE(SUM(incremental_sales),0)::bigint AS month_incremental_sales,
      COALESCE(SUM(total_cost),0)::bigint        AS month_total_cost
    FROM per_campaign
  ) pcs
)

-- SUMMARY row
SELECT
  'SUMMARY'                         AS kind,
  NULL::uuid                        AS campaign_id,
  NULL::text                        AS campaign_name,
  NULL::text                        AS category,
  NULL::text                        AS target_name,
  NULL::text                        AS coupon_name,
  NULL::uuid                        AS coupon_id,
  NULL::date                        AS exec_date,
  NULL::date                        AS sent_date,
  NULL::date                        AS end_date,
  ms.month_total_sales              AS month_total_sales,
  ms.month_campaign_sales           AS month_campaign_sales,
  ms.month_incremental_sales        AS month_incremental_sales,
  ms.month_total_cost               AS month_total_cost,
  ms.month_roi_net                  AS month_roi_net,
  NULL::int                         AS treated_target_count,
  NULL::int                         AS treated_sales_users,
  NULL::int                         AS control_users,
  NULL::int                         AS control_sales_users,
  NULL::int                         AS coupon_used_count,
  NULL::bigint                      AS treated_sales,
  NULL::bigint                      AS control_sales,
  NULL::bigint                      AS incremental_sales,
  NULL::bigint                      AS coupon_cost,
  NULL::bigint                      AS sms_cost,
  NULL::bigint                      AS total_cost,
  NULL::bigint                      AS roi_net,
  NULL::numeric                     AS uplift_contrib_pct
FROM monthly ms

UNION ALL

-- CAMPAIGN rows
SELECT
  'CAMPAIGN'                        AS kind,
  pc.campaign_id,
  pc.campaign_name,
  pc.category,
  pc.target_name,
  pc.coupon_name,
  pc.coupon_id,
  pc.exec_date,
  pc.sent_date,
  pc.end_date,
  NULL::bigint                      AS month_total_sales,
  NULL::bigint                      AS month_campaign_sales,
  NULL::bigint                      AS month_incremental_sales,
  NULL::bigint                      AS month_total_cost,
  NULL::bigint                      AS month_roi_net,
  COALESCE(pc.treated_target_count,0)   AS treated_target_count,
  COALESCE(pc.treated_sales_users,0)    AS treated_sales_users,
  COALESCE(pc.control_users,0)          AS control_users,
  COALESCE(pc.control_sales_users,0)    AS control_sales_users,
  COALESCE(pc.coupon_used_count,0)      AS coupon_used_count,
  COALESCE(pc.treated_sales,0)          AS treated_sales,
  COALESCE(pc.control_sales,0)          AS control_sales,
  COALESCE(pc.incremental_sales,0)      AS incremental_sales,
  COALESCE(pc.coupon_cost,0)            AS coupon_cost,
  COALESCE(pc.sms_cost,0)               AS sms_cost,
  COALESCE(pc.total_cost,0)             AS total_cost,
  COALESCE(pc.roi_net,0)                AS roi_net,
  COALESCE(pc.uplift_contrib_pct,0)     AS uplift_contrib_pct
FROM per_campaign_w_ms pc
ORDER BY kind, campaign_name;

select * from table_order.coupon cp
         join table_order.user_coupon uc on cp.id=uc.coupon_id
         where cp.store_no=:store_no order by cp.created_at desc;