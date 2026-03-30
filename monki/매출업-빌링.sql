select * from sellup.manager;
-- auto-generated definition
create table billings
(
    store_no         bigint                                                        not null
        constraint fk_billings_store_no
            primary key
            references sellup.basic_info
            on delete cascade,
    start_billing_dt        date,
    status smallint                  default 1,
    process_type          boolean                  default true not null,
    price int,
    created_at         timestamp with time zone default now(),
    updated_at    timestamp with time zone
);

comment on table basic_info is '매장 기본설정 정보';

comment on column basic_info.store_no is 'pk';

comment on column basic_info.ai_enabled is 'ai 활성유무';

alter table basic_info
    owner to mk;


create table billings
-- store_no
-- start_billing_dt
-- status (1.대기, 2.진행중, 3.중단, 4.취소) 디폴트 1
-- process_type (1.자동 2.컨펌) 디폴트 1
-- payment_method (1.CMS 2.credit_card) 디폴트 1
-- pricing_type (1.basic, 2.
-- price

select * from public.tb_store where store_nm like '%소요%';