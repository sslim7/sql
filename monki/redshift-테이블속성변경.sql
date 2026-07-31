
-- redshift 동기화를 위해 postgres mk DataBase의 각테이블에 아래 동기화 안되는 컬럼이나 외래키를 조정한다.
-- 1. type: user_define --> text
-- 2. cascade on delete 외래키 --> 외래키 삭제 및 on delete 제외하고 재생성
-- 3. no primary: primary key 생성
alter table pos.tb_store_biznumber add primary key (srno);

alter table public.tb_store alter column store_desc type text;
alter table public.tb_store alter column order_desc type text;
alter table public.tb_store alter column origin_desc type text;
alter table public.tb_store alter column address type text;
alter table public.tb_store alter column road_address type text;
alter table public.tb_store alter column address_detail type text;
alter table public.tb_store_pos alter column tbo_order_guide_message type text;

BEGIN;
ALTER TABLE table_order.coupon
    ALTER COLUMN coupon_type DROP DEFAULT,
    ALTER COLUMN discount_type DROP DEFAULT,
    ALTER COLUMN issue_type DROP DEFAULT,
    ALTER COLUMN condition_type DROP DEFAULT,
    ALTER COLUMN restore_policy DROP DEFAULT;
alter table table_order.users alter column type  type text;
ALTER TABLE table_order.coupon
    ALTER COLUMN coupon_type TYPE text
        USING coupon_type::text,
    ALTER COLUMN discount_type TYPE text
        USING discount_type::text,
    ALTER COLUMN issue_type TYPE text
        USING issue_type::text,
    ALTER COLUMN condition_type TYPE text
        USING condition_type::text,
    ALTER COLUMN restore_policy TYPE text
        USING restore_policy::text;
ALTER TABLE table_order.coupon
ALTER COLUMN issue_schedule_type
SET DEFAULT 'CONDITIONAL';
COMMIT;

alter table table_order.bills alter column status type text;
alter table table_order.subscriptions alter column plan type text;
alter table table_order.subscriptions alter column status type text;
alter table table_order.store_feature alter column pricing_type type text;
alter table table_order.feature alter column pricing_type type text;
ALTER TABLE table_order.bill_items DROP CONSTRAINT fk_table_order_bills_items;
ALTER TABLE table_order.tb_store_sync_config DROP CONSTRAINT tb_store_sync_config_store_no_fkey;
alter table table_order.transactions alter column transaction_type type text;
alter table table_order.transactions alter column status type text;
alter table table_order.pos_response_json_schemas alter column command_type  type text;
alter table table_order.payments alter column payment_method  type text;
alter table table_order.payments alter column status  type text;
alter table table_order.payment_methods alter column method_type  type text;
alter table table_order.auth_tokens alter column status  type text;
alter table table_order.auth_tokens alter column type  type text;
alter table table_order.auth_tokens alter column branch_type  type text;

alter table sellup.seg_lib alter column status  type text;
alter table sellup.seg_lib alter column default_engine type text;
alter table sellup.seg_lib_sql alter column engine type text;;
ALTER TABLE sellup.seg_lib_sql DROP CONSTRAINT seg_lib_sql_seg_lib_id_fkey;
alter table sellup.user_metrics_field alter column field_type type text;
ALTER TABLE sellup.user_metrics_value DROP CONSTRAINT user_metrics_value_user_metrics_id_fkey;

ALTER TABLE sellup.report_jobs DROP CONSTRAINT report_jobs_report_id_fkey;
alter table sellup.manager_store alter column role type text;
alter table sellup.manager_store  DROP CONSTRAINT manager_store_manager_id_fkey;
ALTER TABLE sellup.manager_store
    ADD CONSTRAINT manager_store_manager_id_fkey
        FOREIGN KEY (manager_id) REFERENCES sellup.manager;
alter table sellup.manager alter column role type text;
ALTER TABLE sellup.conversation_messages
    DROP CONSTRAINT conversation_messages_conversation_id_fkey;
ALTER TABLE sellup.conversation_messages
    ADD CONSTRAINT conversation_messages_conversation_id_fkey
        FOREIGN KEY (conversation_id) REFERENCES sellup.conversation_threads;
