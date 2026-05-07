# 추천인기준 나의 하위 맴버들
WITH RECURSIVE PartnerHierarchy AS (
    SELECT
        user_id,
        referrer_user_id,
        1 AS depth,
        CAST(user_id AS CHAR(1000)) AS SortPath
    FROM
        my_referrer
    WHERE
        user_id = :start_user_id

    UNION ALL

    SELECT
        mr.user_id,
        mr.referrer_user_id,
        ph.depth + 1,
        CONCAT(ph.SortPath, '-', mr.user_id) AS SortPath
    FROM
        my_referrer mr
    INNER JOIN
        PartnerHierarchy ph
        ON mr.referrer_user_id = ph.user_id
    WHERE
        ph.depth < 100 -- 최대 깊이를 제한
)
SELECT
    CONCAT(
        LPAD('', (ph.depth - 1) * 4, ' '),
        u.name
    ) AS user_hname,
    (SELECT COUNT(1)
       FROM my_referrer mr
      WHERE mr.referrer_user_id = ph.user_id) members,
    CASE
        WHEN pt.level = 11 THEN 'standard'
        WHEN pt.level = 21 THEN 'elite'
        WHEN pt.level = 31 THEN 'executive'
        ELSE ''
    END AS partner_level,
    ph.depth,
    u.name user_name,
    ph.user_id,
    ph.referrer_user_id,
    (select count(1) from subs_orders so where ph.user_id=so.user_id and so.is_active <> 1) cancel_cnt
FROM
    PartnerHierarchy ph
LEFT JOIN partner pt ON ph.user_id = pt.user_id
JOIN user u ON ph.user_id = u.user_id and u.status=1
ORDER BY
    ph.SortPath; -- DFS 경로를 기준으로 정렬