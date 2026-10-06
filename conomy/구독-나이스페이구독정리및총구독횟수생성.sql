

alter table subs add column subs_limits tinyint not null default 0 comment '구독제한횟수';
alter table subs_orders add column subs_limits tinyint not null default 0 comment '구독제한횟수';

CREATE TABLE subs_orders_bulk_close_20261005 AS
SELECT so.subs_orders_id, so.user_id, so.subs_id, so.is_active AS so_is_active,
       sb.subs_order_billing_id, sb.is_active AS sob_is_active, NOW() AS closed_at
  FROM subs_orders so
  JOIN subs_order_billing sb ON so.subs_orders_id = sb.subs_orders_id
 WHERE so.is_active = 1;

CREATE TABLE subs_order_billing_cleanup_20261005 AS
SELECT sb.subs_order_billing_id, sb.subs_orders_id, sb.is_active, NOW() AS backed_at
  FROM subs_order_billing sb
  LEFT JOIN subs_orders so ON so.subs_orders_id = sb.subs_orders_id
 WHERE sb.is_active = 1 AND (so.subs_orders_id IS NULL OR so.is_active <> 1);

UPDATE subs_orders so
  JOIN subs_orders_bulk_close_20261005 b ON b.subs_orders_id = so.subs_orders_id
   SET so.is_active = 3
 WHERE so.is_active = 1;

UPDATE subs_order_billing sb
  JOIN subs_orders_bulk_close_20261005 b ON b.subs_order_billing_id = sb.subs_order_billing_id
   SET sb.is_active = 3
 WHERE sb.is_active IN (1, 2);

UPDATE subs_order_billing sb
  JOIN subs_order_billing_cleanup_20261005 c ON c.subs_order_billing_id = sb.subs_order_billing_id
   SET sb.is_active = 2
 WHERE sb.is_active = 1;

SELECT (SELECT COUNT(*) FROM subs_orders WHERE is_active=1) so_active,
       (SELECT COUNT(*) FROM subs_order_billing WHERE is_active=1) sob_active;


