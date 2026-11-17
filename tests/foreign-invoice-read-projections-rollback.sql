\set ON_ERROR_STOP on
begin;
-- Synthetic fixtures only. Everything, including writes used to check settlement tokens, is rolled back.
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000412100','Projection administrator',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000412101','Projection owner',false,'admin_staff','{"cash":true,"profit":true,"profitSettlement":true,"supplierStatement":true,"warehouse":true,"stockMovement":true,"sale":true}'),
('00000000-0000-0000-0000-000000412102','SECRET foreign creator',false,'admin_staff','{"cash":true,"profit":true}'),
('00000000-0000-0000-0000-000000412103','Warehouse role',false,'warehouse','{"cash":true,"profit":true}'),
('00000000-0000-0000-0000-000000412104','Installer role',false,'installer','{"cash":true,"profit":true}');
insert into public.transactions(id,kind,party_name,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,notes,receipt_no) values
(-412001,'sale','SECRET foreign customer',201,201,51,true,true,'cash','00000000-0000-0000-0000-000000412102','00000000-0000-0000-0000-000000412101','SECRET sale note',771234001),
(-412002,'system','SECRET live job',1000,1000,310,true,false,'credit','00000000-0000-0000-0000-000000412102','00000000-0000-0000-0000-000000412102','SECRET installation note',771234002),
(-412003,'sale','Own visible customer',307,307,57,true,true,'cash','00000000-0000-0000-0000-000000412101','00000000-0000-0000-0000-000000412101','Own sale note',771234003),
(-412004,'cash_income','Own admin deposit',500,500,0,true,true,'cash','00000000-0000-0000-0000-000000412100','00000000-0000-0000-0000-000000412101','Own admin deposit note',771234004),
(-412005,'purchase','SECRET supplier',211,211,0,true,false,'credit','00000000-0000-0000-0000-000000412102','00000000-0000-0000-0000-000000412102','SECRET purchase note',771234005);
insert into public.transaction_items(id,transaction_id,product_name,qty,price,cost) values
(-412001,-412001,'SECRET material',1,201,150),(-412003,-412003,'Own visible material',1,307,250),(-412005,-412005,'SECRET purchase material',1,211,211);
insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by) values
(-412008,'{"id":-412008,"kind":"system","created_by":"00000000-0000-0000-0000-000000412102","party_name":"SECRET deleted job","notes":"SECRET deleted notes","receipt_no":771234008,"warehouse_name":"SECRET warehouse"}','[]','00000000-0000-0000-0000-000000412100'),
(-412009,'{"id":-412009,"kind":"purchase","created_by":"00000000-0000-0000-0000-000000412102","party_name":"SECRET archived supplier","notes":"SECRET archived notes","receipt_no":771234009,"purchaseCancellation":{"walletEntry":{"id":-412091},"walletReversalId":-412092,"supplierEntry":{"id":-412093},"supplierReversalId":-412094}}','[]','00000000-0000-0000-0000-000000412100');
insert into solar_private.cash_transfers(id,sender_id,recipient_id,amount,status) values
('00000000-0000-0000-0000-000000412120','00000000-0000-0000-0000-000000412100','00000000-0000-0000-0000-000000412101',47,'accepted'),
('00000000-0000-0000-0000-000000412121','00000000-0000-0000-0000-000000412100','00000000-0000-0000-0000-000000412101',10,'accepted');
insert into public.solar_cash_entries(id,owner_id,actor_id,delta,entry_type,notes,job_id,deleted_job_id,transfer_id) values
('00000000-0000-0000-0000-000000412111','00000000-0000-0000-0000-000000412101','00000000-0000-0000-0000-000000412102',-47,'installation_payout','SECRET live expense',-412002,null,'00000000-0000-0000-0000-000000412120'),
('00000000-0000-0000-0000-000000412112','00000000-0000-0000-0000-000000412101','00000000-0000-0000-0000-000000412102',-31,'installation_payout','SECRET deleted expense',null,-412008,null),
('00000000-0000-0000-0000-000000412113','00000000-0000-0000-0000-000000412101','00000000-0000-0000-0000-000000412100',10,'transfer_in','Authorized transfer note',null,null,'00000000-0000-0000-0000-000000412121');
insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,entry_type,note) overriding system value values
(-412091,'00000000-0000-0000-0000-000000412101','USD',-50,-75000,1500,'purchase','SECRET archived original'),
(-412092,'00000000-0000-0000-0000-000000412101','USD',50,75000,1500,'purchase_reversal','SECRET archived reversal');
insert into public.suppliers(id,name,account_currency) values(-412001,'Shared supplier','IQD');
insert into solar_private.supplier_fx_entries(id,supplier_id,owner_id,transaction_id,currency,revision,delta,book_delta,rate,note,correction_for) overriding system value values
(-412095,-412001,'00000000-0000-0000-0000-000000412101',-412005,'IQD',0,211,211,1,'SECRET supplier row',null),
(-412093,-412001,'00000000-0000-0000-0000-000000412101',null,'IQD',0,100,100,1,'SECRET archive entry',null),
(-412094,-412001,'00000000-0000-0000-0000-000000412101',null,'IQD',0,-100,-100,1,'SECRET archive reversal',-412009);
insert into solar_private.profit_settlements(id,owner_id,snapshot,profit,status,date_to,share,receipt) values
('00000000-0000-0000-0000-000000412140','00000000-0000-0000-0000-000000412101','[]',6,'approved',(now() at time zone 'Asia/Baghdad')::date,0,'{}');
insert into solar_private.profit_checkpoints(owner_id,source_key,value,row_data,settlement_id) values
('00000000-0000-0000-0000-000000412101','tx:-412008',6,jsonb_build_object('key','tx:-412008','kind','system','date',now(),'label','SECRET deleted profit','receiptNo',771234008,'value',6),'00000000-0000-0000-0000-000000412140');
create temporary table projection_before as select jsonb_build_object(
 'transactions',(select jsonb_agg(to_jsonb(t) order by id) from public.transactions t),
 'items',(select jsonb_agg(to_jsonb(t) order by id) from public.transaction_items t),
 'cash',(select jsonb_agg(to_jsonb(t) order by id) from public.solar_cash_entries t),
 'wallet',(select jsonb_agg(to_jsonb(t) order by id) from solar_private.wallet_fx_entries t),
 'supplier',(select jsonb_agg(to_jsonb(t) order by id) from solar_private.supplier_fx_entries t),
 'archives',(select jsonb_agg(to_jsonb(t) order by invoice_id) from solar_private.deleted_sales t),
 'stocks',(select jsonb_agg(to_jsonb(t) order by warehouse_id,product_id) from solar_private.warehouse_stocks t)) value;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412101',true);
