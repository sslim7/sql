WITH RECURSIVE
/* ── 파라미터 :from_month :to_month :store_nos — 실행 도구가 값을 묻거나(DataGrip·DBeaver) psql -v 로 넘긴다. 값은 따옴표 포함 문자열 ── */
params AS (
  SELECT CAST(:from_month AS text) AS from_month,   -- 시작 월 'YYYY-MM' (포함)        예: '2026-09'
         CAST(:to_month   AS text) AS to_month,     -- 끝 월   'YYYY-MM' (포함)        예: '2026-09'
         CAST(:store_nos  AS text) AS store_nos     -- 선택: '783,891' 쉼표 구분. '' 이면 전 매장
),
/* 조회 범위: KST 월 경계를 timestamp(KST)·timestamptz·epoch 세 형태로 */
bounds AS NOT MATERIALIZED (  -- 상수로 펼쳐 각 스캔의 인덱스·필터 조건이 되게 한다
  SELECT
    m_from::timestamp                                              AS from_kst,
    m_to_excl::timestamp                                           AS to_kst_excl,
    (m_from::timestamp    AT TIME ZONE 'Asia/Seoul')               AS from_ts,
    (m_to_excl::timestamp AT TIME ZONE 'Asia/Seoul')               AS to_ts,
    EXTRACT(EPOCH FROM (m_from::timestamp    AT TIME ZONE 'Asia/Seoul'))::bigint AS from_utc,
    EXTRACT(EPOCH FROM (m_to_excl::timestamp AT TIME ZONE 'Asia/Seoul'))::bigint AS to_utc
  FROM (SELECT to_date((SELECT from_month FROM params), 'YYYY-MM')                              AS m_from,
               (to_date((SELECT to_month FROM params), 'YYYY-MM') + interval '1 month')::date  AS m_to_excl) x
),
/* ── 매출액: 비회원 포함 총매출. idx_doi_regdt_store_covering (reg_dt, store_no) INCLUDE total_price ── */
total_b AS (
  SELECT doi.store_no,
         to_char(to_timestamp(doi.reg_dt) AT TIME ZONE 'Asia/Seoul', 'YYYY-MM') AS ym,
         SUM(COALESCE(doi.total_price, 0))::bigint                             AS total_sales
  FROM pos.tb_deal_order_item doi
  CROSS JOIN bounds b
  WHERE doi.order_item_status = 'OPRS_006'
    -- deleted_yn 필터 없음: dashboard_kpis.this_sales 와 같은 정의
    AND doi.reg_dt >= b.from_utc AND doi.reg_dt < b.to_utc
    AND ((SELECT store_nos FROM params) = '' OR doi.store_no = ANY (string_to_array((SELECT store_nos FROM params), ',')::bigint[]))
  GROUP BY 1, 2
),
/* 행 집합: 그 달 매출액 > 0 인 매장 */
rows_ AS (
  SELECT t.store_no, t.ym, t.total_sales,
         (to_date(t.ym, 'YYYY-MM')::timestamp AT TIME ZONE 'Asia/Seoul')                        AS m_start_ts,
         ((to_date(t.ym, 'YYYY-MM') + interval '1 month')::timestamp AT TIME ZONE 'Asia/Seoul') AS m_end_ts
  FROM total_b t
  WHERE t.total_sales > 0
    -- 테스트 매장을 빼려면 예: AND t.store_no <> ALL ('{641,644,653,693}'::bigint[])  (md "행 집합")
),
/* ── 캠페인 귀속 윈도우 = 쿠폰 유효기간 [쿠폰 생성, 마지막 user_coupon 만료) (campaign_briefing_roi 와 동일)
      MAX(expire_at) 는 idx_user_coupon_store_coupon (store_no, coupon_id, expire_at) 역방향 1건 ── */
