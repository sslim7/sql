SELECT
    TO_CHAR(
        ssl.created_at + INTERVAL '9 hours',
        'YYYY-MM'
    ) AS month,

    ssl.store_no,
    st.store_nm,

    COUNT(*) FILTER (WHERE ssl.type = '웨이팅')
        AS "웨이팅",

    COUNT(*) FILTER (WHERE ssl.type = 'COUPON')
        AS "CRM 쿠폰",

    COUNT(*) FILTER (WHERE ssl.type = 'POINT')
        AS "CRM 포인트",

    COUNT(*) FILTER (WHERE ssl.type = 'REFERRAL')
        AS "친구추천",

    COUNT(*) FILTER (WHERE ssl.type = '쿠폰')
        AS "매출업 쿠폰",

    COUNT(*) FILTER (WHERE ssl.type = '월간보고서')
        AS "매출업 월간 보고서",

    COUNT(*) FILTER (WHERE ssl.type = '주간보고서')
        AS "매출업 주간 보고서",

    COUNT(*) FILTER (
        WHERE ssl.type NOT IN (
            '웨이팅',
            'COUPON',
            'POINT',
            'REFERRAL',
            '쿠폰',
            '월간보고서',
            '주간보고서'
        )
        OR ssl.type IS NULL
    ) AS "기타",

    COUNT(*) AS total_sms_count

FROM table_order.sms_send_log ssl
JOIN public.tb_store st
  ON st.store_no = ssl.store_no

WHERE ssl.created_at >= TIMESTAMP '2025-12-31 15:00:00'

GROUP BY
    TO_CHAR(ssl.created_at + INTERVAL '9 hours', 'YYYY-MM'),
    ssl.store_no,
    st.store_nm

ORDER BY
    month,
    ssl.store_no;