select set_config('test.foreignReceipt',(select receipt_no::text from public.transactions where id=-412001),true);
select set_config('test.rawProfitToken',md5(solar_private.profit_snapshot(auth.uid(),null,(now() at time zone 'Asia/Baghdad')::date)::text),true);
set local role authenticated;
do $$declare r jsonb;d jsonb;x jsonb;v text;request uuid:='00000000-0000-0000-0000-000000412150';body jsonb;begin
 -- Raw RLS already hides foreign documents; the RPC projections must agree.
 assert not exists(select 1 from public.transactions where id=-412001),'raw foreign invoice exposed';
 r:=public.solar_cash_workspace();
 assert (r#>>'{summary,IQD}')::numeric=940 and(r#>>'{summary,USD}')::numeric=0,r::text;
 assert (r->>'count')::int=8;
 assert r::text not like '%SECRET%' and r::text not like '%771234001%' and r::text not like '%-412001%',r::text;
 assert (select count(*) from jsonb_array_elements(r->'rows')z where z->>'receiptRestricted'='true')=5;
 assert exists(select 1 from jsonb_array_elements(r->'rows')z where z->>'party'='Own visible customer');
 assert exists(select 1 from jsonb_array_elements(r->'rows')z where z->>'note'='Own admin deposit note');
 foreach v in array array['SECRET foreign customer','SECRET sale note',current_setting('test.foreignReceipt'),'SECRET archived supplier','771234009'] loop
  assert(public.solar_cash_workspace(jsonb_build_object('query',v))->>'count')::int=0,'secret search/count oracle: '||v;
 end loop;
 foreach v in array array['tx:-412001','entry:00000000-0000-0000-0000-000000412111','entry:00000000-0000-0000-0000-000000412112','fx:-412091','fx:-412092'] loop
  d:=public.solar_cash_movement_detail(v);
  assert d->>'receiptRestricted'='true' and d->'document'='null'::jsonb and jsonb_array_length(d->'items')=0,d::text;
  assert d::text not like '%SECRET%' and(d->>'after')::numeric-(d->>'before')::numeric=(d->>'delta')::numeric,d::text;
  assert d#>>'{edit,canEdit}'='false' and d#>>'{deletion,canRequest}'='false';
 end loop;
 d:=public.solar_cash_movement_detail('tx:-412003');assert d->'items'->0->>'name'='Own visible material';
 d:=public.solar_cash_movement_detail('tx:-412004');assert d->>'note'='Own admin deposit note';
 d:=public.solar_cash_movement_detail('entry:00000000-0000-0000-0000-000000412113');assert d->>'note'='Authorized transfer note' and d#>>'{transfer,sender}'='Projection administrator' and d#>>'{transfer,recipient}'='Projection owner' and(d->>'delta')::numeric=10 and not(d ? 'receiptRestricted');
 r:=public.solar_cash_statement(null,(now()-interval '1 day')::date,(now()+interval '1 day')::date,'all');
 assert r::text not like '%SECRET%' and r::text not like '%771234001%' and r::text not like '%-412001%',r::text;
 assert(select(z->>'closing')::numeric from jsonb_array_elements(r->'ledgers')z where z->>'currency'='IQD')=940;
 assert(select(z->>'outgoing')::numeric from jsonb_array_elements(r->'ledgers')z where z->>'currency'='USD')=50;
 r:=public.solar_profit_detail('tx:-412001');
 assert r->'invoice'='null'::jsonb and r->'breakdown'='null'::jsonb and r->>'receiptRestricted'='true',r::text;
 assert(r#>>'{movement,value}')::numeric=51 and r::text not like '%SECRET%' and r::text not like '%771234001%';
 r:=public.solar_profit_detail('tx:-412008');assert r::text not like '%SECRET%' and r::text not like '%771234008%' and(r#>>'{movement,available}')::numeric=-6;
 r:=public.solar_profit_workspace('balance');assert r::text not like '%771234001%' and(r#>>'{period,available}')::numeric=102,r::text;
 r:=public.solar_profit_workspace('overview');
 assert r->>'token'=current_setting('test.rawProfitToken') and(r->>'available')::numeric=102;
 assert r::text not like '%771234001%' and r::text not like '%-412001%',r::text;
 body:=jsonb_build_object('expectedToken',r->>'token','note','Read projection token check');
 d:=public.solar_profit_workspace('request',request,body);
 assert d=public.solar_profit_workspace('request',request,body),'idempotent settlement response changed';
 assert d::text not like '%771234001%' and exists(select 1 from jsonb_array_elements(d->'snapshot')z where z->>'receiptRestricted'='true');
 r:=public.solar_profit_workspace('overview');assert r::text not like '%771234001%' and r::text not like '%-412001%',r::text;
 select value into x from jsonb_array_elements(r->'requests') where value->>'id'=request::text;
 d:=public.solar_profit_workspace('cancel','00000000-0000-0000-0000-000000412151',jsonb_build_object('id',request,'expectedToken',x->>'token'));
 assert d->>'status'='cancelled' and d::text not like '%771234001%';
 r:=public.solar_fx('state');assert r::text not like '%SECRET%' and r::text not like '%-412005%' and r::text not like '%-412009%',r::text;
 assert(select sum((z->>'delta')::numeric)from jsonb_array_elements(r->'accountEntries')z)=211;
 r:=public.solar_fx('statement',null,'{"supplierId":-412001}');
 assert(r->>'balance')::numeric=211 and r::text not like '%SECRET%' and r::text not like '%771234005%' and r::text not like '%-412005%',r::text;
 assert not exists(select 1 from jsonb_array_elements(r->'rows')z where z->'transaction'<>'null'::jsonb or jsonb_array_length(z->'items')<>0);
 begin perform public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000412102"}');raise exception 'foreign cashbox accepted';exception when insufficient_privilege then null;end;
 begin perform public.solar_profit_detail('tx:-412002');raise exception 'foreign unassigned profit accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$declare d jsonb;begin
 -- Unknown future metadata cannot bypass the restricted projection's explicit allowlists.
 d:=solar_private.cash_read_projection('{"id":"tx:-412001","delta":201,"currency":"IQD","futureSecret":"SECRET","invoiceId":-412001,"nested":{"party":"SECRET"}}');
 assert not(d ?| array['futureSecret','invoiceId','nested']);
 d:=solar_private.profit_read_projection('{"key":"tx:-412001","kind":"sale","value":51,"futureSecret":"SECRET","invoiceId":-412001,"party":"SECRET","cost":150,"total":201}');
 assert not(d ?| array['futureSecret','invoiceId','party','cost','total']);
 assert (select bool_and(k=any(array['key','kind','value','date','settled','available','deleted','ownerId','receiptNo','label','receiptRestricted']))from jsonb_object_keys(d)k);
 d:=solar_private.supplier_entry_read_projection('{"id":-412095,"transaction_id":-412005,"delta":211,"currency":"IQD","futureSecret":"SECRET","nested":{"party":"SECRET"}}');
 assert not(d ?| array['futureSecret','nested']) and(d->>'delta')::numeric=211;
end$$;
-- The private snapshot/token remains authoritative; only returned copies have been redacted.
do $$begin
 assert exists(select 1 from solar_private.profit_settlements s cross join lateral jsonb_array_elements(s.snapshot)x where s.id='00000000-0000-0000-0000-000000412150' and x->>'receiptNo'=current_setting('test.foreignReceipt'));
 assert exists(select 1 from solar_private.finance_requests f cross join lateral jsonb_array_elements(f.response->'snapshot')x where f.request_id='00000000-0000-0000-0000-000000412150' and x->>'key'='tx:-412001');
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412100',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_cash_movement_detail('tx:-412001');assert r->>'party'='SECRET foreign customer' and r->'items'->0->>'name'='SECRET material';
 r:=public.solar_profit_detail('tx:-412001','00000000-0000-0000-0000-000000412101');assert r->'breakdown'->>'party'='SECRET foreign customer' and(r#>>'{breakdown,materialsCost}')::numeric=150;
 r:=public.solar_fx('statement',null,'{"supplierId":-412001}');assert r::text like '%SECRET purchase material%';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412103',true);
do $$begin begin perform public.solar_cash_movement_detail('tx:-412001');raise exception 'warehouse cash access';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412104',true);
do $$begin begin perform public.solar_profit_detail('tx:-412001');raise exception 'installer profit access';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$declare current_data jsonb;sig text;begin
 foreach sig in array array['invoice_read_allowed(bigint)','cash_read_restricted(text)','cash_read_projection(jsonb)','profit_read_projection(jsonb)','supplier_entry_read_projection(jsonb)','fx_entry_read_projection(jsonb,text)']loop
  assert not has_function_privilege('authenticated','solar_private.'||sig,'EXECUTE') and not has_function_privilege('anon','solar_private.'||sig,'EXECUTE'),'private projection exposed';
 end loop;
 select jsonb_build_object('transactions',(select jsonb_agg(to_jsonb(t) order by id) from public.transactions t),'items',(select jsonb_agg(to_jsonb(t) order by id) from public.transaction_items t),'cash',(select jsonb_agg(to_jsonb(t) order by id) from public.solar_cash_entries t),'wallet',(select jsonb_agg(to_jsonb(t) order by id) from solar_private.wallet_fx_entries t),'supplier',(select jsonb_agg(to_jsonb(t) order by id) from solar_private.supplier_fx_entries t),'archives',(select jsonb_agg(to_jsonb(t) order by invoice_id) from solar_private.deleted_sales t),'stocks',(select jsonb_agg(to_jsonb(t) order by warehouse_id,product_id) from solar_private.warehouse_stocks t)) into current_data;
 assert current_data=(select value from projection_before),'read projection changed historical financial data';
 raise notice 'PASS foreign live/archive cash and supplier details, secret-search oracle, assigned-profit breakdown and snapshots/replays, unchanged balances/tokens, own/admin records, role/ACL isolation and byte-for-byte financial rows';
end$$;
rollback;
