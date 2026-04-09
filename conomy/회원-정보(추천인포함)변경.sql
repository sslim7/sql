
select * from user where name like '%임상석%';
select * from user where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- 윤기표 8096f844-aafc-47ea-ab45-1903aa33b238 --> 추천인 신봉호로 3652beb3-8ca9-4726-b103-3bb15d882fae
select * from my_referrer where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- d9b88f5b-fce3-43fd-ab0c-840aa88c1886 박월달

select * from user;

-- auto-generated definition
create table withdrawn_users
(
    user_id      varchar(36)  collate utf8mb4_bin           not null comment 'user_id'
        primary key,
    name         varchar(100) collate utf8mb4_general_ci   not null comment '이름',
    phone_no     varchar(45)                               not null comment '전화번호',
    status       tinyint                                   not null comment '1.정상.  2.해지  9.일시정지',
    created_at   timestamp(6) default CURRENT_TIMESTAMP(6) not null,
    constraint user_hist_id_UNIQUE
        unique (user_id)
)
    comment '회원탈퇴 이력';

create table user_status_changes
(
    user_status_change_id varchar(36) collate utf8mb4_bin         not null comment 'Unique ID'
        primary key,
    user_id      varchar(36)        collate utf8mb4_bin           not null comment 'user_id',
    reason       varchar(200)                                         null comment '변경사유',
    before_status       tinyint                                   not null comment '1.정상.  2.해지  9.일시정지',
    after_status        tinyint                                   not null comment '1.정상.  2.해지  9.일시정지',
    created_at   timestamp(6) default CURRENT_TIMESTAMP(6) not null,
    constraint user_hist_id_UNIQUE
        unique (user_status_change_id)
)
    comment '회원상태변경 이력';

해지
- 로그인불가
- 1년동안 가입재한
일시정지
- 로그인불가

select * from user where status=9;

insert into user_status_changes (user_status_change_id,user_id,reason,before_status,after_status)
select uuid(),user_id,'탈퇴 요청으로 일시정지',1,9 from user where status=9;

update user_status_changes usc , user ur  set usc.created_at=ur.updated_at where usc.user_id=ur.user_id;


select * from user_status_changes;
01065173332 문미경

select * from user where name='탈퇴회원';

select * from withdrawn_users where phone_no=01011112222 and created >= now() interval 6 month