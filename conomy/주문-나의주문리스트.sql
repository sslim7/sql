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