coupon_bounds AS (
  SELECT c.campaign_id, c.store_no,
         (cp.created_at AT TIME ZONE 'Asia/Seoul') AS first_issue_kst,
         (ue.mx         AT TIME ZONE 'Asia/Seoul') AS last_expire_kst_excl
  FROM sellup.campaign c
  JOIN table_order.coupon cp ON cp.id = c.coupon_id AND cp.store_no = c.store_no
  CROSS JOIN LATERAL (
    SELECT MAX(uc.expire_at) AS mx
    FROM table_order.user_coupon uc
    WHERE uc.store_no = c.store_no AND uc.coupon_id = cp.id
  ) ue
  WHERE ue.mx IS NOT NULL   -- user_coupon 이 없는 캠페인은 원 정의(INNER JOIN)처럼 뺀다
    AND ((SELECT store_nos FROM params) = '' OR c.store_no = ANY (string_to_array((SELECT store_nos FROM params), ',')::bigint[]))
),
/* 윈도우 ∩ 조회 기간 */
campaign_window AS (
  SELECT cb.campaign_id, cb.store_no,
         GREATEST(cb.first_issue_kst, b.from_kst)      AS win_start_kst,
         LEAST(cb.last_expire_kst_excl, b.to_kst_excl) AS win_end_kst_excl
  FROM coupon_bounds cb CROSS JOIN bounds b
  WHERE GREATEST(cb.first_issue_kst, b.from_kst) < LEAST(cb.last_expire_kst_excl, b.to_kst_excl)
),
/* 처리군 (holdout = false), 캠페인 윈도우를 함께 싣는다. ix_cu_campaign_holdout (campaign_id, holdout) */
treated_users AS (
  SELECT DISTINCT cu.campaign_id, cw.store_no, cu.user_id, cw.win_start_kst, cw.win_end_kst_excl
  FROM sellup.campaign_user cu
  JOIN campaign_window cw ON cw.campaign_id = cu.campaign_id
  WHERE cu.holdout = false
),
/* 처리군 회원 (매장, 회원) 하나에 그 회원이 속한 캠페인 윈도우 배열.
   원 정의(매장 전체 회원 주문 → 처리군·윈도우와 조인)와 결과가 같고, 처리군 회원만 user_points 를 찾는다.
   뒤에서 처리군 행과 다시 조인하지 않으려고 윈도우를 배열로 들고 간다(추정 행 수가 틀려도 조인 폭발 없음). */
treated_store_users AS (
  SELECT store_no, user_id,
         array_agg(win_start_kst)    AS win_starts,
         array_agg(win_end_kst_excl) AS win_ends
  FROM treated_users
  GROUP BY store_no, user_id
),
/* 처리군 회원의 결제 deal (user_points ACCUMULATE 로 order→user). user_points 는 idx_user_points_fifo (user_id, store_no, …),
   tb_deal_order 는 PK (store_no, order_id), tb_deal 은 deal_id 인덱스, doi 는 (store_no, order_id) */
member_order_deals AS (
  SELECT dl.store_no, dl.deal_id, up.user_id,
         (to_timestamp(dl.reg_dt) AT TIME ZONE 'Asia/Seoul') AS order_time_kst,
         tsu.win_starts, tsu.win_ends,
         SUM(COALESCE(doi.total_price, 0))::bigint            AS order_total
  FROM treated_store_users tsu
  JOIN table_order.user_points up
    ON up.user_id = tsu.user_id AND up.store_no = tsu.store_no AND up.change_type = 'ACCUMULATE'
  JOIN pos.tb_deal_order tdo ON tdo.store_no = up.store_no AND tdo.order_id = up.order_id
  JOIN pos.tb_deal dl        ON dl.store_no = tdo.store_no AND dl.deal_id = tdo.deal_id
  JOIN pos.tb_deal_order_item doi
    ON doi.store_no = tdo.store_no AND doi.order_id = tdo.order_id AND doi.order_item_status = 'OPRS_006'
  CROSS JOIN bounds b
  WHERE dl.deal_status = 'OPRS_006'
    AND dl.reg_dt >= b.from_utc AND dl.reg_dt < b.to_utc
  GROUP BY dl.store_no, dl.deal_id, up.user_id, dl.reg_dt, tsu.win_starts, tsu.win_ends
),
/* 캠페인 귀속 매출 gross: 주문이 들어가는 캠페인 윈도우 수만큼 더한다
   (캠페인 간 중복 허용: 수수료 분자와 같은 정의), 주문 시각 KST 월 */
