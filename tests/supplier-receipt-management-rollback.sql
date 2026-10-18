\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,permissions) values
('00000000-0000-0000-0000-000000003400','مدير المورد','supplier_admin',true,'{}'),
('00000000-0000-0000-0000-000000003401','موظف المورد','supplier_staff',false,'{"supplierPayment":true,"supplierStatement":true,"cash":true,"exchangeRateEdit":true}'),
('00000000-0000-0000-0000-000000003402','موظف آخر','supplier_other',false,'{"supplierPayment":true}');
insert into suppliers(id,name,account_currency) values(-340001,'مورد اختبار الدولار','USD');
insert into solar_private.supplier_fx_entries(supplier_id,owner_id,currency,revision,delta,book_delta,rate,note) values(-340001,'00000000-0000-0000-0000-000000003401','USD',0,1000,1500000,1500,'افتتاحي للاختبار');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003400',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003401","mode":"deposit","currency":"USD","amount":1000,"rate":1500,"note":"رصيد دولار"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003401","mode":"deposit","currency":"IQD","amount":500000,"note":"رصيد دينار"}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003401',true);
select public.solar_fx('payment','00000000-0000-0000-0000-000000003410','{"paymentId":-340101,"supplierId":-340001,"amount":100,"currency":"USD","rate":1500,"accountRevision":0,"mode":"cash","note":"تسديد قديم"}');
select public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-340102,"supplierId":-340001,"amount":50,"currency":"USD","rate":1600,"accountRevision":0,"mode":"cash","note":"تسديد لاحق مثبت"}');
reset role;
create temporary table frozen as select (select to_jsonb(e) from solar_private.supplier_fx_entries e where transaction_id=-340102) account_entry,(select to_jsonb(w) from solar_private.wallet_fx_entries w where transaction_id=-340102) wallet_entry;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003400',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003401","mode":"deposit","currency":"USD","amount":50,"rate":1700,"note":"دولار لاحق"}');
do $$declare c jsonb;r jsonb;b jsonb;rid uuid:=gen_random_uuid();delid uuid:=gen_random_uuid();replacement_id bigint;begin
 c:=public.solar_supplier_payment_manage('list',null,'{"query":"مورد اختبار"}');if jsonb_array_length(c->'rows')<>2 then raise exception 'history list';end if;
 c:=public.solar_supplier_payment_manage('get',null,'{"id":-340101}');
 if(c->>'balance')::numeric<>850 or(c->>'cashBalance')::numeric<>900 then raise exception 'initial balance';end if;
 r:=public.solar_supplier_payment_manage('update',gen_random_uuid(),jsonb_build_object('id',-340101,'expectedToken',c->>'token','amount',100,'rate',1500,'notes','ملاحظات فقط'));if not(r->>'notesOnly')::boolean or(r->'replacement'->>'id')::bigint<>-340101 or(r->>'balance')::numeric<>850 or(r->>'cashBalance')::numeric<>900 then raise exception 'notes changed balances';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003401',true);
 begin perform public.solar_fx('payment','00000000-0000-0000-0000-000000003410','{"paymentId":-340101,"supplierId":-340001,"amount":100,"currency":"USD","rate":1500,"accountRevision":0,"mode":"cash","note":"تسديد قديم"}');raise exception 'notes stale replay';exception when serialization_failure then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003400',true);
 c:=public.solar_supplier_payment_manage('get',null,'{"id":-340101}');
 b:=jsonb_build_object('id',-340101,'expectedToken',c->>'token','amount',2000,'rate',1500,'notes','اختبار زيادة غير متاحة');
 begin perform public.solar_supplier_payment_manage('update',gen_random_uuid(),b);raise exception 'overspend allowed';exception when sqlstate 'P0002' then null;end;
 r:=public.solar_supplier_payment_manage('get',null,'{"id":-340101}');if r->>'token'<>c->>'token' then raise exception 'failed edit changed data';end if;
 b:=b||jsonb_build_object('amount',80,'notes','تم تعديل القديم');r:=public.solar_supplier_payment_manage('update',rid,b);replacement_id:=(r->'replacement'->>'id')::bigint;
 if(r->>'balance')::numeric<>870 or(r->>'cashBalance')::numeric<>920 then raise exception 'edit account/cash';end if;
 if public.solar_supplier_payment_manage('update',rid,b)<>r then raise exception 'retry duplicated';end if;
 begin perform public.solar_supplier_payment_manage('get',null,'{"id":-340101}');raise exception 'voided reopened';exception when serialization_failure then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003402',true);
 begin perform public.solar_supplier_payment_manage('get',null,jsonb_build_object('id',replacement_id));raise exception 'other staff read';exception when insufficient_privilege then null;end;
 if jsonb_array_length(public.solar_supplier_payment_manage('list')->'rows')<>0 then raise exception 'scope leak';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003401',true);
 begin perform public.solar_fx('payment','00000000-0000-0000-0000-000000003410','{"paymentId":-340101,"supplierId":-340001,"amount":100,"currency":"USD","rate":1500,"accountRevision":0,"mode":"cash","note":"تسديد قديم"}');raise exception 'stale original replay';exception when serialization_failure then null;end;
 c:=public.solar_supplier_payment_manage('get',null,jsonb_build_object('id',replacement_id));b:=jsonb_build_object('id',replacement_id,'expectedToken',c->>'token');r:=public.solar_supplier_payment_manage('delete',delid,b);
 if(r->>'balance')::numeric<>950 or(r->>'cashBalance')::numeric<>1000 then raise exception 'delete account/cash';end if;
 if public.solar_supplier_payment_manage('delete',delid,b)<>r then raise exception 'delete replay';end if;
 -- IQD payment of a USD debt restores IQD, with account currency conversion preserved.
 r:=public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-340103,"supplierId":-340001,"amount":150000,"currency":"IQD","rate":1500,"accountRevision":0,"mode":"cash","note":"تسديد دينار لحساب دولار"}');
 c:=public.solar_supplier_payment_manage('get',null,'{"id":-340103}');if(c->>'balance')::numeric<>850 then raise exception 'IQD into USD debt';end if;
 r:=public.solar_supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',-340103,'expectedToken',c->>'token'));if(r->>'cashBalance')::numeric<>500000 or(r->>'balance')::numeric<>950 then raise exception 'IQD refund';end if;
 r:=public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-340104,"supplierId":-340001,"amount":50,"currency":"USD","rate":1500,"accountRevision":0,"mode":"charge_other","note":"إضافة غير نقدية"}');
 c:=public.solar_supplier_payment_manage('get',null,'{"id":-340104}');r:=public.solar_supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',-340104,'expectedToken',c->>'token'));
 if(r->>'balance')::numeric<>950 or(r->>'cashBalance')::numeric<>500000 then raise exception 'charge cancellation';end if;
end $$;
reset role;
do $$declare f record;begin
 select * into f from frozen;
 if(select to_jsonb(e) from solar_private.supplier_fx_entries e where transaction_id=-340102) is distinct from f.account_entry or(select to_jsonb(w) from solar_private.wallet_fx_entries w where transaction_id=-340102) is distinct from f.wallet_entry then raise exception 'later costs repriced';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003400')<>0 then raise exception 'admin cash changed instead of owner';end if;
 if(solar_private.usd_wallet('00000000-0000-0000-0000-000000003401')->>'amount')::numeric<>1000 or(solar_private.usd_wallet('00000000-0000-0000-0000-000000003401')->>'book')::numeric<>1510000 then raise exception 'USD book not restored';end if;
 if(select count(*) from solar_private.receipt_change_audit)<>5 then raise exception 'audit count';end if;
 if has_function_privilege('anon','public.solar_supplier_payment_manage(text,uuid,jsonb)','EXECUTE') then raise exception 'anon execute';end if;
 raise notice 'PASS edit/delete old supplier payment, subsequent FX postings unchanged, refund currency, noncash charge, atomic failure, replay and owner/admin scope';
end $$;
rollback;
