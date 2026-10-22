WITH target AS (
    -- 한국 날짜 기준 1년 전 오늘의 00:00:00
    SELECT (now() AT TIME ZONE 'Asia/Seoul')::date
           - interval '1 year' AS start_kst
)
SELECT
    u.*,
    to_char(
        u.marketing_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Seoul',
        'YYYY-MM-DD'
    ) AS marketing_date_kst
FROM table_order.users u
CROSS JOIN target t
WHERE u.deleted_at IS NULL
  AND u.marketing_consent IS NOT NULL
  AND marketing_consent = true
  AND u.marketing_at >= (
      t.start_kst AT TIME ZONE 'Asia/Seoul' AT TIME ZONE 'UTC'
  )
  AND u.marketing_at < (
      (t.start_kst + interval '1 day')
      AT TIME ZONE 'Asia/Seoul' AT TIME ZONE 'UTC'
  );