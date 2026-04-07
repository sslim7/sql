-- auto-generated definition
drop table seller_info;
create table seller_info
(
    user_id        varchar(36) collate utf8mb4_bin    not null
        primary key,
    birth_date     varchar(6)                         not null comment '생년월일 (YYMMDD)',
    rrn_back       varbinary(255)                     not null comment '주민등록번호 뒷자리 7자리 (암호화)',
    bank_code      varchar(45)                        not null comment '은행코드',
    account_number varbinary(255)                     not null comment '계좌번호 (암호화)',
    account_holder varchar(100)                       not null comment '예금주명',
    created_at     datetime default CURRENT_TIMESTAMP not null,
    updated_at     datetime default CURRENT_TIMESTAMP not null on update CURRENT_TIMESTAMP,
    constraint fk_seller_info_user
        foreign key (user_id) references user (user_id)
            on update cascade on delete cascade
)
    comment '판매자 기본정보';

drop table seller_info_history;
CREATE TABLE seller_info_history (
    id BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id        varchar(36) collate utf8mb4_bin  NOT NULL,
    birth_date     VARCHAR(6)       NOT NULL COMMENT '생년월일 (YYMMDD)',
    rrn_back       VARBINARY(255)   NOT NULL COMMENT '주민등록번호 뒷자리 7자리 (암호화)',
    bank_code      VARCHAR(45)      NOT NULL COMMENT '은행코드',
    account_number VARBINARY(255)   NOT NULL COMMENT '계좌번호 (암호화)',
    account_holder VARCHAR(100)     NOT NULL COMMENT '예금주명',
    created_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_seller_info_user_history
        FOREIGN KEY (user_id) REFERENCES user (user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
)
  COMMENT='판매자 기본정보 변경히스토리';
select * from user;
select * from bank where is_active=1 order by name;
ALTER TABLE seller_info CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
select * from seller_info;

WITH new_subs AS (
    SELECT
        YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3)                    AS year_week,
        DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
        DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
        ur2.user_id                                                                   AS referrer_user_id,
        ANY_VALUE(ur2.name)    COLLATE utf8mb4_general_ci                             AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci                            AS referrer_phone,
        SUM(so.speed_cash)                                                            AS new_speed_cash
    FROM subs_order_payment op
    JOIN subs_orders so ON op.subs_orders_id = so.subs_orders_id
    JOIN subs ss         ON so.subs_id = ss.subs_id
    JOIN user ur         ON so.user_id = ur.user_id
    JOIN my_referrer mr  ON so.user_id = mr.user_id
    JOIN user ur2        ON mr.referrer_user_id = ur2.user_id
    WHERE op.is_success = 1
      AND LEFT(op.created_at, 10) = so.subs_start_date
      AND YEARWEEK(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), 3) = :base_yearweek
    GROUP BY 1, 2, 3, 4
),
cancel_subs AS (
    SELECT
        YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3)                    AS year_week,
        DATE_FORMAT(DATE_SUB(DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY), '%y-%m-%d') AS week_start,
        DATE_FORMAT(DATE_ADD(DATE_SUB(DATE(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')), INTERVAL WEEKDAY(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul')) DAY), INTERVAL 6 DAY), '%y-%m-%d') AS week_end,
        ur2.user_id                                                                   AS referrer_user_id,
        ANY_VALUE(ur2.name)    COLLATE utf8mb4_general_ci                             AS referrer_name,
        ANY_VALUE(ur2.phone_no) COLLATE utf8mb4_general_ci                            AS referrer_phone,
        TRUNCATE(
            SUM(
                CASE
                    WHEN sc.updated_at < so.created_at + INTERVAL 1 MONTH
                    THEN so.speed_cash
                    ELSE so.speed_cash
                       - so.speed_cash
                       * (SELECT COUNT(1) FROM subs_order_payment sop
                          WHERE sc.subs_orders_id = sop.subs_orders_id AND sop.is_success = 1) / 12
                END
            ), 0
        )                                                                              AS return_speed_cash
    FROM subs_order_cancel sc
    JOIN subs_orders so ON sc.subs_orders_id = so.subs_orders_id AND so.speed_cash <> 0
    JOIN subs ss         ON so.subs_id = ss.subs_id
    JOIN user ur         ON so.user_id = ur.user_id
    JOIN my_referrer mr  ON so.user_id = mr.user_id
    JOIN user ur2        ON mr.referrer_user_id = ur2.user_id
    WHERE sc.status = 2
      AND YEARWEEK(CONVERT_TZ(sc.updated_at,'UTC','Asia/Seoul'), 3) = :base_yearweek
    GROUP BY 1, 2, 3, 4
)
SELECT
    n.year_week,
    n.week_start,
    n.week_end,
    n.referrer_user_id,
    CONCAT(
        COALESCE(
            DATE_FORMAT(
                (SELECT CONVERT_TZ(so2.created_at, 'UTC', 'Asia/Seoul')
                 FROM subs_orders so2
                 WHERE so2.user_id = n.referrer_user_id
                   AND so2.is_active = 1
                 ORDER BY so2.created_at
                 LIMIT 1),
                '%m/%d '
            ),
            ''
        ),
        n.referrer_name
    )                                                                                 AS referrer_name,
    n.referrer_phone,
    COALESCE(n.new_speed_cash, 0)                                                     AS speed_cash,
    COALESCE(c.return_speed_cash, 0)                                                  AS return_speed_cash,
    COALESCE(n.new_speed_cash, 0) - COALESCE(c.return_speed_cash, 0)                 AS final_speed_cash,
    si.birth_date,
    si.rrn_back,
    si.bank_code,
    b.name                                                                            AS bank_name,
    si.account_number,
    si.account_holder
