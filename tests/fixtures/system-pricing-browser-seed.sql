-- Local isolated browser fixture; never run on a live project.
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003970','مدير حد الربح',true,'admin_staff','07700003970','{}'),
('00000000-0000-0000-0000-000000003971','بائع حد الربح',false,'admin_staff','07700003971','{"system":true,"installations":true,"stockMovement":true,"salesHistory":true,"customerStatement":true}'),
('00000000-0000-0000-0000-000000003972','مخزن حد الربح',false,'warehouse','07700003972','{}'),
('00000000-0000-0000-0000-000000003973','مهندس حد الربح',false,'installer','07700003973','{}');
insert into products(id,code,name,qty,cost)values(-397001,'MIN-01','مادة حد الربح',100,1000000),(-397002,'MIN-02','مادة ثانية للربح',100,500000);
insert into customers(id,name,customer_type,owner_id)values(-397001,'زبون حد الربح','system','00000000-0000-0000-0000-000000003971');
insert into solar_push_subscriptions(endpoint,user_id,p256dh,auth_key)values('https://fcm.googleapis.com/fcm/send/local-system-pricing-browser','00000000-0000-0000-0000-000000003971','local-key','local-auth');
commit;
