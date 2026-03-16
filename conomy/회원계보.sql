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
                    user_id = :user_id
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
                ph.depth,
                u.name user_name,
                ph.user_id,
                ph.referrer_user_id,
                u2.name referrer_user_name,
                left(u.created_at,10) register
            FROM
                PartnerHierarchy ph
            JOIN user u ON ph.user_id = u.user_id and u.status=1
            JOIN user u2 ON ph.referrer_user_id=u2.user_id and u2.status=1
            WHERE ph.user_id<>:user_id
            ORDER BY
                ph.SortPath -- DFS 경로를 기준으로 정렬
;
