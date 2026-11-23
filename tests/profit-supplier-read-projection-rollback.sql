\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions) values
 ('00000000-0000-0000-0000-000000413341','مدير الاختبار',true,'admin_staff',true,'{}'),
 ('00000000-0000-0000-0000-000000413342','صاحب التسوية',false,'admin_staff',true,'{"profit":true,"profitSettlement":true}');
insert into public.suppliers(id,name,account_currency) values(-413341,'مورد اختبار التفاصيل','USD');
insert into solar_private.supplier_fx_entries(id,supplier_id,owner_id,currency,revision,delta,book_delta,rate,gain,note) overriding system value
 values(-413341,-413341,'00000000-0000-0000-0000-000000413342','USD',0,1,1000,1450,450,'supplier-private-note #381');
insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,gain,entry_type,note) overriding system value values
 (-413342,'00000000-0000-0000-0000-000000413342','USD',1,1000,1450,450,'supplier_payment_refund','supplier-private-note #382'),
 (-413343,'00000000-0000-0000-0000-000000413342','USD',-1,-1000,1400,400,'sell_usd','تبديل قاصتي');
insert into solar_private.profit_settlements(id,owner_id,date_to,snapshot,profit,status,share,receipt,settlement_model,
 supplier_id,supplier_amount_iqd,supplier_currency,supplier_amount,supplier_rate,supplier_receipt)
 values('00000000-0000-0000-0000-000000413343','00000000-0000-0000-0000-000000413342',current_date,
 '[{"key":"supplierfx:-413341","kind":"fx_gain","label":"supplier-private-note #381","receiptNo":381,"value":450}]',
 3900,'approved',1000,'{"receiptNo":655,"amount":1000}','owner_debit_supplier_charge',
 -413341,2900,'USD',2,1450,'{"receiptNo":381,"name":"supplier-private-name","beforeBalance":99,"afterBalance":101}');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413342',true);
