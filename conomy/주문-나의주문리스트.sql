select a.order_id,
                   a.subs_order_id,
                   c.order_item_id,
                   a.order_date,
                   ur.name order_user_name,
                   a.order_number,
                   c.order_status ,
                   b.delivery_date,
                   b.delivery_comment,
                   b.address,
                   b.address_detail,
                   b.receiver_name,
                   c.item_id,
                   c.order_qty,
                   a.use_points,
                   d.name,
                   b.receipt_method,
                   b.phone_number,
                   d.category,
                   a.user_id,
                     (
                                SELECT
                                    JSON_ARRAYAGG(image_data)
                                FROM (
                                    SELECT
                                        JSON_OBJECT(
                                            'item_image_id', ii.item_image_id,
                                            'image_url', ii.image_url,
                                            'thumbnail_url', ii.thumbnail_url,
                                            'order_by', ii.order_by,
                                            'created_at', ii.created_at,
                                            'updated_at', ii.updated_at
                                        ) AS image_data
                                    FROM item_images ii
                                    WHERE ii.item_id = d.item_id
                                    ORDER BY ii.order_by
                                ) AS ordered_images
                            ) AS item_images
            from orders a
                     join order_items c on a.order_id = c.order_id
                     join shipping b on c.order_item_id = b.order_item_id
                     join item d on c.item_id = d.item_id # and d.is_active =1
                     join user ur on a.user_id = ur.user_id
            where c.order_status <> 99
                and a.user_id = :user_id
            order by a.order_date desc;

select * from sms_validation order by created_at desc;
select * from user where name='테스트';
select * from user_login;
select * from user_status_changes;
select * from user where user_id='d7debee1-e091-420b-b110-0251eab6932c';
select * from user_status_log;
select * from withdrawn_users;
select * from order_items;
-- '주문상태 (0.입금확인중 1.결제완료 2.상품준비중 3.배송중 4.배송완료 5.환불요청 6.환불완료 7.교환요청 8.교환완료 9.주문취소 99.가주문)',
4.배송완료,6.환불완료,8.교환완료 9.주문취소,99
-- 구독리스트
SELECT
                b.subs_item_id,
                b.item_id,
                b.delivery_price,
                b.is_bundled_delivery,
                c.name,
                c.description,
                c.unit,
                c.seats,
                c.is_active,
                c.created_at,
                c.updated_at,
                a.max_seats,
                a.remain_seats,
                c.delivery_method,
                (
                    SELECT
                        JSON_ARRAYAGG(image_data)
                    FROM (
                        SELECT
                            JSON_OBJECT(
                                'item_image_id', ii.item_image_id,
                                'image_url', ii.image_url,
                                'thumbnail_url', ii.thumbnail_url,
                                'order_by', ii.order_by,
                                'created_at', ii.created_at,
                                'updated_at', ii.updated_at
                            ) AS image_data
                        FROM item_images ii
                        WHERE ii.item_id = b.item_id
                        ORDER BY ii.order_by ASC
                    ) AS ordered_images
                ) AS item_images
            FROM
                subs_orders a
            JOIN
                subs_items b ON a.subs_id = b.subs_id
            JOIN
                item c ON b.item_id = c.item_id
            join subs d on a.subs_id = d.subs_id
            WHERE  a.is_active = 1
            and c.is_active =1
            and a.user_id = :user_id
              ;
            and d.sub_cate_id =:category_id;

select * from user where name='박명신';
select * from subs_orders where user_id='746e432d-834d-4cec-9da6-10c2a0e621ff';
select * from subs_order_billing where subs_orders_id in (
    '4cbe56bd-7ae2-4184-8b72-992abf3d87a5',
'c98d455c-daf1-4dbc-a9dc-2477317265be'
    )
;
select convert_tz(so.created_at,'UTC','Asia/Seoul') 구독일,ss.name 구독제품,ur.name 구독자,ur2.name 추천인, sb.card_company, sb.card_number
       , od.order_id,oi.order_status
       from subs_order_billing sb
         join subs_orders so on sb.subs_orders_id=so.subs_orders_id
         join subs ss on so.subs_id=ss.subs_id
         join user ur on so.user_id=ur.user_id
         join my_referrer mr on ur.user_id=mr.user_id
         join user ur2 on mr.referrer_user_id=ur2.user_id
         join orders od on sb.subs_orders_id=od.subs_order_id
         join order_items oi on od.order_id=oi.order_id
         where sb.card_company='[비씨]' and sb.card_number='1475';