alter table sellup.conversation_threads alter column status type text;
alter table sellup.campaign_user alter column status type text;
ALTER TABLE sellup.campaign_user
    DROP CONSTRAINT campaign_user_campaign_id_fkey;
ALTER TABLE sellup.campaign_user
    ADD CONSTRAINT campaign_user_campaign_id_fkey
        FOREIGN KEY (campaign_id) REFERENCES sellup.campaign;
alter table sellup.campaign alter column status type text;
alter table sellup.campaign alter column window_from type smallint;
alter table sellup.campaign alter column window_to type smallint;
-- 1. enum 캐스팅이 들어간 default와 check 제거
ALTER TABLE sellup.briefing_setting
    ALTER COLUMN schedule_type DROP DEFAULT;
ALTER TABLE sellup.briefing_setting
    DROP CONSTRAINT chk_schedule_fields;
-- 2. 타입 변경
ALTER TABLE sellup.briefing_setting
    ALTER COLUMN schedule_type TYPE text USING schedule_type::text;
-- 3. default와 check를 text 기준으로 재생성
ALTER TABLE sellup.briefing_setting
    ALTER COLUMN schedule_type SET DEFAULT 'NONE';
ALTER TABLE sellup.briefing_setting
    ADD CONSTRAINT chk_schedule_fields
        CHECK ((schedule_type = 'NONE' AND schedule_day_of_week IS NULL AND schedule_day_of_month IS NULL) OR
               (schedule_type = 'DAILY' AND schedule_day_of_week IS NULL AND schedule_day_of_month IS NULL) OR
               (schedule_type = 'WEEKLY' AND schedule_day_of_week IS NOT NULL AND schedule_day_of_month IS NULL) OR
               (schedule_type = 'MONTHLY' AND schedule_day_of_month IS NOT NULL AND schedule_day_of_week IS NULL));
alter table sellup.briefing_setting alter column time_mode type text;
alter table sellup.briefing_setting alter column send_time type smallint;
alter table sellup.briefing_setting alter column auto_send_time type smallint;
ALTER TABLE sellup.briefing_setting DROP CONSTRAINT briefing_setting_policy_code_fkey;
ALTER TABLE sellup.briefing_setting
    ADD CONSTRAINT briefing_setting_policy_code_fkey
        FOREIGN KEY (policy_code) REFERENCES sellup.briefing_policy (policy_code);
alter table sellup.briefing_policy alter column kind type text;
alter table sellup.briefing_policy alter column default_schedule_type type text;
alter table sellup.briefing_policy alter column default_time_mode type text;
alter table sellup.briefing_policy alter column default_send_time type smallint;

alter table sellup.briefing_log alter column severity type text;
alter table sellup.autopilot_jobs alter column status type text;
alter table sellup.apilot_run_node alter column node_type type text;
alter table sellup.apilot_run_node alter column status type text;
ALTER TABLE sellup.apilot_run_node DROP CONSTRAINT apilot_run_node_run_id_fkey;
ALTER TABLE sellup.apilot_run_node
    ADD CONSTRAINT apilot_run_node_run_id_fkey
        FOREIGN KEY (run_id) REFERENCES sellup.apilot_run;
alter table sellup.apilot_run alter column status type text;
alter table sellup.apilot_run alter column stage type text;
alter table sellup.apilot_run alter column stage_status type text;
alter table sellup.apilot_node_registry alter column node_type type text;
alter table sellup.apilot_jobs alter column status type text;
ALTER TABLE sellup.apilot_flow_edge DROP CONSTRAINT apilot_flow_edge_from_node_id_fkey;
ALTER TABLE sellup.apilot_flow_edge
    ADD CONSTRAINT apilot_flow_edge_from_node_id_fkey
        FOREIGN KEY (from_node_id) REFERENCES sellup.apilot_node_registry;
ALTER TABLE sellup.apilot_flow_edge DROP CONSTRAINT apilot_flow_edge_to_node_id_fkey;
ALTER TABLE sellup.apilot_flow_edge
    ADD CONSTRAINT apilot_flow_edge_to_node_id_fkey
        FOREIGN KEY (to_node_id) REFERENCES sellup.apilot_node_registry;
