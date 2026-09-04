
CREATE DATABASE analytics;

CREATE MATERIALIZED VIEW public.sellup_campaign_member_mv
DISTSTYLE KEY
DISTKEY(campaign_id)
SORTKEY(store_no, campaign_id, user_id)
AUTO REFRESH YES
AS
SELECT
    c.store_no,
    c.campaign_id,
    c.coupon_id,
    c.exec_date,
    cu.campaign_user_id,
    cu.user_id,
    COALESCE(cu.holdout, FALSE) AS holdout
FROM mk.sellup.campaign c
JOIN mk.sellup.campaign_user cu
  ON cu.campaign_id = c.campaign_id;

CREATE MATERIALIZED VIEW public.sellup_campaign_bounds_mv
DISTSTYLE KEY
DISTKEY(campaign_id)
SORTKEY(store_no, campaign_id)
AUTO REFRESH YES
AS
SELECT
    c.store_no,
    c.campaign_id,
    c.campaign_name,
    c.category,
    c.coupon_id,
    c.exec_date,

    cp.created_at AS coupon_from_utc,

    MAX(uc.expire_at) AS coupon_to_utc

FROM mk.sellup.campaign c

JOIN mk.table_order.coupon cp
  ON cp.id = c.coupon_id
 AND cp.store_no = c.store_no

JOIN mk.table_order.user_coupon uc
  ON uc.coupon_id = c.coupon_id
 AND uc.store_no = c.store_no
 AND uc.deleted_at IS NULL

WHERE c.coupon_id IS NOT NULL

GROUP BY
    c.store_no,
    c.campaign_id,
    c.campaign_name,
    c.category,
    c.coupon_id,
    c.exec_date,
    cp.created_at;

SELECT
    schema,
    name,
    is_stale,
    autorefresh,
    state
FROM stv_mv_info
WHERE name = 'sellup_campaign_member_mv';

SELECT
    "schema",
    "table",
    diststyle,
    sortkey1,
    sortkey_num,
    tbl_rows,
    size,
    unsorted,
    stats_off
FROM svv_table_info
WHERE "table" = 'sellup_campaign_member_mv';
SELECT
    "schema",
    "table",
    diststyle,
    sortkey1,
    sortkey_num,
    tbl_rows,
    size,
    unsorted,
    stats_off
FROM svv_table_info
WHERE "schema" = 'sellup'
  AND "table" = 'campaign_user';

CREATE MATERIALIZED VIEW public.pos_order_sales_mv
DISTSTYLE KEY
DISTKEY(store_no)
SORTKEY(store_no, reg_dt, deal_id, order_id)
AUTO REFRESH YES
AS
SELECT
    oi.store_no,
    oi.deal_id,
    oi.order_id,
    MIN(oi.reg_dt) AS reg_dt,
    SUM(oi.total_price) AS sales
FROM mk.pos.tb_deal_order_item oi
JOIN mk.pos.tb_deal d
  ON d.store_no = oi.store_no
 AND d.deal_id = oi.deal_id
WHERE
    oi.order_item_status = 'OPRS_006'
    AND COALESCE(oi.deleted_yn, FALSE) = FALSE
    AND d.deal_status = 'OPRS_006'
    AND COALESCE(d.deleted_yn, FALSE) = FALSE
GROUP BY
    oi.store_no,
    oi.deal_id,
    oi.order_id;