campaign_sales_b AS (
  SELECT mo.store_no, to_char(mo.order_time_kst, 'YYYY-MM') AS ym,
         SUM(mo.order_total * w.n_win)::bigint AS campaign_sales_gross
  FROM member_order_deals mo
  CROSS JOIN LATERAL (
    SELECT count(*) AS n_win
    FROM unnest(mo.win_starts, mo.win_ends) AS x(win_start_kst, win_end_kst_excl)
    WHERE mo.order_time_kst >= x.win_start_kst AND mo.order_time_kst < x.win_end_kst_excl
  ) w
  WHERE w.n_win > 0
  GROUP BY 1, 2
),
/* ── 비캠페인 CRM (crm_sales_none_campaign 와 동일): POINT 전부 + 캠페인 쿠폰이 아닌 COUPON, deal_discount.created_at 월 ── */
nc_discounts AS (
  SELECT dd.store_no, dd.deal_id, dd.order_id,
         (dd.created_at AT TIME ZONE 'Asia/Seoul')::date AS d_kst
  FROM table_order.deal_discount dd
  CROSS JOIN bounds b
  WHERE dd.discount_type IN ('COUPON', 'POINT')
    AND dd.discount_amount > 0
    AND dd.created_at >= b.from_ts AND dd.created_at < b.to_ts
    AND ((SELECT store_nos FROM params) = '' OR dd.store_no = ANY (string_to_array((SELECT store_nos FROM params), ',')::bigint[]))
    AND (
      dd.discount_type = 'POINT'
      OR NOT EXISTS (
        SELECT 1 FROM table_order.user_coupon uc
        JOIN sellup.campaign cp ON cp.coupon_id = uc.coupon_id AND cp.store_no = dd.store_no
        WHERE uc.id = dd.discount_ref_id
      )
    )
),
/* (날짜, deal, order) 중복 제거 */
nc_pairs AS (SELECT DISTINCT store_no, d_kst, deal_id, order_id FROM nc_discounts),
/* 할인 붙은 deal(order_id=0 이면 deal 전체)의 결제 품목 합 */
nc_sales AS (
  SELECT np.store_no, np.d_kst, np.deal_id, np.order_id,
         COALESCE(SUM(doi.total_price), 0)::bigint AS amt
  FROM nc_pairs np
  JOIN pos.tb_deal dl
    ON dl.store_no = np.store_no AND dl.deal_id = np.deal_id AND dl.deal_status = 'OPRS_006'
  JOIN pos.tb_deal_order_item doi
    ON doi.store_no = np.store_no AND doi.deal_id = np.deal_id
   AND doi.order_item_status = 'OPRS_006' AND doi.deleted_yn = false
   AND (np.order_id = 0 OR doi.order_id = np.order_id)
  GROUP BY np.store_no, np.d_kst, np.deal_id, np.order_id
),
nc_b AS (
  SELECT store_no, to_char(d_kst, 'YYYY-MM') AS ym, SUM(amt)::bigint AS noncampaign_crm_sales
  FROM nc_sales GROUP BY 1, 2
),
/* ── sms_send_log 매장별 status 값 (느슨한 인덱스 스캔). idx_sms_send_log_count (store_no, status, created_at, type)
      는 created_at 이 셋째 열이라, status 를 하나씩 고정해야 created_at 범위가 인덱스 조건이 된다 ── */
sms_status AS (
  SELECT s.store_no,
         (SELECT min(l.status) FROM table_order.sms_send_log l WHERE l.store_no = s.store_no) AS status
  FROM (SELECT DISTINCT store_no FROM rows_) s
  UNION ALL
  SELECT st.store_no,
         (SELECT min(l.status) FROM table_order.sms_send_log l
          WHERE l.store_no = st.store_no AND l.status > st.status)
  FROM sms_status st
  WHERE st.status IS NOT NULL
),
/* ── billing (작은 표: billing 1.7천·invoice 1.9천·payment_detail 2.3천·payments 1.9천 행) ──
   bill_yymm 은 'YYYY-MM' 텍스트이고 **청구월 = 사용월 + 1** 이다(2026-09 청구서 = 8월 사용분).
   같은 금액을 두 기준으로 낸다:
     basis 'claim' 청구월 기준: status='paid' 이고 bill_yymm = 년월
     basis 'pay'   출금월 기준: status='paid' 이고 성공 결제(CMS출금완료·신용카드·무통장입금) payment_date 최솟값의 'YYYY-MM' = 년월.
                   (2026-11-03 기준 성공 결제가 있는 청구서 1,629건은 모두 paid 라 paid 조건은 결과를 바꾸지 않는다).
                   실패 후 재출금이면 성공한 날의 달에 잡힌다. 결제 기록 없는 paid 청구서(37건)는 이 기준에 나오지 않는다. */