alter table sellup.apilot_config_store alter column pilot_status type text;
alter table sellup.apilot_config_store alter column persona type text;

-- tb_menu type변경 및 뷰 재생성
BEGIN;
alter table public.tb_menu alter column menu_nm type text;
DROP VIEW public.v_mkd_store_menu;
ALTER TABLE public.tb_menu ALTER COLUMN menu_nm TYPE text;

CREATE VIEW public.v_mkd_store_menu AS
SELECT m.menu_no,
    m.menu_status,
    fn_get_codetext(m.menu_status, 'menu_status'::character varying) AS menu_status_desc,
    m.menu_nm,
    mp.menu_price,
    i.img_url,
    m.best_menu_yn,
        CASE
            WHEN m.menu_badge::text = 'MNBG_102'::text THEN true
            ELSE false
        END AS new_yn,
    ms.kitchen_no,
    ms.kitchen_nm,
    ms.order_min_amt,
    ms.store_no,
    ms.store_nm,
    ms.order_dt,
    ms.order_turn_no,
    ms.order_turn_nm,
    ms.departure_time,
    ms.order_start_days,
    ms.order_start_time,
    ms.order_start_dt,
    ms.order_end_days,
    ms.order_end_time,
    ms.order_end_dt,
    ms.mkd_order_enable,
    ms.turn_order_limit,
    ms.order_count,
    m.menu_badge,
    sp.product_status,
    fn_get_codetext(sp.product_status, 'product_status'::character varying) AS product_status_desc
   FROM v_mkd_store ms
     JOIN tb_menu m ON m.store_no = ms.store_no
     JOIN tb_store_product sp ON sp.product_no = m.product_no AND sp.product_status::text = 'PRDT_010'::text
     JOIN tb_menu_price mp ON mp.menu_price_no = m.menu_price_no
     JOIN tb_img i ON i.img_no = m.use_img_no AND i.use_yn = true
  WHERE m.use_yn = true AND m.mkd_disable_yn = false AND m.menu_status::text = 'MN_001'::text;

-- redshift에서 작업
-- 1. sortkey 변경 (seg_lib_sql에서 쿼리하는 테이블만 우선적으로)
ALTER TABLE table_order.user_points ALTER DISTKEY store_no;
ALTER TABLE table_order.user_points ALTER COMPOUND SORTKEY (store_no, created_at);

ALTER TABLE pos.tb_deal ALTER COMPOUND SORTKEY (store_no, reg_dt);

ALTER TABLE pos.tb_deal_order ALTER COMPOUND SORTKEY (store_no, reg_dt);
ALTER TABLE pos.tb_deal_order_item ALTER COMPOUND SORTKEY (store_no, reg_dt);

ALTER TABLE public.tb_menu ALTER COMPOUND SORTKEY (store_no, menu_no);
ALTER TABLE public.tb_menu_price ALTER COMPOUND SORTKEY (menu_no);
-- ALTER TABLE public.tb_store ALTER COMPOUND SORTKEY (store_no); -- 이미 이렇게 있음
-- ALTER TABLE public.tb_store_pos ALTER COMPOUND SORTKEY (store_no); -- 이미 이렇게 있음

-- ALTER TABLE sellup.apilot_config_store ALTER COMPOUND SORTKEY (store_no);
-- ALTER TABLE sellup.basic_info ALTER COMPOUND SORTKEY (store_no);
ALTER TABLE sellup.campaign ALTER COMPOUND SORTKEY (store_no, created_at);
ALTER TABLE sellup.campaign_user ALTER COMPOUND SORTKEY (campaign_id, user_id);
ALTER TABLE sellup.churn_pred ALTER COMPOUND SORTKEY (store_no, base_date);
-- ALTER TABLE sellup.manager ALTER COMPOUND SORTKEY (manager_id);
ALTER TABLE sellup.manager_store ALTER COMPOUND SORTKEY (manager_id,store_no);
ALTER TABLE sellup.user_metrics ALTER COMPOUND SORTKEY (store_no, snap_date);
ALTER TABLE sellup.user_metrics_value ALTER COMPOUND SORTKEY (user_metrics_id, field_name);

