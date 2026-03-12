expire를 insert 하지않고 일시기준으로 만료,잔액 구할수있겠다
-- 유저별,매장별 특정일시(UTC) 기준 포인트 잔액 구하기
-- user_id,store_no null 이면 해당필드 group by
-- as_of_utc null 이면 now()
WITH params AS (
  SELECT
    COALESCE(:as_of_ts_utc::timestamptz, now()) AS as_of_utc,
    :user_id::uuid  AS user_id,
    :store_no::bigint AS store_no
),
tx AS (
  SELECT
    up.user_id,
    up.store_no,
    CASE
      WHEN up.change_type IN ('USE', 'DEDUCT', 'ACCUMULATE_CANCEL') THEN -ABS(up.point)
      WHEN up.change_type IN ('ACCUMULATE', 'GRANT', 'USE_CANCEL')  THEN  ABS(up.point)
      WHEN up.change_type IN ('PENDING')                            THEN  0
      ELSE 0
    END AS signed_point
  FROM table_order.user_points up
  CROSS JOIN params p
  WHERE up.created_at <= p.as_of_utc
    AND (p.user_id  IS NULL OR up.user_id  = p.user_id)
    AND (p.store_no IS NULL OR up.store_no = p.store_no)
)
SELECT
  user_id,
  store_no,
  GREATEST(0, SUM(signed_point)) AS balance_asof
FROM tx
GROUP BY user_id, store_no
HAVING GREATEST(0, SUM(signed_point)) > 0
ORDER BY store_no, balance_asof DESC;

-- 유저별,매장별 특정일시(UTC) 기준 만료되는 포인트 구하기
-- user_id,store_no null 이면 해당필드 group by
-- as_of_utc null 이면 now()
WITH params AS (
  SELECT
    COALESCE(:as_of_ts_utc::timestamptz, now()) AS as_of_utc,
    :user_id::uuid       AS user_id,
    :store_no::bigint    AS store_no
),

tx AS (
  SELECT
    up.user_id,
    up.store_no,
    up.id,
    up.created_at,
    up.expired_at,
    CASE
      WHEN up.change_type IN ('USE', 'DEDUCT', 'ACCUMULATE_CANCEL') THEN -ABS(up.point)
      WHEN up.change_type IN ('ACCUMULATE', 'GRANT', 'USE_CANCEL')  THEN  ABS(up.point)
      WHEN up.change_type IN ('PENDING')                            THEN  0
      ELSE 0
    END AS signed_point
  FROM table_order.user_points up
  CROSS JOIN params p
  WHERE up.created_at <= p.as_of_utc
    AND (p.user_id  IS NULL OR up.user_id  = p.user_id)
    AND (p.store_no IS NULL OR up.store_no = p.store_no)
),

outflow AS (
  SELECT
    user_id,
    store_no,
    SUM(-signed_point) AS total_out
  FROM tx
  WHERE signed_point < 0
  GROUP BY user_id, store_no
),

inflow AS (
  SELECT
    user_id,
    store_no,
    id,
    created_at,
    expired_at,
    signed_point AS in_point,
    SUM(signed_point) OVER (
      PARTITION BY user_id, store_no
      ORDER BY created_at, id
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cum_in
  FROM tx
  WHERE signed_point > 0
),

bucket_remaining AS (
  SELECT
    i.user_id,
    i.store_no,
    i.expired_at,
    (i.in_point - GREATEST(
      0,
      LEAST(
        i.in_point,
        COALESCE(o.total_out, 0) - (i.cum_in - i.in_point)
      )
    )) AS remaining_in_bucket
  FROM inflow i
  LEFT JOIN outflow o
    ON o.user_id = i.user_id AND o.store_no = i.store_no
)

SELECT
  br.user_id,
  br.store_no,
  SUM(br.remaining_in_bucket) AS expired_amount_asof
FROM bucket_remaining br
CROSS JOIN params p
WHERE br.expired_at IS NOT NULL
  AND br.expired_at < p.as_of_utc
GROUP BY br.user_id, br.store_no
HAVING SUM(br.remaining_in_bucket) > 0
ORDER BY br.store_no, expired_amount_asof DESC;

select * from public.tb_store where store_nm like '%샤브몽%';

select ur.phone 전화번호,case when marketing_consent=false then '미동의' end as 마케팅동의 from table_order.user_stores us join table_order.users ur on us.user_id=ur.id where us.store_no=646;

select * from sellup.manager;