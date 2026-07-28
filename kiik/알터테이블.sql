select * from admin;
alter table admin add column email varchar(100) not null;
alter table admin add column password varchar(255) not null;
alter table admin add column is_admin boolean not null default false;
alter table admin add column must_change_password boolean not null default false;
alter table admin add column permissions json not null DEFAULT (JSON_OBJECT());
alter table admin drop column phone_no;
create unique index uix_admin_email on admin (email);
alter table admin alter column admin_id set default (uuid());

create table audit_logs
(
    audit_log_id         varchar(36) collate utf8mb4_bin                                  not null default (uuid())
        primary key,
    admin_id    varchar(36) collate utf8mb4_bin,
    actions     varchar(1000)                                   not null,
    targets     varchar(255),
    details     json,
    ip_address  varchar(45),
    created_at  timestamp(6) default CURRENT_TIMESTAMP(6) not null
);
create index idx_audit_logs_admin_id   on audit_logs (admin_id);
create index idx_audit_logs_created_at on audit_logs (created_at);
create index idx_audit_logs_admin_created on audit_logs (admin_id, created_at);
create index idx_audit_logs_target on audit_logs (targets);