ALTER TABLE table_order.coupon ALTER COMPOUND SORTKEY (store_no, id);
ALTER TABLE table_order.deal_discount ALTER COMPOUND SORTKEY (store_no, order_id);
ALTER TABLE table_order.sms_send_log ALTER COMPOUND SORTKEY (store_no, created_at);
ALTER TABLE table_order.user_coupon ALTER COMPOUND SORTKEY (store_no, user_id);
ALTER TABLE table_order.user_points ALTER COMPOUND SORTKEY (store_no, created_at);
-- ALTER TABLE table_order.user_stores ALTER COMPOUND SORTKEY (store_no);
ALTER TABLE table_order.user_visit ALTER COMPOUND SORTKEY (store_no, created_at);
-- ALTER TABLE table_order.users ALTER COMPOUND SORTKEY (id);

-- 2. postgres에서 변경조치 되었으므로 다시 갱신
alter database mk integration refresh table mk.public.tb_store,mk.public.tb_store_pos;
alter database mk integration refresh table mk.public.tb_menu;

alter database mk integration refresh table mk.sellup.seg_lib;
alter database mk integration refresh table mk.table_order.users;
alter database mk integration refresh table mk.table_order.coupon;
alter database mk integration refresh table mk.table_order.bills;
alter database mk integration refresh table mk.table_order.subscriptions;
alter database mk integration refresh table mk.table_order.store_feature;
alter database mk integration refresh table mk.table_order.feature;
alter database mk integration refresh table mk.table_order.bill_items;
alter database mk integration refresh table mk.table_order.tb_store_sync_config;
alter database mk integration refresh table mk.table_order.transactions;
alter database mk integration refresh table mk.table_order.pos_response_json_schemas,mk.table_order.payment_methods,mk.table_order.auth_tokens;
alter database mk integration refresh table mk.table_order.payments;

alter database mk integration refresh table mk.sellup.user_metrics_value,mk.sellup.user_metrics_field,mk.sellup.seg_lib_sql ;
alter database mk integration refresh table mk.sellup.report_jobs;
alter database mk integration refresh table mk.sellup.manager_store;
alter database mk integration refresh table mk.sellup.manager;
alter database mk integration refresh table mk.sellup.conversation_messages;
alter database mk integration refresh table mk.sellup.conversation_threads;
alter database mk integration refresh table mk.sellup.campaign_user;
alter database mk integration refresh table mk.sellup.campaign;
alter database mk integration refresh table mk.sellup.briefing_setting;
alter database mk integration refresh table mk.sellup.briefing_policy;
alter database mk integration refresh table mk.sellup.briefing_log;
alter database mk integration refresh table mk.sellup.autopilot_jobs;
alter database mk integration refresh table mk.sellup.apilot_run;
alter database mk integration refresh table mk.sellup.apilot_run_node;
alter database mk integration refresh table mk.sellup.apilot_node_registry;
alter database mk integration refresh table mk.sellup.apilot_jobs;
alter database mk integration refresh table mk.sellup.autopilot_jobs;
alter database mk integration refresh table mk.sellup.apilot_flow_edge;
alter database mk integration refresh table mk.sellup.apilot_config_store;

alter database mk integration refresh table mk.table_order.transactions;
alter database mk integration refresh table mk.table_order.subscriptions;
alter database mk integration refresh table mk.table_order.payments;
alter database mk integration refresh table mk.table_order.payment_methods;
alter database mk integration refresh table mk.table_order.coupon;
alter database mk integration refresh table mk.table_order.bills;
alter database mk integration refresh table mk.table_order.auth_tokens;

ALTER TABLE table_order.user_points ALTER DISTKEY store_no;
ALTER TABLE table_order.user_points ALTER COMPOUND SORTKEY (store_no, created_at);
-- sortkey 변경확인
SELECT
    a.attname AS column_name,
    a.attsortkeyord AS sortkey_order,
    a.attisdistkey AS is_distkey
FROM pg_attribute a
JOIN pg_class c
  ON a.attrelid = c.oid
JOIN pg_namespace n
  ON c.relnamespace = n.oid
WHERE n.nspname = 'table_order'
  AND c.relname = 'user_points'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY
    CASE WHEN a.attsortkeyord = 0 THEN 999 ELSE ABS(a.attsortkeyord) END,
    a.attnum;