
SELECT CONCAT(ur_ref.name,'(',mr_top.user_id,')')   AS 하위추천인,
       CONCAT(ur_sub.name,'(',so.user_id,')')        AS 구독자,
       ss.name                                        AS 구독상품,
       '신규'                                         AS 구분,
       DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) AS 일자,
       ss.price                                       AS 구독금액,
       so.speed_cash                                  AS `지급(반환)스피드캐시`,
       TRUNCATE(so.speed_cash * 0.1, 0)               AS 국장수당
FROM my_referrer mr_top
JOIN my_referrer mr_sub ON mr_top.user_id = mr_sub.referrer_user_id
JOIN subs_orders so ON so.user_id = mr_sub.user_id
JOIN subs_order_payment op ON op.subs_orders_id = so.subs_orders_id
JOIN subs ss ON so.subs_id = ss.subs_id
JOIN user ur_ref ON mr_top.user_id = ur_ref.user_id
JOIN user ur_sub ON so.user_id = ur_sub.user_id
WHERE mr_top.referrer_user_id = :user_id
  AND op.is_success = 1
  AND LEFT(op.created_at, 10) = so.subs_start_date
  AND DATE_FORMAT(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), '%Y-%m') = :ym

UNION ALL

-- 구독 취소
SELECT CONCAT(ur_ref.name,'(',mr_top.user_id,')')   AS 하위추천인,
       CONCAT(ur_sub.name,'(',so.user_id,')')        AS 구독자,
       ss.name                                        AS 구독상품,
       '취소'                                         AS 구분,
       DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) AS 일자,
       ss.price                                       AS 구독금액,
       TRUNCATE(so.speed_cash
           - so.speed_cash * (SELECT COUNT(1)
                                FROM subs_order_payment sop
                               WHERE sop.subs_orders_id = sc.subs_orders_id) / 12
       , 0)                                           AS `지급(반환)스피드캐시`,
       TRUNCATE(TRUNCATE(so.speed_cash
           - so.speed_cash * (SELECT COUNT(1)
                                FROM subs_order_payment sop
                               WHERE sop.subs_orders_id = sc.subs_orders_id) / 12
       , 0) * 0.1, 0)                                AS 국장수당
FROM my_referrer mr_top
JOIN my_referrer mr_sub ON mr_top.user_id = mr_sub.referrer_user_id
JOIN subs_order_cancel sc
JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id AND so.speed_cash <> 0
                   AND so.user_id = mr_sub.user_id
JOIN subs ss ON so.subs_id = ss.subs_id
JOIN user ur_ref ON mr_top.user_id = ur_ref.user_id
JOIN user ur_sub ON so.user_id = ur_sub.user_id
WHERE mr_top.referrer_user_id = :user_id
  AND sc.status = 2
  AND DATE_FORMAT(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), '%Y-%m') = :ym
ORDER BY 하위추천인, 일자, 구분;