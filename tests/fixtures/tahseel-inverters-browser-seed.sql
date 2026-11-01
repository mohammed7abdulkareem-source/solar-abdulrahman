-- Isolated local browser fixture only. Never execute in a live project.
begin;
insert into profiles(id,display_name,user_type,is_admin,permissions,phone)values
('00000000-0000-0000-0000-000000003911','المهندس علي','admin_staff',false,'{"system":true,"tahseel":true,"tahseelFull":true}','07700003911'),
('00000000-0000-0000-0000-000000003912','الإداري عمر','admin_staff',false,'{"system":true,"tahseel":true,"tahseelFull":false}','07700003912'),
('00000000-0000-0000-0000-000000003913','عرض خاص لمستخدم آخر','admin_staff',false,'{"system":true,"tahseel":true,"tahseelFull":true}','07700003913'),
('00000000-0000-0000-0000-000000003914','المخزن','warehouse',true,'{"tahseel":true,"tahseelFull":true}','07700003914'),
('00000000-0000-0000-0000-000000003915','مهندس التنصيب','installer',true,'{"tahseel":true,"tahseelFull":true}','07700003915');
insert into brands(id,name)values(391001,'FULLMAX');
insert into products(id,code,name,category,brand_id,qty,cost)values
(391001,'QTY-INV','8KW/IP21','انفيرتر',391001,100,500000),
(391002,'QTY-PNL','600W','الواح',391001,1000,100000),
(391003,'QTY-BAT','15KW','بطارية',391001,100,2000000),
(391004,'QTY-BAT25','25KW','بطارية',391001,100,3000000);
insert into solar_quotes(id,user_id,payload)values
('00000000-0000-0000-0000-000000391001','00000000-0000-0000-0000-000000003911','{"schema":3,"customer":"عرض قديم كامل","phone":"07700003900","day":"15","night":"15","batteryCapacity":"15","panel":{"id":391002,"name":"600W","brand":"FULLMAX","cost":"100000"},"battery":{"id":391003,"name":"15KW","brand":"FULLMAX","cost":"2000000"},"inverter":{"id":391001,"name":"8KW/IP21","brand":"FULLMAX","cost":"500000"},"markupPercent":"5","perPanel":"30000","expenses":{"crane":"25000","worker":"20000","programmer":"35000","delivery":"25000","electrical":"150000"},"notes":"مسودة سابقة لا تتغير"}'),
('00000000-0000-0000-0000-000000391002','00000000-0000-0000-0000-000000003912','{"schema":3,"customer":"عرض قديم محدود","day":"15","night":"15","batteryCapacity":"15","panel":{"id":391002},"battery":{"id":391003},"inverter":{"id":391001},"notes":"عرض سابق محدود"}'),
('00000000-0000-0000-0000-000000391003','00000000-0000-0000-0000-000000003913','{"schema":3,"customer":"PRIVATE_OTHER_QUOTE"}');
commit;
