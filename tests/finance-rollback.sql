begin;
insert into public.profiles(id,display_name,is_admin,permissions) values
 ('00000000-0000-0000-0000-000000003500','مدير المالية',true,'{}'),
 ('00000000-0000-0000-0000-000000003501','قاصة الموظف',false,'{"cash":true,"customerPayment":true,"suppliers":true}'),
 ('00000000-0000-0000-0000-000000003502','دون صلاحية',false,'{}');
insert into public.products(id,code,name,qty,cost) values(-350001,'FIN-1','مادة الفواصل',0,0);
insert into public.customers(id,name,customer_type,owner_id) values(-350001,'عميل جملة افتتاحي','wholesale','00000000-0000-0000-0000-000000003501');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values
 (-350001,'customer_payment',-350001,'عميل جملة افتتاحي',-100000,false,'opening_balance','00000000-0000-0000-0000-000000003500','00000000-0000-0000-0000-000000003500');
insert into public.transactions(id,kind,total,subtotal,profit,cost,fx_pricing,cash,created_by,cashbox_user_id) values
 (-350002,'sale',400000,400000,100000,300000,true,false,'00000000-0000-0000-0000-000000003500','00000000-0000-0000-0000-000000003500');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003500',true);
select public.solar_exchange_rate_set(1500,0);
do $$declare uid uuid:='00000000-0000-0000-0000-000000003500';staff uuid:='00000000-0000-0000-0000-000000003501';a jsonb;r jsonb;r2 jsonb;p jsonb;req uuid;sid bigint;rows jsonb;begin
 p:=jsonb_build_object('ownerId',uid,'mode','capital_deposit','currency','IQD','amount',1000000,'note','رأس مال');req:=gen_random_uuid();r:=public.solar_cash_save(req,p);r2:=public.solar_cash_save(req,p);
 if r<>r2 or(r->>'afterIQD')::numeric<>1000000 or r->>'receiptNo' is null then raise exception 'FAIL IQD capital/retry: %',r;end if;
 if public.solar_cash_receipt(req)<>r then raise exception 'FAIL reopening cash receipt';end if;
 begin perform public.solar_cash_save(req,p||'{"amount":1}'::jsonb);raise exception 'FAIL changed retry';exception when serialization_failure or sqlstate 'PT409' then null;end;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','capital_deposit','currency','USD','amount',1000.5,'rate',1500,'note','رأس مال دولار'));
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid));
 if(a->'summary'->>'IQD')::numeric<>1000000 or(a->'summary'->>'USD')::numeric<>1000.5 or(a->'summary'->>'usdBook')::numeric<>1500750 or(a->>'retainedProfit')::numeric<>100000 then raise exception 'FAIL separated balances and capital not profit: %',a;end if;
 req:=gen_random_uuid();p:=jsonb_build_object('ownerId',uid,'mode','buy_usd','currency','USD','amount',100.25,'rate',1500,'note','صرف شراء');r:=public.solar_cash_save(req,p);r2:=public.solar_cash_save(req,p);
 if r<>r2 or(r->>'afterIQD')::numeric<>849625 or(r->>'afterUSD')::numeric<>1100.75 or r->>'receiptNo' is null then raise exception 'FAIL atomic exchange/retry: %',r;end if;
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid,'query','صرف شراء'));
 if(a->>'count')::integer<>2 or exists(select 1 from jsonb_array_elements(a->'rows') x where x->>'request_id' is distinct from req::text) then raise exception 'FAIL two exchange legs and shared receipt: %',a;end if;
 if public.solar_cash_receipt(req)<>r then raise exception 'FAIL reopening exchange receipt';end if;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','sell_usd','currency','USD','amount',100.25,'rate',1600,'note','صرف بيع'));
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid));
 if(a->'summary'->>'IQD')::numeric<>1010025 or(a->'summary'->>'USD')::numeric<>1000.5 or(a->>'retainedProfit')::numeric<>110025 then raise exception 'FAIL realized exchange profit: %',a;end if;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','expense','currency','USD','amount',0.5,'rate',1600,'note','مصروف دولار'));
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid));
 if(a->>'retainedProfit')::numeric<>109275 or(a->'summary'->>'USD')::numeric<>1000 then raise exception 'FAIL USD expense at carrying value and FX: %',a;end if;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','capital_withdraw','currency','USD','amount',10,'rate',1600,'note','سحب رأس مال'));
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','expense','currency','IQD','amount',1000,'note','مصروف تشغيلي'));
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','capital_withdraw','currency','IQD','amount',500,'note','سحب رأس مال دينار'));
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid));
 if(a->>'retainedProfit')::numeric<>108275 or(a->'summary'->>'IQD')::numeric<>1008525 or(a->'summary'->>'USD')::numeric<>990 then raise exception 'FAIL expense vs capital: %',a;end if;
 begin perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','distribution','currency','IQD','amount',108276,'note','تجاوز الأرباح'));raise exception 'FAIL profit over-distribution';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','distribution','currency','IQD','amount',100000,'note','توزيع محفوظ'));
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid));
 if(a->>'retainedProfit')::numeric<>8275 or(a->'summary'->>'IQD')::numeric<>908525 then raise exception 'FAIL distribution: %',a;end if;
 begin perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','expense','currency','USD','amount',991,'rate',1500,'note','تجاوز الدولار'));raise exception 'FAIL USD overdraft';exception when no_data_found then null;end;
 begin perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',uid,'mode','expense','currency','IQD','amount',908526,'note','تجاوز الدينار'));raise exception 'FAIL IQD overdraft';exception when no_data_found then null;end;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',staff,'mode','deposit','currency','IQD','amount',200000,'note','إيداع للموظف'));
 a:=public.solar_cash_workspace('{"ownerId":null}');if(a->'summary'->>'IQD')::numeric<>1108525 then raise exception 'FAIL all cash scope';end if;
 -- A new supplier starts in its agreed currency, without a fake conversion.
 req:=gen_random_uuid();p:='{"name":"مورد دولار جديد","currency":"USD","phone":"07712345678"}';r:=public.solar_supplier_save(req,p);r2:=public.solar_supplier_save(req,p);sid:=(r->>'id')::bigint;
 if r<>r2 or r->>'currency'<>'USD' then raise exception 'FAIL explicit new supplier currency';end if;
 begin perform public.solar_supplier_save(gen_random_uuid(),p);raise exception 'FAIL duplicate supplier';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 select x into a from jsonb_array_elements(public.solar_supplier_directory()) x where(x->>'id')::bigint=sid;
 begin perform public.solar_supplier_save(gen_random_uuid(),jsonb_build_object('id',sid,'token',a->>'token','name','مورد دولار جديد','currency','IQD'));raise exception 'FAIL unsafe metadata currency change';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 p:=jsonb_build_object('kind','purchase','party','مورد دولار جديد','partyId',sid,'mode','credit','sourceCurrency','USD','exchangeRate',1500,'marketRate',1500,'accountRevision',0,'items',jsonb_build_array(jsonb_build_object('id',-350001,'qty',2,'price',125.5)));
 r:=public.solar_invoice_save(gen_random_uuid(),p);
 a:=public.solar_fx('account',null,jsonb_build_object('supplierId',sid));if(a->>'balance')::numeric<>251 or(a->>'bookBalance')::numeric<>376500 then raise exception 'FAIL decimal purchase';end if;
 perform public.solar_fx('payment',gen_random_uuid(),jsonb_build_object('supplierId',sid,'paymentId',-350050,'amount',125.5,'currency','USD','rate',1660,'accountRevision',0,'mode','cash','note','تسديد بالكسور'));
 a:=public.solar_fx('account',null,jsonb_build_object('supplierId',sid));if(a->>'balance')::numeric<>125.5 or(a->'usdWallet'->>'amount')::numeric<>864.5 then raise exception 'FAIL nominal account and physical payment';end if;
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid));
 if(a->'summary'->>'IQD')::numeric<>(public.solar_fx('account',null,jsonb_build_object('supplierId',sid))->>'cashBalance')::numeric or(a->'summary'->>'USD')::numeric<>864.5 then raise exception 'FAIL duplicate linked USD cash posting: %',a;end if;
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid,'currency','USD'));select x into rows from jsonb_array_elements(a->'rows') x where x->>'note'='مصروف دولار';
 a:=public.solar_cash_workspace(jsonb_build_object('ownerId',uid,'query','مصروف دولار','currency','USD'));
 if(a->>'count')::integer<>1 or(a->'rows'->0->>'balance')::numeric<>(rows->>'balance')::numeric then raise exception 'FAIL search preserves running balances: %',a;end if;
 begin insert into public.transactions(id,kind,total,cash,created_by) values(-350100,'cash_income',1,true,uid);raise exception 'FAIL raw cash insert';exception when insufficient_privilege then null;end;
 begin delete from public.transactions where cash_purpose='expense';raise exception 'FAIL raw cash delete';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003501',true);