do $$
declare overview jsonb; report jsonb; request jsonb; item jsonb;
begin
 overview:=public.solar_profit_workspace('overview',null,'{}');
 report:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',auth.uid()));
 select x into strict request from jsonb_array_elements(overview->'requests') x where x->>'id'='00000000-0000-0000-0000-000000413343';
 assert not request ?| array['supplier_id','supplier_amount','supplier_currency','supplier_rate','supplier_receipt'];
 assert (request->>'profit')::numeric=3900 and (request->>'share')::numeric=1000 and (request->>'supplier_amount_iqd')::numeric=2900;
 assert (request#>>'{receipt,receiptNo}')::int=655 and (request#>>'{snapshot,0,value}')::numeric=450;
 assert request#>'{snapshot,0,receiptNo}'='null'::jsonb;
 assert overview::text not like '%supplier-private%' and report::text not like '%supplier-private%';
 foreach item in array array[public.solar_profit_detail('supplierfx:-413341',auth.uid()),public.solar_profit_detail('walletfx:-413342',auth.uid())] loop
  assert item::text not like '%supplier-private%' and (item#>>'{movement,value}')::numeric=450;
 end loop;
 assert public.solar_profit_detail('walletfx:-413343',auth.uid())#>>'{movement,label}'='تبديل قاصتي';
 assert (report#>>'{period,earned}')::numeric=1300;
end $$;

reset role;
update public.profiles set permissions=permissions||'{"supplierStatement":true}' where id='00000000-0000-0000-0000-000000413342';
set local role authenticated;
do $$
declare overview jsonb; request jsonb;
begin
 overview:=public.solar_profit_workspace('overview',null,'{}');
 select x into strict request from jsonb_array_elements(overview->'requests') x where x->>'id'='00000000-0000-0000-0000-000000413343';
 assert (request->>'supplier_id')::bigint=-413341 and (request->>'supplier_amount')::numeric=2;
 assert public.solar_profit_detail('supplierfx:-413341',auth.uid())#>>'{movement,label}'='supplier-private-note #381';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413341',true);
 overview:=public.solar_profit_workspace('overview',null,'{"ownerId":"00000000-0000-0000-0000-000000413342"}');
 select x into strict request from jsonb_array_elements(overview->'requests') x where x->>'id'='00000000-0000-0000-0000-000000413343';
 assert (request#>>'{supplier_receipt,afterBalance}')::numeric=101;
end $$;

-- Both suppliers are on the same personal profit account. Even with all
-- ordinary supplier features, only the named supplier's references are hidden.
reset role;
update public.profiles set permissions=permissions||'{"supplierPayment":true,"supplierBalances":true,"suppliers":true,"cash":true}'
 where id='00000000-0000-0000-0000-000000413342';
insert into public.suppliers(id,name,account_currency) values(-413351,'ABDULRAHMAN','USD');
insert into solar_private.supplier_fx_entries(id,supplier_id,owner_id,currency,revision,delta,book_delta,rate,gain,note,correction_for)
 overriding system value values
 (-413351,-413351,'00000000-0000-0000-0000-000000413342','USD',0,2,1800,1000,200,'named-private-refund #447',-413360),
 (-413352,-413341,'00000000-0000-0000-0000-000000413342','USD',0,1,1000,1450,0,'supplier-private-note #382',-413361);
insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,gain,entry_type,note)
 overriding system value values
 (-413351,'00000000-0000-0000-0000-000000413342','USD',2,1800,1000,200,'supplier_payment_refund','named-private-refund #447');
insert into solar_private.profit_settlements(id,owner_id,date_to,snapshot,profit,status,share,receipt,settlement_model,
 supplier_id,supplier_amount_iqd,supplier_currency,supplier_amount,supplier_rate,supplier_receipt)
 values('00000000-0000-0000-0000-000000413351','00000000-0000-0000-0000-000000413342',current_date,
 '[{"key":"supplierfx:-413351","kind":"fx_gain","label":"named-private-refund #447","receiptNo":447,"value":200}]',
 3000,'approved',1000,'{"receiptNo":656,"amount":1000}','owner_debit_supplier_charge',
 -413351,2000,'USD',2,1000,'{"receiptNo":447,"name":"ABDULRAHMAN","beforeBalance":123,"afterBalance":125}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413342',true);
do $$
declare overview jsonb; request jsonb; cash jsonb; fx jsonb; movement jsonb; account_row jsonb;
begin
 overview:=public.solar_profit_workspace('overview',null,'{}');
 select x into strict request from jsonb_array_elements(overview->'requests') x where x->>'id'='00000000-0000-0000-0000-000000413351';
 assert not request ?| array['supplier_id','supplier_amount','supplier_currency','supplier_rate','supplier_receipt'];
 assert (request->>'supplier_amount_iqd')::numeric=2000 and (request->>'share')::numeric=1000;
 assert overview::text not like '%named-private-refund%' and overview::text not like '%ABDULRAHMAN%';
 assert (public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',auth.uid()))#>>'{period,earned}')::numeric=1700;
 assert public.solar_profit_detail('walletfx:-413342',auth.uid())#>>'{movement,label}'='supplier-private-note #382';
 assert public.solar_profit_detail('walletfx:-413351',auth.uid())#>>'{movement,label}'='فرق صرف قاصة';
 assert public.solar_profit_detail('supplierfx:-413351',auth.uid())#>>'{movement,label}'='فرق صرف مورد';
 cash:=public.solar_cash_workspace('{"query":"named-private-refund"}');
 assert (cash->>'count')::int=0;
 cash:=public.solar_cash_workspace('{}');
 select x into strict movement from jsonb_array_elements(cash->'rows') x
  where (x->>'delta')::numeric=2 and x->>'receiptRestricted'='true';
 assert (movement->>'book_delta')::numeric=1800 and not movement ?| array['rate','source_currency','sourceCurrency'];
 cash:=public.solar_cash_workspace('{"query":"supplier-private-note #382"}');
 assert (cash->>'count')::int=1;
 fx:=public.solar_fx('state',null,'{}');
 assert fx::text not like '%named-private-refund%';
 select x into strict movement from jsonb_array_elements(fx->'walletEntries') x
  where (x->>'delta')::numeric=2 and x->>'receiptRestricted'='true';
 assert (movement->>'gain')::numeric=200 and (movement->>'book_delta')::numeric=1800;
 assert not movement ?| array['transaction_id','finance_request_id','supplier_id','rate'];
 select x into strict account_row from jsonb_array_elements(fx->'accountEntries') x where (x->>'id')::bigint=-413341;
 assert account_row->>'note'='supplier-private-note #381';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413341',true);
 overview:=public.solar_profit_workspace('overview',null,'{"ownerId":"00000000-0000-0000-0000-000000413342"}');
 select x into strict request from jsonb_array_elements(overview->'requests') x where x->>'id'='00000000-0000-0000-0000-000000413351';
 assert (request#>>'{supplier_receipt,afterBalance}')::numeric=125;
end $$;
rollback;