bill_pay AS (  -- 청구서별 첫 성공 출금일
  SELECT pd.bill_id, MIN(py.payment_date) AS pay_date
  FROM billing.payment_detail pd
  JOIN billing.payments py ON py.payment_id = pd.payment_id
  WHERE py.payment_status IN ('CMS출금완료', '신용카드', '무통장입금')
  GROUP BY pd.bill_id
),
bills AS (
  SELECT 'claim'::text AS basis, b.bill_id, b.store_no, b.bill_yymm AS ym, b.total_amount
  FROM billing.billing b
  WHERE b.status = 'paid'
    -- 순수 CMS 출금만 보려면 위 줄 대신:
    --   EXISTS (SELECT 1 FROM billing.payment_detail pd JOIN billing.payments py ON py.payment_id = pd.payment_id
    --           WHERE pd.bill_id = b.bill_id AND py.payment_status = 'CMS출금완료')
    AND b.bill_yymm >= (SELECT from_month FROM params) AND b.bill_yymm <= (SELECT to_month FROM params)
    AND ((SELECT store_nos FROM params) = '' OR b.store_no = ANY (string_to_array((SELECT store_nos FROM params), ',')::bigint[]))
  UNION ALL
  SELECT 'pay'::text, b.bill_id, b.store_no, to_char(bp.pay_date, 'YYYY-MM'), b.total_amount
  FROM billing.billing b
  JOIN bill_pay bp ON bp.bill_id = b.bill_id
  WHERE b.status = 'paid'   -- 두 기준 모두 paid 청구서만 집계한다(failed·issued·draft 제외). 사용자 결정 2026-11-03
    AND to_char(bp.pay_date, 'YYYY-MM') >= (SELECT from_month FROM params)
    AND to_char(bp.pay_date, 'YYYY-MM') <= (SELECT to_month FROM params)
    AND ((SELECT store_nos FROM params) = '' OR b.store_no = ANY (string_to_array((SELECT store_nos FROM params), ',')::bigint[]))
),
/* 청구서 합 (총출금총액), 기준별 */
bill_total AS (
  SELECT basis, store_no, ym, SUM(total_amount)::bigint AS paid_total FROM bills GROUP BY 1, 2, 3
),
/* 인보이스 종류별 합, 기준별. sell_type enum 6종(sellup 정액·정률, kakaotalk, tableorder, qrorder, waiting, service)을 모두 열로 낸다.
   sellup 의 정액/정률은 인보이스 calc_type → 없으면 계약 calc_type → 그래도 없으면 정액 */
inv_b AS (
  SELECT bl.basis, bl.store_no, bl.ym,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'sellup'
               AND COALESCE(i.invoice_data->>'calc_type', ct.contract_data->>'calc_type', '정액') = '정액')::bigint AS sellup_flat,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'sellup'
               AND COALESCE(i.invoice_data->>'calc_type', ct.contract_data->>'calc_type', '정액') = '정률')::bigint AS sellup_rate,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'kakaotalk')::bigint  AS alimtalk_total,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'tableorder')::bigint AS tableorder_rental,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'qrorder')::bigint    AS qrorder_total,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'waiting')::bigint    AS waiting_total,
         SUM(i.total_amount) FILTER (WHERE i.sell_type = 'service')::bigint    AS service_total
  FROM bills bl
  JOIN billing.invoice i        ON i.bill_id = bl.bill_id
  LEFT JOIN billing.contracts ct ON ct.cont_id = i.cont_id
  GROUP BY 1, 2, 3
),
/* 매출업사용여부: 현재 sellup·active 계약 보유 (월과 무관) */
sellup_use AS (
  SELECT DISTINCT store_no FROM billing.contracts
  WHERE sell_type = 'sellup' AND sell_status = 'active'
)
SELECT
  r.store_no                                                        AS "매장코드",
  s.store_nm                                                        AS "매장명",
  r.ym                                                              AS "년월",
  r.total_sales                                                     AS "매출액",
  (COALESCE(cs.campaign_sales_gross, 0) + COALESCE(nc.noncampaign_crm_sales, 0))::bigint AS "ai매출액",
  ROUND((COALESCE(cs.campaign_sales_gross, 0) + COALESCE(nc.noncampaign_crm_sales, 0)) * 100.0
        / r.total_sales, 2)                                         AS "ai매출비중",
  mem.cnt                                                           AS "회원수",
  sms.cnt                                                           AS "sms발송건수",
  ROUND(sms.cnt::numeric / NULLIF(mem.cnt, 0), 2)                   AS "회원당sms발송건수",
  CASE WHEN su.store_no IS NOT NULL THEN 'Y' ELSE 'N' END           AS "매출업사용여부",
  COALESCE(bt.paid_total, 0)                                        AS "총출금총액",
  COALESCE(iv.sellup_flat, 0)                                       AS "AI 매출업정액제",
  COALESCE(iv.sellup_rate, 0)                                       AS "AI매출업정률제",
  COALESCE(iv.alimtalk_total, 0)                                    AS "알림톡총액",
  COALESCE(iv.tableorder_rental, 0)                                 AS "테이블오더렌탈료",
  COALESCE(iv.qrorder_total, 0)                                     AS "QR주문",
  COALESCE(iv.waiting_total, 0)                                     AS "웨이팅",
  COALESCE(iv.service_total, 0)                                     AS "서비스",
  COALESCE(bp.paid_total, 0)                                        AS "출금월총출금총액",
  COALESCE(ip.sellup_flat, 0)                                       AS "출금월AI매출업정액제",
  COALESCE(ip.sellup_rate, 0)                                       AS "출금월AI매출업정률제",
  COALESCE(ip.alimtalk_total, 0)                                    AS "출금월알림톡총액",
  COALESCE(ip.tableorder_rental, 0)                                 AS "출금월테이블오더렌탈료",
  COALESCE(ip.qrorder_total, 0)                                     AS "출금월QR주문",
  COALESCE(ip.waiting_total, 0)                                     AS "출금월웨이팅",
  COALESCE(ip.service_total, 0)                                     AS "출금월서비스"
