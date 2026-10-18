begin;
insert into public.profiles(id,display_name,is_admin,permissions) values
 ('00000000-0000-0000-0000-000000003400','مدير العملات',true,'{}'),
 ('00000000-0000-0000-0000-000000003401','موظف العملات',false,'{"purchase":true,"supplierPayment":true,"supplierStatement":true,"cash":true}'),
 ('00000000-0000-0000-0000-000000003402','بلا صلاحيات',false,'{}');
insert into public.suppliers(id,name) values(-340001,'المورد الدولاري'),(-340002,'المورد الديناري');
insert into public.products(id,code,name,qty,cost) values(-340001,'FX-1','مادة عملات',0,0);
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-340000,'cash_income',10000000,true,'00000000-0000-0000-0000-000000003400','00000000-0000-0000-0000-000000003400');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003400',true);
select public.solar_exchange_rate_set(1500,0);
do $$declare a jsonb;r jsonb;r2 jsonb;req uuid:=gen_random_uuid();p jsonb;tid bigint;token text;begin
 a:=public.solar_fx('account',null,'{"supplierId":-340001}');
 perform public.solar_fx('currency',gen_random_uuid(),jsonb_build_object('supplierId',-340001,'currency','USD','rate',1500,'expectedRevision',0,'expectedToken',a->>'token','note','اتفاق الدولار'));
 p:='{"kind":"purchase","party":"المورد الدولاري","partyId":-340001,"mode":"credit","sourceCurrency":"USD","exchangeRate":1500,"marketRate":1500,"accountRevision":1,"cashCurrency":"IQD","items":[{"id":-340001,"qty":10,"price":100}]}';
 r:=public.solar_invoice_save(req,p);tid:=(r->>'id')::bigint;
 r2:=public.solar_invoice_save(req,p);if r<>r2 then raise exception 'FAIL invoice retry';end if;
 a:=public.solar_fx('account',null,'{"supplierId":-340001}');if(a->>'balance')::numeric<>1000 or(a->>'bookBalance')::numeric<>1500000 then raise exception 'FAIL USD account from USD invoice: %',a;end if;
 -- Pay 700,000 IQD at 1,400: supplier USD balance decreases by exactly 500.
 r:=public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-340001,"paymentId":-340002,"amount":700000,"currency":"IQD","rate":1400,"accountRevision":1,"mode":"cash","note":"دينار مقابل دولار"}');
 a:=public.solar_fx('account',null,'{"supplierId":-340001}');if(a->>'balance')::numeric<>500 or(a->>'bookBalance')::numeric<>750000 or(a->>'cashBalance')::numeric<>9300000 then raise exception 'FAIL IQD paying USD account: %',a;end if;
 -- An old purchase cannot be revalued after a settlement.
 begin perform public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('invoiceId',tid,'expectedRevision',0,'items','[{"id":-340001,"qty":10,"price":90}]'::jsonb));raise exception 'FAIL edit old AP';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 -- Deposit actual dollar capital, then pay the remaining 500 USD at another rate.
 perform public.solar_fx('wallet',gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003400","mode":"deposit","amount":1000,"rate":1400,"note":"رصيد دولار"}');
 p:='{"supplierId":-340001,"paymentId":-340003,"amount":500,"currency":"USD","rate":1600,"accountRevision":1,"mode":"cash","note":"تسديد دولار"}';req:=gen_random_uuid();
 r:=public.solar_fx('payment',req,p);r2:=public.solar_fx('payment',req,p);if r<>r2 then raise exception 'FAIL payment retry';end if;
 a:=public.solar_fx('account',null,'{"supplierId":-340001}');if(a->>'balance')::numeric<>0 or(a->>'bookBalance')::numeric<>0 or(a->'usdWallet'->>'amount')::numeric<>500 or(a->>'cashBalance')::numeric<>9300000 then raise exception 'FAIL USD payment and no IQD double-debit: %',a;end if;
 -- IQD invoice on a USD account, then exact USD payment, freezes original 1,500 rate.
 p:='{"kind":"purchase","party":"المورد الدولاري","mode":"credit","sourceCurrency":"IQD","exchangeRate":1,"marketRate":1500,"accountRevision":1,"items":[{"id":-340001,"qty":2,"price":150000}]}';
 perform public.solar_invoice_save(gen_random_uuid(),p);
 a:=public.solar_fx('account',null,'{"supplierId":-340001}');if(a->>'balance')::numeric<>200 then raise exception 'FAIL IQD invoice to USD account';end if;
 -- Currency conversion preserves book value and keeps a separately readable old register.
 perform public.solar_fx('currency',gen_random_uuid(),jsonb_build_object('supplierId',-340001,'currency','IQD','rate',1400,'expectedRevision',1,'expectedToken',a->>'token','note','اتفاق دينار'));
 a:=public.solar_fx('account',null,'{"supplierId":-340001}');if(a->>'balance')::numeric<>280000 or(a->>'bookBalance')::numeric<>300000 then raise exception 'FAIL currency conversion book carry: %',a;end if;
 begin perform public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-340001,"paymentId":-340004,"amount":1,"currency":"USD","rate":1500,"accountRevision":1,"mode":"cash"}');raise exception 'FAIL stale currency revision';exception when serialization_failure or sqlstate 'PT409' then null;end;
 -- Dollar invoice into IQD account. Purchase costs stay in IQD weighted average.
 perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"المورد الديناري","mode":"credit","sourceCurrency":"USD","exchangeRate":1450,"marketRate":1450,"accountRevision":0,"items":[{"id":-340001,"qty":2,"price":100}]}');
 a:=public.solar_fx('account',null,'{"supplierId":-340002}');if(a->>'balance')::numeric<>290000 then raise exception 'FAIL USD invoice to IQD account';end if;
 a:=public.solar_party_balances('suppliers',(now() at time zone 'Asia/Baghdad')::date);
 if not exists(select 1 from jsonb_array_elements(a->'rows') x where x->>'id'='-340002' and x->>'currency'='IQD' and(x->>'balance')::numeric=290000) then raise exception 'FAIL denomination balances report: %',a;end if;
 -- Real exchange touches both cash currencies once, with idempotent retry.
 p:='{"mode":"buy_usd","amount":100,"rate":1500,"note":"شراء دولار"}';req:=gen_random_uuid();r:=public.solar_fx('wallet',req,p);r2:=public.solar_fx('wallet',req,p);
 if r<>r2 or(r->>'cashBalance')::numeric<>9150000 or(r->'usdWallet'->>'amount')::numeric<>600 then raise exception 'FAIL two wallet exchange';end if;
 -- Non-cash dollar charge, then latest edit and stale-token rejection.
 p:='{"supplierId":-340002,"paymentId":-340010,"amount":100,"currency":"USD","rate":1500,"accountRevision":0,"mode":"charge_old_balance","note":"حساب قديم بالدولار"}';
 r:=public.solar_fx('payment',gen_random_uuid(),p);token:=r->>'token';
 r:=public.solar_fx('payment',gen_random_uuid(),p||jsonb_build_object('amount',200,'expectedToken',token));
 if(r->>'total')::numeric<>-300000 or(r->>'sourceSubtotal')::numeric<>-200 or(r->>'cash')::boolean then raise exception 'FAIL USD charge edit';end if;
 begin perform public.solar_fx('payment',gen_random_uuid(),p||jsonb_build_object('expectedToken',token));raise exception 'FAIL stale payment';exception when serialization_failure or sqlstate 'PT409' then null;end;
 a:=public.solar_fx('account',null,'{"supplierId":-340002}');if(a->>'balance')::numeric<>590000 or(a->>'cashBalance')::numeric<>9150000 or(a->'usdWallet'->>'amount')::numeric<>600 then raise exception 'FAIL charge no cash effect: %',a;end if;
 begin perform public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-340002,"paymentId":-340005,"amount":601,"currency":"USD","rate":1500,"accountRevision":0,"mode":"cash"}');raise exception 'FAIL USD overdraft';exception when no_data_found then null;end;
 begin update public.suppliers set account_currency='USD' where id=-340002;raise exception 'FAIL raw currency change';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003401',true);
do $$begin
 if(public.solar_fx('account',null,'{"supplierId":-340001}')->>'balance')::numeric<>0 then raise exception 'FAIL owner scope';end if;
 begin perform public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-340002,"paymentId":-340006,"amount":1,"currency":"IQD","rate":1234,"accountRevision":0,"mode":"charge_other","note":"اختبار"}');raise exception 'FAIL rate permission';exception when insufficient_privilege then null;end;
 begin perform public.solar_fx('wallet',gen_random_uuid(),'{"mode":"deposit","amount":1,"rate":1500,"note":"اختبار"}');raise exception 'FAIL capital permission';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003402',true);
do $$begin begin perform public.solar_fx('payment',gen_random_uuid(),'{}');raise exception 'FAIL permission';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if(select sum(gain) from solar_private.supplier_fx_entries)<>100000 then raise exception 'FAIL realized FX separated from merchandise profit';end if;
 if has_function_privilege('anon','public.solar_fx(text,uuid,jsonb)','execute') or has_table_privilege('authenticated','solar_private.wallet_fx_entries','insert') then raise exception 'FAIL ledger access';end if;
end $$;
select 'PASS supplier currencies, both payment currencies, physical wallets, rates, conversion, retries, scope and realized FX' result;
rollback;
