
select * from user where name like '%임상석%';
select * from user where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- 윤기표 8096f844-aafc-47ea-ab45-1903aa33b238 --> 추천인 신봉호로 3652beb3-8ca9-4726-b103-3bb15d882fae
select * from my_referrer where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- d9b88f5b-fce3-43fd-ab0c-840aa88c1886 박월달

select * from user;

-- auto-generated definition
create table user_status_change
(
    user_status_change_id varchar(36) collate utf8mb4_bin           not null comment 'Unique ID'
        primary key,
    user_id      varchar(36)  collate utf8mb4_bin           not null comment 'user_id',
    name         varchar(100) collate utf8mb4_general_ci   not null comment '이름',
    phone_no     varchar(45)                               not null comment '전화번호',
    status       tinyint                                   not null comment '1.정상.  2.해지  9.일시정지',
    created_at   timestamp(6) default CURRENT_TIMESTAMP(6) not null,
    constraint user_hist_id_UNIQUE
        unique (user_status_change_id)
)
    comment '회원변경 히스토리';
select * from subs_orders;
해지
- 로그인불가
- 1년동안 가입재한
일시정지
- 로그인불가
