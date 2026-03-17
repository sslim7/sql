select * from reward where description like '공유보너스%' order by created_at desc;

select ur.user_id,ur.name,sum(vp.join_point)
  from valie_points vp join user ur on vp.user_id=ur.user_id and ur.status=1
 where vp.created_at > '2024-03-01' and vp.created_at < '2026-03-01'
 group by 1,2 having sum(vp.join_point) > 0
order by 2;

INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'd214be46-13dc-4883-9c94-f25524f2fa51', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'e9a2b91e-f91d-47c9-8279-e9d226170bf4', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'd5b16965-2f9e-4d16-9ced-b649c50a7854', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '5135e71f-baf2-4005-9dee-101d331dce6e', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'a761a422-5503-4666-a6e5-763d636546c2', 14, '공유보너스 (26년 2월분)', 21083);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'c6bd904b-83be-4bd9-a051-925036b86feb', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '3d910def-83ef-45f7-be77-90ce36743299', 14, '공유보너스 (26년 2월분)', 32436);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'f1d482e5-bb2c-4e25-91a0-cc226eec187c', 14, '공유보너스 (26년 2월분)', 32436);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '8c5f419e-a32f-477a-8034-e2fe1b409a91', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '093ba426-7c5a-479b-ac9b-bd7233e42c5d', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '46c4b439-103d-47da-85d7-cc2e74fd649d', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '62357ae8-20af-43af-83cf-45edad5f13c5', 14, '공유보너스 (26년 2월분)', 227052);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '3c254411-df69-48eb-8bb5-77fa8c984fb1', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '85c8e2d5-949c-4a48-a868-d184effafb8a', 14, '공유보너스 (26년 2월분)', 24327);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '1e0a03ac-48fd-47c6-a537-67101a22eeb5', 14, '공유보너스 (26년 2월분)', 21083);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'b312c889-eb18-4eb6-8863-35ffcd36c8e2', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '0c48b812-1069-4f55-a2b1-4cdfc4f93de1', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '01c68b02-7f3a-4646-9a76-7af23da763b5', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '4702a383-2bc8-4798-9331-ae123c7bac84', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '18656a54-2876-4b9a-806f-cc4561aa01e4', 14, '공유보너스 (26년 2월분)', 97308);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '6b1f6bac-3f19-4ad3-855d-b14446f5436a', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '210d8ce5-e24a-4a73-b75b-db667ef111e1', 14, '공유보너스 (26년 2월분)', 97308);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '2c4cdec6-e14c-4f84-9397-029a40ba823e', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'b634b830-00c5-4f3c-8329-326364594fac', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '95566d87-52c9-4c88-9841-6201be1e9290', 14, '공유보너스 (26년 2월분)', 72981);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '8f0b5849-f803-4a93-b738-4d0dee3f72f9', 14, '공유보너스 (26년 2월분)', 194616);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '0c7af3fb-7563-4b2f-882c-699f9d712f61', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '5d6b3506-3e44-471c-9c2a-0e04abeafc21', 14, '공유보너스 (26년 2월분)', 32436);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '757e222b-ee5b-4902-b798-744dcf1117a0', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '2fcf392f-86a6-4197-b684-89e409d29a25', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'c7f9f664-c482-409e-8617-3de16ad61339', 14, '공유보너스 (26년 2월분)', 48654);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'f999b6f1-b8e3-4647-80f8-d4b40f688533', 14, '공유보너스 (26년 2월분)', 32436);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '104d2d25-4f76-4e9c-be3d-0df32ddf44eb', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'b407f621-02ed-4112-a511-9bdc681abccb', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '6eb39ac2-8203-488a-868b-7422602c08f0', 14, '공유보너스 (26년 2월분)', 251379);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '4559ab60-fcd7-40dd-94ad-68f5fe072d5d', 14, '공유보너스 (26년 2월분)', 89199);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '8c1b2cc8-af52-4e13-a402-e0023f58df23', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'd9ef7481-e3fe-4560-b8ac-4d7d13cd8b26', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '0e1d9a89-f89a-4971-a5f1-e92069d9e974', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '39af32d3-ff8c-4124-bdf9-cf4695d2a6b1', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '25cadc33-32b7-4ae5-9a17-ab272bf3e596', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'fa117f00-d1e1-4acf-b6fa-5cc98746a39b', 14, '공유보너스 (26년 2월분)', 105417);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '677b9d39-052c-4088-a2b4-167ecdba6c7d', 14, '공유보너스 (26년 2월분)', 32436);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'b32a322c-6496-44c4-87ef-5168471b0e82', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '67a26694-8bbc-43a5-9f09-d9ff0a36bc52', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '85d61291-f435-41fd-8746-f9b4afa0b907', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), '7627a00c-4e2b-4c1e-817c-1b804e2a0442', 14, '공유보너스 (26년 2월분)', 32436);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'bb029dbc-98e6-4a6b-ab0f-ce45493bb535', 14, '공유보너스 (26년 2월분)', 16218);
INSERT INTO conomy.reward (reward_id, user_id, trans_type, description, point) VALUES (uuid(), 'df3d5fe6-033a-4de1-9d15-6e600432b29c', 14, '공유보너스 (26년 2월분)', 32436);