-- card_company='[비씨]' and card_number='1475;

select *,sop.payment_key,oi.order_id from subs_order_cancel soc
         join subs_orders so on soc.subs_orders_id=so.subs_orders_id
         join orders od on od.subs_order_id=so.subs_orders_id
         join subs_order_payment sop on so.subs_orders_id=sop.subs_orders_id and left(od.created_at,8)=left(sop.created_at,8) and sop.payment_key is not null
         join subs_order_billing sob on sop.subs_order_billing_id=sob.subs_order_billing_id
         join order_items oi on od.order_id=oi.order_id and oi.order_status in (1,2)
         where soc.status=1
#          and    soc.subs_order_cancel_id=:subs_order_cancel_id
         ;

select * from subs_order_cancel order by created_at desc;

select * from subs_order_payment where subs_order_payment.is_success=1 order by created_at desc;

select * from subs_order_payment where subs_orders_id='f175c7dd-cc85-4c84-92cb-63f9a6e11227';
select * from subs_orders where subs_orders_id='c5a36fb0-b819-4ae2-9abe-309c8145f4b8';


SELECT DATE_FORMAT(CONVERT_TZ(op.created_at,'UTC','Asia/Seoul'), '%y-%m-%d %H:%i') payment_time,
                   CONCAT(ur.name,'(',ur.user_id,')') user,
                   ss.name,
                   ss.price,
                   CASE WHEN (SELECT COUNT(1) FROM subs_order_payment sop
                              WHERE op.subs_orders_id=sop.subs_orders_id
                              AND sop.is_success=1
                              AND sop.created_at<=op.created_at)=1 THEN '신규'
                        ELSE CONCAT((SELECT COUNT(1) FROM subs_order_payment sop2
                                     WHERE op.subs_orders_id=sop2.subs_orders_id
                                     AND sop2.is_success=1
                                     AND sop2.created_at<=op.created_at),'차')
                   END AS chasu,
                   CONCAT(ur2.name,'(',ur2.user_id,')') referrer,
                   case when left(so.created_at,10)=left(op.created_at,10)
                        then so.subs_orders_id
                        else op.subs_order_payment_id
                    end subs_order_payment_id,
    so.created_at,op.created_at,
    so.subs_orders_id,op.subs_order_payment_id,
                  case when left(so.created_at,10)=left(op.created_at,10)
                       then concat(sb.card_company,' ',sb.card_number,' ',so.subs_orders_id)
                       else CONCAT_WS(' ', sb.card_company, sb.card_number, op.subs_order_payment_id)
                  end payment_info
              FROM subs_order_payment op
              JOIN subs_order_billing sb on op.subs_order_billing_id=sb.subs_order_billing_id
              JOIN subs_orders so ON op.subs_orders_id=so.subs_orders_id
              JOIN subs ss ON so.subs_id=ss.subs_id
              JOIN user ur ON so.user_id=ur.user_id
              JOIN my_referrer mr ON so.user_id=mr.user_id
              JOIN user ur2 ON mr.referrer_user_id=ur2.user_id
             WHERE op.is_success=1
               AND op.created_at >= CONVERT_TZ(STR_TO_DATE(CONCAT(:base_yymm, '-01'), '%Y-%m-%d'),'Asia/Seoul', 'UTC')
               AND op.created_at <  CONVERT_TZ(DATE_ADD(STR_TO_DATE(CONCAT(:base_yymm, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH),'Asia/Seoul', 'UTC')
             ORDER BY op.created_at DESC;

select *,SUBSTRING_INDEX(
    SUBSTRING_INDEX(source, "'subs_orders_id': '", -1),
    "'", 1
  ) AS subs_orders_id from jobs_log order by created_at;
update jobs_log set subs_orders_id=SUBSTRING_INDEX(
    SUBSTRING_INDEX(source, "'subs_orders_id': '", -1),
    "'", 1
  ) where created_at > '2025-12-01'
;
select * from jobs_log;
select count(1) from subs_order_payment where billing_yymm='202604' and is_success=1;
select * from subs_order_cancel order by subs_order_cancel.created_at desc;
select * from subs_orders where user_id='5f873070-012c-48ed-81fe-050fb54e575a';
select * from subs_order_billing;
select * from sub_cate;
select * from user where name='임상석';
SELECT
                a.subs_id,
                b.subs_orders_id,
                a.name,
                a.category,
                b.subs_start_date,
                a.price,
                a.plan,
                a.max_seats,
                a.is_active,
                a.created_at,
                b.billing_day,
                (select count(1)
                 from subs_order_payment sop
                 where b.subs_orders_id=sop.subs_orders_id and sop.billing_yymm=DATE_FORMAT(CONVERT_TZ(NOW(), '+00:00', '+09:00'), '%Y%m') and sop.is_success=1) as is_success
            FROM subs a
            JOIN subs_orders b ON a.subs_id = b.subs_id
            WHERE a.sub_cate_id = '3c4cace8-b6b5-11ef-97ed-42010a400003'
            AND b.user_id = #'a3fbfc93-5d18-4cbe-a0eb-1296c4f8a390'
                                '5f873070-012c-48ed-81fe-050fb54e575a'
            AND b.is_active =1
;

select * from subs_order_payment where subs_order_payment_id='9254d50a-bec5-462b-ad47-9dc79af3a010';
select * from subs_orders where subs_orders_id='cd05ca54-010b-471d-8d8c-b49dd40ff5ed';
-- DUE_202604_{'subs_orders_id': 'f088c8ca-e7e2-43fa-816e-f7b2ffdb61ea', 'user_id': 'e4a8ed35-9720-4efa-8495-73745af37382', 'subs_id': '5314c97e-bd50-11f0-b509-42010a40000b', 'billing_day': 9, 'is_end_of_month': 0, 'subs_name': '비즈니스 (세레니움)', 'net_amount': 99000, 'vat': 0, 'max_seats': 4, 'user_name': '황금희', 'billingKey': 'BIKYUT0018710m2603201624118319', 'is_active': 1, 'subs_order_billing_id': '953dedb3-c1b5-4837-b255-f2c6c8d98cd6', 'pg_type': 22, 'subs_start_date': datetime.datetime(2026, 3, 9,

alter table jobs_log
add column subs_orders_id varchar(36) collate utf8mb4_bin;

alter table subs_paused_history
    add column req_pause_comment varchar(500) comment "구독페이지내 안내문구";

ALTER TABLE sub_cate
  modify COLUMN req_pause_end_date DATE NULL
  COMMENT '구독 정지 종료일 (NULL = 정지 아님, 구독 신청 가능 상태)';

select * from sub_cate;
ALTER TABLE subs
  DROP COLUMN req_pause_end_date;
create table subs_paused_history
(
subs_paused_id   varchar(36) collate utf8mb4_bin           not null comment 'unique_id'
        primary key,
sub_cate_id     varchar(36) collate utf8mb4_bin           not null comment 'sub_cate_id',
admin_id   varchar(36) collate utf8mb4_bin           not null comment 'admin_id',
action_type tinyint      default 1                    not null comment '처리유형(1.정지해제 2.일시정지)',
req_pause_end_date date comment "구독신청정지종료일(null 신청가능)",
created_at  timestamp(6) default CURRENT_TIMESTAMP(6) not null,
updated_at  timestamp(6)                              null on update CURRENT_TIMESTAMP(6),
    constraint subs_paused_history_UNIQUE
        unique (subs_paused_id)
)
    comment '구독정지이력';


SELECT
                    sc.sub_cate_id,
                    sc.category,
                    sc.name,
                    sc.subs_desc,
                    sc.order_by,
                    sc.created_at,
                    sc.updated_at,
                    ss.req_pause_end_date
                FROM sub_cate sc
 JOIN subs ss on sc.sub_cate_id=ss.sub_cate_id
WHERE sc.category = 1010 ORDER BY order_by ASC
;

table sub_cate
(
    sub_cate_id        varchar(36) collate utf8mb4_bin           not null
        primary key,
    category           char(4)                                   null comment '1010.설악천연수 1020.웰니스 1030.뷰티 2010.벨리몰 3010.몰 4010.무샵',
    name               varchar(100)                              null comment '서브 카테고리명',
    subs_desc          text                                      null comment '구독설명',
    order_by           tinyint      default 1                    not null comment '노출순서',
    created_at         timestamp(6) default CURRENT_TIMESTAMP(6) not null,
    updated_at         timestamp(6)                              null,
    req_pause_end_date date                                      null comment '구독 정지 종료일 (NULL = 정지 아님, 구독 신청 가능 상태)',
    req_pause_comment  varchar(500)                              null comment '구독페이지내 안내문구'
);

select * from sub_cate where category <> 9999 order by category,order_by ;
select * from subs_paused_history;

select * from admin;
select * from jobs_log;

select * from subs_order_payment where subs_orders_id='d35f5723-171c-42b5-8dc5-79c3e97c1ef4';

INSERT INTO conomy.subs_order_payment (subs_order_payment_id, subs_orders_id, subs_order_billing_id, billing_yymm, is_success, failure_reason, created_at, updated_at, pg_type, payment_key)
VALUES ('204142d9-9318-497d-81b4-4c23941c96bf', 'd35f5723-171c-42b5-8dc5-79c3e97c1ef4', '588acb08-466b-4e0c-be5f-efbd620c1d63', '202604', 1, null, '2026-04-19 20:50:51.063525', null, 22, 'UT0018710m01162604192050502219');
select * from orders where subs_order_id='d35f5723-171c-42b5-8dc5-79c3e97c1ef4';

INSERT INTO conomy.orders (order_id, subs_order_id, order_number, user_id, order_date, order_status, created_at, updated_at, order_amount, vat, delivery_price, use_points)
VALUES (uuid(), 'd35f5723-171c-42b5-8dc5-79c3e97c1ef4', '3dc9bdce-240c-43ab-a7dc-5a0c4394e1e9', 'f9af65d0-c504-4cde-a587-3229c48ff541', '2026-04-19 20:50:51', 1, '2026-04-19 20:50:51.983362', null, 0, 0, 0, 0);
select * from order_items where order_id='b846c3b2-3be9-11f1-9134-42010a40000c';
INSERT INTO conomy.order_items (order_item_id, order_id, item_id, order_qty, created_at, order_status, order_amount, vat, delivery_price)
VALUES (uuid(), 'b846c3b2-3be9-11f1-9134-42010a40000c', '1463a92a-bd4f-11f0-b509-42010a40000b', 4, '2026-04-19 20:50:51', 1, 0, 0, 0);

INSERT INTO conomy.shipping (shipping_id, order_id, receiver_name, phone_number, zipcode, address_detail, delivery_comment, delivery_date, created_at, address, invoice_no, level, comcode, estimate, man, telno_man, telno_office, receipt_method, logistics_center_id, order_item_id)
VALUES (uuid(), 'b846c3b2-3be9-11f1-9134-42010a40000c', '윤광수 ', '01090058101', '06781', 'B2', '문 앞에 놓아주세요', null, '2026-04-19 20:50:51.059744', '서울 서초구 언남16길 13 (양재동, 청구빌리지)', null, null, null, null, null, null, null, 1, null, 'c4771c6d-3be9-11f1-9134-42010a40000c');

select * from shipping order by created_at desc;
# order_id 8159d292-878c-451b-bcc0-93053d25299c
select * from order_items where order_id='8159d292-878c-451b-bcc0-93053d25299c';
select * from order_payment where order_id='8159d292-878c-451b-bcc0-93053d25299c';
select * from shipping where order_id='8159d292-878c-451b-bcc0-93053d25299c';
select * from subs_order_payment where payment_key='UT0018710m01162604192050502219';

select * from subs_order_billing where card_number='5823';

select * from subs_orders so
join subs_order_billing sob on so.subs_orders_id=sob.subs_orders_id
join subs_order_payment sop on so.subs_orders_id=sop.subs_orders_id
where so.subs_orders_id='d35f5723-171c-42b5-8dc5-79c3e97c1ef4';
      #'d35f5723-171c-42b5-8dc5-79c3e97c1ef4';

select * from user where user_id='f9af65d0-c504-4cde-a587-3229c48ff541';

select * from user where user_id='d9fd6fd9-2b3a-47ed-a82a-43e4bd539cbd';

select * from subs_order_billing where card_number='70280';
select * from subs_orders where subs_orders_id='de9d3146-79bc-423c-ad8a-d30b3f5648e4';