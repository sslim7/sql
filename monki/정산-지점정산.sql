
5/6
1. 이메일에서 첨부화일 다운로드
2. ops들어가서 사전체크->
3. 사전체크 -> 처리중인게 있어서 아래 사전체크 후 쿼리수행
4. CSV업로드 -> ..... 주문상태
5. 재집계 -> status=reconciled라서 재집계안됨 (업데이트대상이 없으면 상태도 안바뀐다 ㅠㅠ)
6. 재집계 -> SELECT * FROM operations.settlement_runs WHERE year_month='2026-04'; 불러서 status=order_updated 변경
7. 실행판정 -> 다음단계 -> Production쓰기 -> 다음단계 status=order_updated라서 다음단계안됨 recalculated로 변경후 다음단계
9. 통합관리(https://crew.monki.net admin_id_001 / yes1234) 정산-통합정 정산집등록(시청점)
10. 완료
11. 마지막에 있는 키오스크 주문수수료 + 먼키앱(포장제외 홀주문) 주문수수료 조회 쿼리실행하여 리스트 전달

https://ops.monthlykitchen.kr/settlements
주문상태 업데이트 대상이 없으면 status가 바뀌지 않으니 완료후 status로 수정하고 다음단계버튼을 눌러라

2단계: 화면에 파일붙이고 https://adm.smartkds.co.kr/smartcast/jsp/main.jsp mkitchenM/master1234 들어가서 시청점 합계금액을 가져와서 입력
SELECT * FROM operations.settlement_runs WHERE year_month='2026-04';

각 단계가 요구하는 status:
  ┌─────────────────┬───────────────┬────────────────────────────────┐
  │      단계        │   필요 status  │           완료 후 status         │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ 사전체크          │ draft         │ pre_check                      │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ CSV 업로드        │ pre_check     │ csv_parsed                     │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ 매핑             │ csv_parsed    │ mapped                         │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ 대사             │ mapped        │ reconciled                     │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ 실행판정          │ reconciled    │ (변경 안 함)                     │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ 주문상태변경       │ reconciled    │ order_updated                  │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ 재집계            │ order_updated │ recalculated                   │
  ├─────────────────┼───────────────┼────────────────────────────────┤
  │ Production 쓰기  │ recalculated  │ production_written → completed │
  └─────────────────┴───────────────┴────────────────────────────────┘

-- 전역 설정 체크
--  24년 2월 15일 기준
-- “먼키캐시 적립률” : 5
-- “먼키캐시 적립 분담률” : 50
-- “먼키쿠폰 사용 수수료율” : 10
SELECT public.fn_get_mk_config_float('mpoint', 'mpoint_save_mk_monki') AS "먼키캐시 적립율"
  , public.fn_get_mk_config_float('order_accounts', 'oa_ms_mpoint_store_fee') AS "먼키캐시 적립 분담율"
  , public.fn_get_mk_config_float('order_accounts', 'oa_ms_mk_coupon_fee') AS "먼키쿠폰 사용 수수료율"
;

-- 지점 수수료율 모두 있는지 체크
SELECT k.kitchen_nm AS "지점명"
  , s.store_no AS "매장번호"
  , s.store_nm AS "매장명"
  , public.fn_get_codetext(ct.ct_type, 'ct_type_code') AS "계약형태"
  , sf31.order_pay_fee AS "수수료계약 매출수수료"
  , sf11.order_pay_fee AS "일반_키오스크_주문수수료"
  , sf12.order_pay_fee AS "일반_키오스크_결제수수료"
  , sf13.order_pay_fee AS "일반_먼키_주문수수료(매장)"
  , sf14.order_pay_fee AS "일반_먼키_주문수수료(포장/배달)"
  , sf15.order_pay_fee AS "일반_먼키_결제수수료(매장/포장/배달)"
  , sf16.order_pay_fee AS "일반_먼키_무료배달_주문수수료"
  , sf17.order_pay_fee AS "일반_먼키_무료배달_결제수수료"
  , sf18.order_pay_fee AS "일반_먼키_무료배달_배달료"
  , sf21.order_pay_fee AS "B2B_키오스크_주문수수료"
  , sf22.order_pay_fee AS "B2B_키오스크_결제수수료"
  , sf23.order_pay_fee AS "B2B_먼키_주문수수료(매장)"
  , sf24.order_pay_fee AS "B2B_먼키_주문수수료(포장/배달)"
  , sf25.order_pay_fee AS "B2B_먼키_결제수수료(매장/포장/배달)"
  , sf26.order_pay_fee AS "B2B_먼키_무료배달_주문수수료"
  , sf27.order_pay_fee AS "B2B_먼키_무료배달_결제수수료"
  , sf28.order_pay_fee AS "B2B_먼키_무료배달_배달료"
  , public.fn_get_store_config_float(s.store_no, 'order_accounts', 'oa_ms_store_coupon_fee') AS "매장쿠폰 사용 수수료율"
  , public.fn_get_store_config_float(s.store_no, 'order_accounts', 'oa_ms_msg_amt') AS "알림톡 요금"
FROM public.tb_store s
JOIN public.tb_kitchen k ON k.kitchen_no = s.kitchen_no
LEFT OUTER JOIN public.tb_contract ct ON ct.store_no = s.store_no
LEFT OUTER JOIN public.tb_store_fee sf11 ON sf11.store_no = s.store_no AND sf11.account_type = 'AC_001' AND sf11.order_pay_type = 'AP_101'
LEFT OUTER JOIN public.tb_store_fee sf12 ON sf12.store_no = s.store_no AND sf12.account_type = 'AC_001' AND sf12.order_pay_type = 'AP_102'
LEFT OUTER JOIN public.tb_store_fee sf13 ON sf13.store_no = s.store_no AND sf13.account_type = 'AC_001' AND sf13.order_pay_type = 'AP_201'
LEFT OUTER JOIN public.tb_store_fee sf14 ON sf14.store_no = s.store_no AND sf14.account_type = 'AC_001' AND sf14.order_pay_type = 'AP_202'
LEFT OUTER JOIN public.tb_store_fee sf15 ON sf15.store_no = s.store_no AND sf15.account_type = 'AC_001' AND sf15.order_pay_type = 'AP_203'
LEFT OUTER JOIN public.tb_store_fee sf16 ON sf16.store_no = s.store_no AND sf16.account_type = 'AC_001' AND sf16.order_pay_type = 'AP_401'
LEFT OUTER JOIN public.tb_store_fee sf17 ON sf17.store_no = s.store_no AND sf17.account_type = 'AC_001' AND sf17.order_pay_type = 'AP_402'
LEFT OUTER JOIN public.tb_store_fee sf18 ON sf18.store_no = s.store_no AND sf18.account_type = 'AC_001' AND sf18.order_pay_type = 'AP_403'
LEFT OUTER JOIN public.tb_store_fee sf21 ON sf21.store_no = s.store_no AND sf21.account_type = 'AC_002' AND sf21.order_pay_type = 'AP_101'
LEFT OUTER JOIN public.tb_store_fee sf22 ON sf22.store_no = s.store_no AND sf22.account_type = 'AC_002' AND sf22.order_pay_type = 'AP_102'
LEFT OUTER JOIN public.tb_store_fee sf23 ON sf23.store_no = s.store_no AND sf23.account_type = 'AC_002' AND sf23.order_pay_type = 'AP_201'
LEFT OUTER JOIN public.tb_store_fee sf24 ON sf24.store_no = s.store_no AND sf24.account_type = 'AC_002' AND sf24.order_pay_type = 'AP_202'
LEFT OUTER JOIN public.tb_store_fee sf25 ON sf25.store_no = s.store_no AND sf25.account_type = 'AC_002' AND sf25.order_pay_type = 'AP_203'
LEFT OUTER JOIN public.tb_store_fee sf26 ON sf26.store_no = s.store_no AND sf26.account_type = 'AC_002' AND sf26.order_pay_type = 'AP_401'
LEFT OUTER JOIN public.tb_store_fee sf27 ON sf27.store_no = s.store_no AND sf27.account_type = 'AC_002' AND sf27.order_pay_type = 'AP_402'
LEFT OUTER JOIN public.tb_store_fee sf28 ON sf28.store_no = s.store_no AND sf28.account_type = 'AC_002' AND sf28.order_pay_type = 'AP_403'
LEFT OUTER JOIN public.tb_store_fee sf31 ON sf31.store_no = s.store_no AND sf31.account_type = 'AC_001' AND sf31.order_pay_type = 'AP_301'
WHERE s.use_yn = TRUE
AND s.store_status NOT IN ('ST_008')
AND s.store_open_status NOT IN ('STNS_104')
AND k.use_yn = TRUE
AND k.kitchen_type = 'KC_001'
AND s.store_no NOT IN (19,197,193,47,199,54,198,69,143,200,207,343) /* 테스트매장 */
AND s.store_no NOT IN (250,326,344) /* 제외매장 */
AND s.store_no NOT IN (272,298,261,301,254,268) /* 주방오락실, 먼키펍 */
AND s.kitchen_no IN (1,3,4,11,12)
ORDER BY ct.ct_type, s.kitchen_no, s.store_no
;

-- 지점 키오스크 매장매핑 체크
-- 통합관리자 > 먼키지점 > 운영 > 키오스크-매장매핑
-- “#언매핑 주문”이 있을 경우 매핑 등록
-- 아래 쿼리에서는 store_nm 이 store_full_name 포함되어 있는지 확인 (포함되어 있지 않은 경우 잘못된 매칭)
SELECT s1.store_no
  , s1.store_full_name
  , s.store_no AS store_no_s
  , s.store_nm
  , s.kitchen_no
  , k.kitchen_nm
FROM
(
  SELECT st.store_no, st.store_full_name
  FROM sales.tb_sales_total st
  WHERE st.store_no != -1
  AND st.sale_type = '03'
  AND st.order_dt2 BETWEEN date_part('epoch', concat('2024-10-01')::timestamp AT TIME ZONE 'KST')::int8 AND (date_part('epoch', concat('2024-10-31')::timestamp AT TIME ZONE 'KST' + interval'1 day')::int8 - 1)
  GROUP BY st.store_no, st.store_full_name
) s1
LEFT OUTER JOIN public.tb_store s ON s.store_no = s1.store_no
LEFT OUTER JOIN public.tb_kitchen k ON k.kitchen_no = s.kitchen_no
ORDER BY s.store_no ASC
;

-- 사전체크 후 처리중인게 있으면 아래쿼리로 업데이트
/* 먼키앱 처리중 --> 처리완료 order에서 찾기 */
SELECT count(*) AS cnt
FROM public.tb_order
WHERE use_yn = TRUE
AND reg_dt BETWEEN date_part('epoch', concat('{시작날짜}2024-10-01')::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', concat('{종료날짜}2024-10-31')::timestamp AT TIME ZONE 'KST' + interval'1 day')::int8 - 1)
AND order_status = 'OD_013'
;

SELECT count(*) AS cnt
FROM public.tb_order
WHERE use_yn = TRUE
  AND reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
                 AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
  AND order_status = 'OD_013'
;

/* 처리중 -> 처리완료 확인 order_store에서 찾기 */
SELECT count(*) AS cnt
FROM public.tb_order_store a
JOIN public.tb_order b ON a.order_no = b.order_no
AND b.use_yn = TRUE
AND b.reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND a.store_order_status = 'OD_013'
;

BEGIN TRANSACTION;
UPDATE public.tb_order
SET order_status = 'OD_014'
WHERE use_yn = TRUE
AND reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND order_status = 'OD_013'
;
UPDATE public.tb_order_store a
SET store_order_status = 'OD_014'
FROM public.tb_order b
WHERE a.order_no = b.order_no
AND b.use_yn = true
AND b.reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND a.store_order_status = 'OD_013'
;
ROLLBACK;
COMMIT;

/* 먼키앱 배달중 --> 배달완료 */
SELECT *
FROM public.tb_order
WHERE use_yn = TRUE
AND reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND order_status = 'OD_015'
;

/* 먼키앱 배달중 --> 배달완료 order_store에서 찾기 */
SELECT a.*
FROM public.tb_order_store a
JOIN public.tb_order b ON a.order_no = b.order_no
AND b.use_yn = TRUE
AND b.reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND a.store_order_status = 'OD_015'
;
BEGIN TRANSACTION;
UPDATE public.tb_order
SET order_status = 'OD_016'
WHERE use_yn = TRUE
AND reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND order_status = 'OD_015'
;
UPDATE public.tb_order_store a
SET store_order_status = 'OD_016'
FROM public.tb_order b
WHERE a.order_no = b.order_no
AND b.use_yn = TRUE
AND b.reg_dt BETWEEN date_part('epoch', '2026-04-01'::timestamp AT TIME ZONE 'KST')::int8
AND (date_part('epoch', ('2026-04-30'::timestamp + interval '1 day') AT TIME ZONE 'KST')::int8 - 1)
AND a.store_order_status = 'OD_015'
;
ROLLBACK;
COMMIT;

/* 먼키앱 무료배달 주문완료 건 배달완료가 아닌 건 */
SELECT o.order_no
  , to_char(timezone('KST', to_timestamp(o.reg_dt)), 'YYYY-MM-DD HH24:MI:SS') AS reg_dt
  , o.order_date
  , public.fn_get_codetext(o.order_type, 'order_type') AS order_type_name
  , public.fn_get_codetext(o.order_status, 'order_status') AS order_status_name
  , public.fn_get_codetext(o.alloc_status, 'alloc_status') AS alloc_status_txt
  , o.menu_price
  , o.tot_price
  , o.discount_price
  , o.delivery_price
  , o.pay_point_amt
  , o.pay_user_amt
FROM public.tb_order o
WHERE o.use_yn = TRUE
AND o.order_type = 'OD_022'
AND o.order_status NOT IN ('OD_011', 'OD_017', 'PG_001', 'PG_002')
AND o.order_date BETWEEN '2026-04-01' AND '2026-04-30'
AND (o.alloc_status IS NULL OR o.alloc_status != 'ALS_008')
ORDER BY o.order_date ASC
;
-- 무료배달 주문완료 건 배달완료가 아닌 건 배달완료 처리
BEGIN TRANSACTION;
UPDATE public.tb_order
SET alloc_status = 'ALS_008'
WHERE use_yn = TRUE
AND order_type = 'OD_022'
AND order_status NOT IN ('OD_011', 'OD_017', 'PG_001', 'PG_002')
AND order_date BETWEEN '2026-04-01' AND '2026-04-30'
AND (alloc_status IS NULL OR alloc_status != 'ALS_008')
;
ROLLBACK;
COMMIT;

--
SELECT st.*
FROM sales.tb_sales_total st
WHERE
--     st.store_no = -1
-- AND st.sale_type = '03'
-- AND
    st.order_dt2 BETWEEN date_part('epoch', concat('2026-05-01')::timestamp AT TIME ZONE 'KST')::int8 AND (date_part('epoch', concat('2026-05-30')::timestamp AT TIME ZONE 'KST' + interval'1 day')::int8 - 1)
;

-- 사전체크하다 중단되었을때 status=pre_check로 되어있을테니 failed로 수정하고 다시 사전체크부터 들어간다
SELECT *
--     id, year_month, status, created_at
  FROM operations.settlement_runs
  WHERE year_month='2026-04';
--       status NOT IN ('completed', 'failed');

-- 주문상태 업데이트 대상이 없으면 위 레코드 status=reconciled이다 아래 쿼리를 실행해서 모두 0이면 order_updated로 수정후 재집계실행
 -- Case A: OD_013 남아있는지
  SELECT COUNT(*) FROM public.tb_order
  WHERE use_yn = TRUE AND order_status = 'OD_013'
    AND reg_dt BETWEEN 1743440400 AND 1746118799;

  -- Case B: OD_015 남아있는지
  SELECT COUNT(*) FROM public.tb_order
  WHERE use_yn = TRUE AND order_status = 'OD_015'
    AND reg_dt BETWEEN 1743440400 AND 1746118799;

  -- Case C: 무료배달 미완료
  SELECT COUNT(*) FROM public.tb_order
  WHERE use_yn = TRUE AND order_type = 'OD_022'
    AND order_status NOT IN ('OD_011','OD_017','PG_001','PG_002')
    AND order_date BETWEEN '2026-04-01' AND '2026-04-30'
    AND (alloc_status IS NULL OR alloc_status != 'ALS_008');

-- 키오스크 주문수수료 + 먼키앱(포장제외 홀주문) 주문수수료 조회
select DISTINCT(acc_no)
  from sales.tb_accounts2_order
 where order_date > '2026-04-01 00:00:00'  and order_date < '2026-05-01 00:00:00'
 order by acc_no asc;

-- 위에서 조회한 acc_no로 수정
SELECT x2.store_no AS "매장번호"
  , s.store_nm AS "매장명"
  , x2.store_price_sum AS "판매정산금"
  , x2.acc_order_fee_sum AS "주문중개수수료"
FROM (
  SELECT x.store_no
    , sum(x.store_price) AS store_price_sum
    , sum(x.acc_order_fee) AS acc_order_fee_sum
  FROM (
	SELECT ao.store_no
      , m1.account_amt AS store_price
      , m2.account_amt AS acc_order_fee
	FROM sales.tb_accounts2_order ao
	JOIN public.tb_order o ON o.order_no = ao.order_no
	LEFT OUTER JOIN sales.tb_accounts2_order_item m1 ON m1.acc_no = ao.acc_no AND m1.store_no = ao.store_no AND m1.order_no = ao.order_no AND m1.acc_order_type = 'ACOT_001' AND m1.order_account_type = 'ODAT_012' /*판매정산금*/
	LEFT OUTER JOIN  sales.tb_accounts2_order_item m2 ON m2.acc_no = ao.acc_no AND m2.store_no = ao.store_no AND m2.order_no = ao.order_no AND m1.acc_order_type = 'ACOT_001' AND m2.order_account_type = 'ODAT_002' /*주문수수료*/
	WHERE ao.acc_no = ${acc_no}
	AND ao.acc_order_type = 'ACOT_001' /*먼키앱주문*/
	AND EXISTS (SELECT 1 FROM public.tb_store t WHERE t.kitchen_no = 12 AND t.store_no = ao.store_no) /*시청점*/
	AND o.order_type = 'OD_003' /*매장주문*/
	UNION ALL
	SELECT ao.store_no
      , m1.account_amt as store_price
      , m2.account_amt as acc_order_fee
	FROM sales.tb_accounts2_order ao
	LEFT OUTER JOIN sales.tb_accounts2_order_item m1 ON m1.acc_no = ao.acc_no AND m1.store_no = ao.store_no AND m1.order_id = ao.order_id AND m1.acc_order_type = 'ACOT_002' AND m1.order_account_type = 'ODAT_012' /*판매정산금*/
	LEFT OUTER JOIN sales.tb_accounts2_order_item m2 ON m2.acc_no = ao.acc_no AND m2.store_no = ao.store_no AND m2.order_id = ao.order_id AND m1.acc_order_type = 'ACOT_002' AND m2.order_account_type = 'ODAT_002' /*주문수수료*/
	WHERE ao.acc_no = ${acc_no}
	AND ao.acc_order_type = 'ACOT_002' /*키오스크주문*/
	AND EXISTS (SELECT 1 FROM public.tb_store t WHERE t.kitchen_no = 12 AND t.store_no = ao.store_no) /*시청점*/
  ) x
  GROUP BY x.store_no
) x2
JOIN public.tb_store s ON s.store_no = x2.store_no
ORDER BY x2.store_no;