FROM rows_ r
LEFT JOIN public.tb_store s    ON s.store_no = r.store_no
LEFT JOIN campaign_sales_b cs  ON cs.store_no = r.store_no AND cs.ym = r.ym
LEFT JOIN nc_b nc              ON nc.store_no = r.store_no AND nc.ym = r.ym
/* 회원수: idx_table_order_user_stores_store_no_created (store_no, created_at) */
CROSS JOIN LATERAL (
  SELECT count(*)::bigint AS cnt FROM table_order.user_stores us
  WHERE us.store_no = r.store_no AND us.created_at < r.m_end_ts
) mem
/* sms발송건수: status 조건 없이 그 달 행 전부 = 비NULL status 값마다 센 합 + status IS NULL 행 수.
   두 갈래 모두 (store_no, status, created_at) 세 열을 인덱스 조건으로 쓴다
   (status 는 2026-11-03 기준 NOT NULL 컬럼이라 NULL 갈래는 0 이지만, 제약이 바뀌어도 누락이 없게 둔다) */
CROSS JOIN LATERAL (
  SELECT COALESCE((
           SELECT SUM(c.n)
           FROM sms_status st
           CROSS JOIN LATERAL (
             SELECT count(*) AS n FROM table_order.sms_send_log l
             WHERE l.store_no = st.store_no AND l.status = st.status
               AND l.created_at >= r.m_start_ts AND l.created_at < r.m_end_ts
           ) c
           WHERE st.store_no = r.store_no AND st.status IS NOT NULL), 0)
       + (SELECT count(*) FROM table_order.sms_send_log l
          WHERE l.store_no = r.store_no AND l.status IS NULL
            AND l.created_at >= r.m_start_ts AND l.created_at < r.m_end_ts)
         ::bigint AS cnt
  OFFSET 0   -- 펼침 방지: 펼치면 cnt 를 쓰는 두 곳(sms발송건수·회원당)에서 두 번 센다
) sms
LEFT JOIN sellup_use su  ON su.store_no = r.store_no
LEFT JOIN bill_total bt  ON bt.basis = 'claim' AND bt.store_no = r.store_no AND bt.ym = r.ym
LEFT JOIN inv_b iv       ON iv.basis = 'claim' AND iv.store_no = r.store_no AND iv.ym = r.ym
LEFT JOIN bill_total bp  ON bp.basis = 'pay'   AND bp.store_no = r.store_no AND bp.ym = r.ym
LEFT JOIN inv_b ip       ON ip.basis = 'pay'   AND ip.store_no = r.store_no AND ip.ym = r.ym
ORDER BY r.store_no, r.ym;