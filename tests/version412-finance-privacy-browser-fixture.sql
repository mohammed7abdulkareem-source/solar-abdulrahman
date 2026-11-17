\set ON_ERROR_STOP on
begin;
-- Isolated browser fixture; subsequent browser checks are read-only.
do $$begin if current_database()<>'solar_seller_scope_browser' then raise exception 'Use the isolated privacy browser database';end if;
if exists(select 1 from profiles where id::text like '00000000-0000-0000-0000-0000004129%') then raise exception 'Fixture already exists; do not reseed';end if;end$$;
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000412900','Projection administrator',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000412901','Projection owner',false,'admin_staff','{"cash":true,"profit":true,"profitSettlement":true,"supplierStatement":true,"warehouse":true,"stockMovement":true,"sale":true}'),
('00000000-0000-0000-0000-000000412902','SECRET foreign creator',false,'admin_staff','{"cash":true,"profit":true}'),
('00000000-0000-0000-0000-000000412903','Warehouse role',false,'warehouse','{"cash":true,"profit":true}'),
('00000000-0000-0000-0000-000000412904','Installer role',false,'installer','{"cash":true,"profit":true}');
insert into public.transactions(id,kind,party_name,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,notes,receipt_no) values
(-412901,'sale','SECRET foreign customer',201,201,51,true,true,'cash','00000000-0000-0000-0000-000000412902','00000000-0000-0000-0000-000000412901','SECRET sale note',771234001),
(-412902,'system','SECRET live job',1000,1000,310,true,false,'credit','00000000-0000-0000-0000-000000412902','00000000-0000-0000-0000-000000412902','SECRET installation note',771234002),
(-412903,'sale','Own visible customer',307,307,57,true,true,'cash','00000000-0000-0000-0000-000000412901','00000000-0000-0000-0000-000000412901','Own sale note',771234003),
(-412904,'cash_income','Own admin deposit',500,500,0,true,true,'cash','00000000-0000-0000-0000-000000412900','00000000-0000-0000-0000-000000412901','Own admin deposit note',771234004),
(-412905,'purchase','SECRET supplier',211,211,0,true,false,'credit','00000000-0000-0000-0000-000000412902','00000000-0000-0000-0000-000000412902','SECRET purchase note',771234005);
insert into public.transaction_items(id,transaction_id,product_name,qty,price,cost) values
(-412901,-412901,'SECRET material',1,201,150),(-412903,-412903,'Own visible material',1,307,250),(-412905,-412905,'SECRET purchase material',1,211,211);
insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by) values
(-412908,'{"id":-412908,"kind":"system","created_by":"00000000-0000-0000-0000-000000412902","party_name":"SECRET deleted job","notes":"SECRET deleted notes","receipt_no":771234008,"warehouse_name":"SECRET warehouse"}','[]','00000000-0000-0000-0000-000000412900'),
(-412909,'{"id":-412909,"kind":"purchase","created_by":"00000000-0000-0000-0000-000000412902","party_name":"SECRET archived supplier","notes":"SECRET archived notes","receipt_no":771234009,"purchaseCancellation":{"walletEntry":{"id":-412991},"walletReversalId":-412992,"supplierEntry":{"id":-412993},"supplierReversalId":-412994}}','[]','00000000-0000-0000-0000-000000412900');
insert into solar_private.cash_transfers(id,sender_id,recipient_id,amount,status) values
('00000000-0000-0000-0000-000000412920','00000000-0000-0000-0000-000000412900','00000000-0000-0000-0000-000000412901',47,'accepted'),
('00000000-0000-0000-0000-000000412921','00000000-0000-0000-0000-000000412900','00000000-0000-0000-0000-000000412901',10,'accepted');
insert into public.solar_cash_entries(id,owner_id,actor_id,delta,entry_type,notes,job_id,deleted_job_id,transfer_id) values
('00000000-0000-0000-0000-000000412911','00000000-0000-0000-0000-000000412901','00000000-0000-0000-0000-000000412902',-47,'installation_payout','SECRET live expense',-412902,null,'00000000-0000-0000-0000-000000412920'),
('00000000-0000-0000-0000-000000412912','00000000-0000-0000-0000-000000412901','00000000-0000-0000-0000-000000412902',-31,'installation_payout','SECRET deleted expense',null,-412908,null),
('00000000-0000-0000-0000-000000412913','00000000-0000-0000-0000-000000412901','00000000-0000-0000-0000-000000412900',10,'transfer_in','Authorized transfer note',null,null,'00000000-0000-0000-0000-000000412921');
insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,entry_type,note) overriding system value values
(-412991,'00000000-0000-0000-0000-000000412901','USD',-50,-75000,1500,'purchase','SECRET archived original'),
(-412992,'00000000-0000-0000-0000-000000412901','USD',50,75000,1500,'purchase_reversal','SECRET archived reversal');
insert into public.suppliers(id,name,account_currency) values(-412901,'Shared supplier','IQD');
insert into solar_private.supplier_fx_entries(id,supplier_id,owner_id,transaction_id,currency,revision,delta,book_delta,rate,note,correction_for) overriding system value values
(-412995,-412901,'00000000-0000-0000-0000-000000412901',-412905,'IQD',0,211,211,1,'SECRET supplier row',null),
(-412993,-412901,'00000000-0000-0000-0000-000000412901',null,'IQD',0,100,100,1,'SECRET archive entry',null),
(-412994,-412901,'00000000-0000-0000-0000-000000412901',null,'IQD',0,-100,-100,1,'SECRET archive reversal',-412909);
insert into solar_private.profit_settlements(id,owner_id,snapshot,profit,status,date_to,share,receipt) values
('00000000-0000-0000-0000-000000412940','00000000-0000-0000-0000-000000412901','[]',6,'approved',(now() at time zone 'Asia/Baghdad')::date,0,'{}');
insert into solar_private.profit_checkpoints(owner_id,source_key,value,row_data,settlement_id) values
('00000000-0000-0000-0000-000000412901','tx:-412908',6,jsonb_build_object('key','tx:-412908','kind','system','date',now(),'label','SECRET deleted profit','receiptNo',771234008,'value',6),'00000000-0000-0000-0000-000000412940');
update public.profiles set phone='07700412911' where id='00000000-0000-0000-0000-000000412901';
commit;
