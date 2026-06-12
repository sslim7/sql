
select * from user where name like '%김형숙%';
-- 김성임 bd511024-6c5f-4ff7-b1eb-ed38b4a72c7a
select * from withdrawn_users where name like '%김%';
select * from user where user_id='a14ae27e-9ed4-476d-aca4-45a897da2f2f';
-- 윤기표 8096f844-aafc-47ea-ab45-1903aa33b238 --> 추천인 신봉호로 3652beb3-8ca9-4726-b103-3bb15d882fae
select * from my_referrer where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- d9b88f5b-fce3-43fd-ab0c-840aa88c1886 박월달
select * from subs_order_billing where card_number='7265';
select * from subs_orders where
                              user_id = '7f03a81f-f236-4fef-8037-297bfa8ec40e';

#                               subs_orders_id in (
#     '3dd3523d-f12e-4c1f-b4b5-170c7814748d'
#     )
    ;
select * from subs_order_payment where subs_orders_id='3dd3523d-f12e-4c1f-b4b5-170c7814748d' order by created_at;
c713e3c5-172f-447b-bb14-f9af5a6fa3fc
47d30eef-2dd0-45aa-8164-e02f2ff1cf34

select * from orders where subs_order_id ='3dd3523d-f12e-4c1f-b4b5-170c7814748d';
select * from order_items where order_id='84a5b279-7c29-46a6-b642-1f703449852c';
