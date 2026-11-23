-- All fixtures roll back; both reporting roles see the same stock/cash movements.
\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,display_name,is_admin,user_type,active,permissions) values
 ('00000000-0000-0000-0000-000000413461','أدمن تجريبي',true,'admin',true,'{}'),
 ('00000000-0000-0000-0000-000000413462','موظف تقارير تجريبي',false,'admin_staff',true,
  '{"purchase":true,"stockMovement":true,"supplierBalances":true,"suppliers":true,"supplierPayment":true,"supplierStatement":true,"capital":true}');
insert into public.suppliers(id,name) values
 (-413461,'ABDULRAHMAN'),(-413462,'ABDULRAHMAN REPORTS');
insert into public.products(id,code,name) values(-413461,'REPORTS413461','مادة تقارير');
-- Recreate pre-FX imports, including one stale supplier ID and an opening
-- subsequently posted to the FX ledger. The DDL itself rolls back with the fixtures.
alter table public.transactions disable trigger solar_fx_post;
insert into public.transactions(id,kind,party_id,party_name,total,cash,created_by,cashbox_user_id,warehouse_id,notes,payment_mode) values
 (-413461,'purchase',-413461,'ABDULRAHMAN',100,true,'00000000-0000-0000-0000-000000413462','00000000-0000-0000-0000-000000413462',1,'secret4134cash',null),
 (-413462,'purchase',-413462,'ABDULRAHMAN REPORTS',44,false,'00000000-0000-0000-0000-000000413462','00000000-0000-0000-0000-000000413462',1,'visible4134purchase',null),
 (-413463,'supplier_payment',-413461,'ABDULRAHMAN',-91,false,'00000000-0000-0000-0000-000000413462','00000000-0000-0000-0000-000000413462',null,'secret4134opening','charge_old_balance'),
 (-413464,'supplier_payment',-413462,'ABDULRAHMAN REPORTS',-31,false,'00000000-0000-0000-0000-000000413462','00000000-0000-0000-0000-000000413462',null,'visible4134opening','charge_old_balance'),
 (-413465,'purchase',-913461,'ABDULRAHMAN',73,false,'00000000-0000-0000-0000-000000413462','00000000-0000-0000-0000-000000413462',1,'secret4134orphan',null);
set constraints all immediate;
alter table public.transactions enable trigger solar_fx_post;
set constraints all deferred;
insert into public.transaction_items(id,transaction_id,product_id,product_name,qty,price) values
 (-413461,-413461,-413461,'مادة تقارير',5,20),(-413462,-413462,-413461,'مادة تقارير',4,11);
insert into solar_private.supplier_fx_entries(supplier_id,owner_id,transaction_id,currency,revision,delta,book_delta,rate,note) values
 (-413461,'00000000-0000-0000-0000-000000413462',-413463,'IQD',0,91,91,1,'secret4134fx'),
 (-413462,'00000000-0000-0000-0000-000000413462',-413464,'IQD',0,31,31,1,'visible4134fx');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413461',true);
do $$
declare r jsonb;
begin
 r:=public.solar_quick_search('ABDULRAHMAN','suppliers');
 assert exists(select 1 from jsonb_array_elements(r->'suppliers') s where s->>'id'='-413461' and (s->>'balance')::numeric=91);
 r:=public.solar_party_balances('suppliers',(now() at time zone 'Asia/Baghdad')::date);
 assert exists(select 1 from jsonb_array_elements(r->'rows') s where s->>'id'='-413461');
 assert exists(select 1 from jsonb_array_elements(r->'unresolved_rows') s where s->>'id'='-413465');
 r:=public.solar_capital_snapshot();
 assert r::text like '%secret4134cash%' and r::text like '%secret4134opening%';
 r:=public.solar_inventory('material_report',null,'{"productId":-413461,"withPrices":true}');
 assert exists(select 1 from jsonb_array_elements(r->'rows') s where s->>'invoiceId'='-413461' and s->>'party'='ABDULRAHMAN');
end $$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413462',true);
do $$
declare r jsonb;
begin
 r:=public.solar_quick_search('ABDULRAHMAN','suppliers');
 assert not exists(select 1 from jsonb_array_elements(r->'suppliers') s where s->>'id'='-413461');
 assert exists(select 1 from jsonb_array_elements(r->'suppliers') s where s->>'id'='-413462' and (s->>'balance')::numeric=31);
 r:=public.solar_party_balances('suppliers',(now() at time zone 'Asia/Baghdad')::date);
 assert not exists(select 1 from jsonb_array_elements(r->'rows') s where s->>'id'='-413461');
 assert exists(select 1 from jsonb_array_elements(r->'rows') s where s->>'id'='-413462');
 assert not exists(select 1 from jsonb_array_elements(r->'unresolved_rows') s where s->>'id'='-413465');
 r:=public.solar_capital_snapshot();
 assert (r#>>'{cash,iqd}')::numeric=-100 and r::text not like '%secret4134%';
 assert (r#>>'{suppliers,payable}')::numeric=75 and (r#>>'{opening,supplierNet}')::numeric=31;
 assert exists(select 1 from jsonb_array_elements(r#>'{cash,rows}') s where (s->>'delta')::numeric=-100 and s->>'receiptRestricted'='true' and s->>'receiptNo' is null);
 r:=public.solar_capital_current_snapshot();
 assert (r#>>'{suppliers,payable}')::numeric=75 and (r#>>'{cash,iqd}')::numeric=-100;
 r:=public.solar_inventory('material_report',null,'{"productId":-413461,"withPrices":true}');
 assert jsonb_array_length(r->'rows')=2;
 assert exists(select 1 from jsonb_array_elements(r->'rows') s where s->>'invoiceId' is null and s->>'id' like 'restricted:%'
   and s->>'receiptNo' is null and s->>'party'='' and s->>'pricing' is null and (s->>'inQty')::numeric=5);
 assert exists(select 1 from jsonb_array_elements(r->'rows') s where s->>'invoiceId'='-413462'
   and s->>'party'='ABDULRAHMAN REPORTS' and (s#>>'{pricing,unitPrice}')::numeric=11);
end $$;
rollback;
