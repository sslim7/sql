select * from item where name like '%KIIK%';
select * from item_images;
select * from item where item.is_active=1 and item.category='2010' order by created_at;
INSERT INTO conomy.item (item_id, name, description, unit, seats, is_active, category,
                         sale_price, vat, delivery_price, is_bundled_delivery, delivery_method, retail_price, vendor_id, eco_point,created_at)
VALUES (uuid(), 'KIIK의 시작, 3일 지우개 (6개월분) - 사용할수록 피부는 더 건강하게', '
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_01.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_02.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_03.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_04.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_05.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_06.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_07.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_08.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_09.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_10.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_11.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_12.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_13.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_14.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_15.png" width="640" height="818"" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_16.png" width="640" height="818"" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_17.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_18.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_19.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_20.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_21.png" width="640" height="818" style="width: 100%; height: auto">
<img src="https://static-file.conomy.io/item_desc_image/kiik_desc_22.png" width="640" height="818" style="width: 100%; height: auto">
', '세트', 1, 0, '2010', 594000, 54000, 0, 0, 1, 1452000, '3126b3af-c2c0-11f0-b509-42010a40000b', 0,'2023-02-16 07:37:12.831000');

INSERT INTO conomy.item_images (item_image_id, item_id, image_url, thumbnail_url, order_by)
VALUES (uuid(), 'bc5499b8-a9d7-11f1-856d-42010a40000e', '/item_origin_image/kiik_01.png', '/item_thumbnail_image/kiik_01.png', 1);
INSERT INTO conomy.item_images (item_image_id, item_id, image_url, thumbnail_url, order_by)
VALUES (uuid(), 'bc5499b8-a9d7-11f1-856d-42010a40000e', '/item_origin_image/kiik_02.png', '/item_thumbnail_image/kiik_02.png', 2);
INSERT INTO conomy.item_images (item_image_id, item_id, image_url, thumbnail_url, order_by)
VALUES (uuid(), 'bc5499b8-a9d7-11f1-856d-42010a40000e', '/item_origin_image/kiik_03.png', '/item_thumbnail_image/kiik_03.png', 3);
select * from item_images where item_id='92984844-a9d5-11f1-856d-42010a40000e';