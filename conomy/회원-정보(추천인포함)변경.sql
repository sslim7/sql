
select * from user where name like '%김소연%';
select * from user where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- 윤기표 8096f844-aafc-47ea-ab45-1903aa33b238 --> 추천인 신봉호로 3652beb3-8ca9-4726-b103-3bb15d882fae
select * from my_referrer where user_id='9e9b4623-6017-4f26-909f-ab8805e08616';
-- d9b88f5b-fce3-43fd-ab0c-840aa88c1886 박월달
select * from subs_orders where user_id='d3eb8ae3-2e87-4f0a-bcc7-7279a07fca97';
select * from subs_order_cancel where subs_orders_id='de9d3146-79bc-423c-ad8a-d30b3f5648e4';

select * from subs_order_billing
         where card_number=9447 and card_company='[NH채움]';
#              subs_orders_id='37c14ea0-1bdd-4fba-b78b-30cdfbcb8fbd'
;
-- 9447,"","",[NH채움]  591015
