\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003530','مدير التحويل',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003531','صاحب الفواتير',false,'admin_staff','{"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003532','المستفيد',false,'admin_staff','{"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003533','مخزن',false,'warehouse','{}');
insert into suppliers(id,name,account_currency) values(-353003,'مورد ربح التحويل','IQD');
insert into transactions(id,kind,party_name,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id) values
(353001,'sale','عميل سري أ',100000,100000,20000,true,false,'credit','00000000-0000-0000-0000-000000003531','00000000-0000-0000-0000-000000003531'),
(353002,'sale','عميل سري ب',150000,150000,30000,true,false,'credit','00000000-0000-0000-0000-000000003531','00000000-0000-0000-0000-000000003531');
create temporary table transfer_before as select jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'stock',(select jsonb_agg(to_jsonb(s) order by warehouse_id,product_id) from solar_private.warehouse_stocks s),'cash',(select jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text) from cash_ledger c)) data;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003531',true);
do $$begin begin perform public.solar_profit_transfer('list');raise exception 'staff transfer permission';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003530',true);
do $$declare r jsonb;b jsonb;request uuid:=gen_random_uuid();begin
 b:='{"invoiceIds":[353001,353002],"ownerId":"00000000-0000-0000-0000-000000003532","note":"اختبار تحويل ربح فاتورتين"}';
 r:=public.solar_profit_transfer('preview',null,b);
 if(r->>'total')::numeric<>50000 or jsonb_array_length(r->'rows')<>2 then raise exception 'batch preview amount';end if;
 begin perform public.solar_profit_transfer('apply',gen_random_uuid(),b||'{"expectedToken":"stale"}');raise exception 'stale preview accepted';exception when sqlstate 'PT409' then null;end;
 b:=b||jsonb_build_object('expectedToken',r->>'token');r:=public.solar_profit_transfer('apply',request,b);
 if public.solar_profit_transfer('apply',request,b)<>r then raise exception 'transfer replay changed response';end if;
 perform set_config('test.profit_transfer_request',request::text,true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003531',true);
do $$declare r jsonb;begin
 r:=public.solar_profit_workspace('overview');if(r->>'available')::numeric<>0 or jsonb_array_length(r->'rows')<>0 then raise exception 'source retained attributed profit';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003532',true);
do $$declare r jsonb;begin
 r:=public.solar_profit_workspace('overview');if(r->>'available')::numeric<>50000 or jsonb_array_length(r->'rows')<>2 then raise exception 'recipient profit missing';end if;
 if r::text like '%عميل سري%' then raise exception 'foreign client label exposed';end if;
 r:=public.solar_profit_detail('tx:353001');if r->'invoice'<>'null'::jsonb or r->>'transferred'<>'true' or(r->'movement'->>'available')::numeric<>20000 then raise exception 'recipient source-invoice leak %',r;end if;
 r:=public.solar_profit_workspace('overview');r:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',r->>'token'));
 perform set_config('test.transfer_settlement',r->>'id',true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003530',true);
do $$declare r jsonb;begin
 r:=public.solar_profit_detail('tx:353001','00000000-0000-0000-0000-000000003532');if r->'invoice'->>'party_name'<>'عميل سري أ' then raise exception 'admin source invoice missing';end if;
 begin perform public.solar_profit_transfer('preview',null,'{"invoiceIds":[353001],"ownerId":"00000000-0000-0000-0000-000000003531"}');raise exception 'pending settlement moved';exception when raise_exception then if sqlerrm='pending settlement moved' then raise;end if;end;
end$$;
reset role;
do $$declare current_data jsonb;begin
 select jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'stock',(select jsonb_agg(to_jsonb(s) order by warehouse_id,product_id) from solar_private.warehouse_stocks s),'cash',(select jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text) from cash_ledger c)) into current_data;
 if current_data<>(select data from transfer_before) then raise exception 'profit attribution changed financial/source rows';end if;
 if(select count(*) from solar_private.invoice_profit_owner_audit where request_id=current_setting('test.profit_transfer_request')::uuid)<>2 then raise exception 'wrong audit / duplicate application';end if;
 if solar_private.retained_profit('00000000-0000-0000-0000-000000003531')<>0 or solar_private.retained_profit('00000000-0000-0000-0000-000000003532')<>50000 then raise exception 'retained profit inconsistent';end if;
 if not(solar_private.reset_snapshot() ? 'solar_private.invoice_profit_owners') or not(solar_private.reset_snapshot() ? 'solar_private.invoice_profit_owner_audit') then raise exception 'reset backup missing attribution';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003530',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003530","mode":"capital_deposit","currency":"IQD","amount":100000,"note":"تمويل تسوية الاختبار"}');
do $$declare r jsonb;begin
 r:=public.solar_profit_workspace('overview',null,'{"ownerId":"00000000-0000-0000-0000-000000003532"}')->'requests'->0;
 perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',r->>'token','share',5000,'cashOwnerId','00000000-0000-0000-0000-000000003532','collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-353003,'supplierToken',(select s->>'token' from jsonb_array_elements(public.solar_profit_workspace('overview')->'suppliers')s where(s->>'id')::bigint=-353003),'supplierRate',1));
 r:=public.solar_profit_workspace('overview',null,'{"ownerId":"00000000-0000-0000-0000-000000003532"}');
 if(r->>'available')::numeric<>0 then raise exception 'transferred profit settlement was not closed';end if;
end$$;
do $$begin begin perform public.solar_profit_transfer('preview',null,'{"invoiceIds":[353001],"ownerId":"00000000-0000-0000-0000-000000003531"}');raise exception 'settled profit moved';exception when raise_exception then if sqlerrm='settled profit moved' then raise;end if;end;end$$;
reset role;
do $$begin if has_function_privilege('anon','public.solar_profit_transfer(text,uuid,jsonb)','execute') then raise exception 'anonymous assignment';end if;raise notice 'PASS admin-only batch profit transfer, preview/CAS/idempotence, source removal/recipient credit, company profit/cash/stock/invoice unchanged, private receipt redaction, pending and settled safeguards, audit and reset backup';end$$;
rollback;