do $$declare a jsonb;r jsonb;p jsonb;req uuid:=gen_random_uuid();begin
 a:=public.solar_cash_workspace('{}');if(a->'summary'->>'IQD')::numeric<>200000 or jsonb_array_length(a->'owners')<>1 then raise exception 'FAIL staff cash scope';end if;
 begin perform public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000003500"}');raise exception 'FAIL foreign cash visibility';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003501","mode":"capital_deposit","currency":"IQD","amount":1,"note":"ممنوع"}');raise exception 'FAIL capital permission';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003501","mode":"buy_usd","currency":"USD","amount":1,"rate":1600,"note":"ممنوع"}');raise exception 'FAIL exchange-rate permission';exception when insufficient_privilege then null;end;
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003501","mode":"expense","currency":"IQD","amount":10000,"note":"مصروف الموظف"}');
 a:=public.solar_customer_payment_context(-350001);if(a->>'balance')::numeric<>100000 then raise exception 'FAIL wholesale opening context';end if;
 p:=jsonb_build_object('customerId',-350001,'invoiceId',null,'amount',25000,'mode','payment','notes','','expectedToken',a->>'token');r:=public.solar_customer_payment_save(req,p);
 if public.solar_customer_payment_save(req,p)<>r or(r->>'remaining')::numeric<>75000 or(r->>'cashAfter')::numeric<>215000 then raise exception 'FAIL wholesale settlement/retry';end if;
 begin perform public.solar_customer_payment_save(gen_random_uuid(),p);raise exception 'FAIL wholesale stale token';exception when serialization_failure or sqlstate 'PT409' then null;end;
 a:=public.solar_customer_payment_context(-350001);p:=jsonb_build_object('customerId',-350001,'invoiceId',null,'amount',5000,'mode','charge_old_balance','notes','إضافة موثقة','expectedToken',a->>'token');r:=public.solar_customer_payment_save(gen_random_uuid(),p);
 if(r->>'remaining')::numeric<>80000 or(r->>'cashAfter')::numeric<>215000 then raise exception 'FAIL wholesale reverse noncash charge';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003502',true);
do $$begin begin perform public.solar_cash_workspace();raise exception 'FAIL permission';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if exists(select 1 from solar_private.wallet_fx_entries e left join solar_private.finance_requests r on r.request_id=e.finance_request_id where e.finance_request_id is not null and r.request_id is null) then raise exception 'FAIL receipt audit linkage';end if;
 if has_function_privilege('anon','public.solar_cash_save(uuid,jsonb)','execute') or has_function_privilege('authenticated','solar_private.retained_profit(uuid)','execute') or has_table_privilege('authenticated','solar_private.finance_requests','select') then raise exception 'FAIL private ledger privileges';end if;
 if(select sum(delta) from solar_private.cash_movements() where owner_id='00000000-0000-0000-0000-000000003500' and currency='USD')<>864.5 then raise exception 'FAIL server movement totals';end if;
end $$;
select 'PASS unified cash, both currencies, decimal purchases, receipt retry, owner scope, expenses/capital, retained profit, protected writes, supplier directory and wholesale settlement' result;
rollback;