FROM new_subs n
LEFT JOIN cancel_subs c
       ON n.year_week = c.year_week
      AND n.referrer_user_id = c.referrer_user_id
LEFT JOIN seller_info si ON si.user_id = n.referrer_user_id
LEFT JOIN bank b          ON b.bank_code = si.bank_code

UNION ALL

SELECT
    c.year_week,
    c.week_start,
    c.week_end,
    c.referrer_user_id,
    CONCAT(
        COALESCE(
            DATE_FORMAT(
                (SELECT CONVERT_TZ(so2.created_at, 'UTC', 'Asia/Seoul')
                 FROM subs_orders so2
                 WHERE so2.user_id = c.referrer_user_id
                   AND so2.is_active = 1
                 ORDER BY so2.created_at
                 LIMIT 1),
                '%m/%d '
            ),
            ''
        ),
        c.referrer_name
    )                                                                                 AS referrer_name,
    c.referrer_phone,
    0                                                                                 AS speed_cash,
    c.return_speed_cash                                                               AS return_speed_cash,
    0 - c.return_speed_cash                                                           AS final_speed_cash,
    si.birth_date,
    si.rrn_back,
    si.bank_code,
    b.name                                                                            AS bank_name,
    si.account_number,
    si.account_holder
FROM cancel_subs c
LEFT JOIN new_subs n
       ON c.year_week = n.year_week
      AND c.referrer_user_id = n.referrer_user_id
LEFT JOIN seller_info si ON si.user_id = c.referrer_user_id
LEFT JOIN bank b          ON b.bank_code = si.bank_code
WHERE n.referrer_user_id IS NULL

ORDER BY year_week DESC, referrer_name;

select * from seller_info;
select * from seller_info_history;

select * from subs_order_payment order by created_at desc;

select * from subs_orders where subs_orders_id='21244bce-c744-4339-aca3-621493c4bc75';
select * from orders where subs_order_id is null;
select * from user where user_id='5d062845-b18f-4728-9a0d-c05327958d68';

select * from subs_orders where subs_orders_id='418a985d-9526-4e66-bb9f-741ad6e28a72';

select * from user where user_id='a1c2916a-01eb-4431-89b5-09d636478701';