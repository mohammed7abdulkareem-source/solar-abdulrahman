\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003600','إدارة الصندوق',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003601','صاحب الأرباح الخارجية',false,'admin_staff','{"cash":true,"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003602','مستلم الأموال',false,'admin_staff','{"financeReceive":true}'),
('00000000-0000-0000-0000-000000003603','إدارة قاصته',false,'admin_staff','{"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000003604','مخزن بصلاحية قديمة',true,'warehouse','{"cash":true,"cashAdminTools":true,"cashExternalProfit":true}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003600',true);
select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003601","mode":"deposit","currency":"IQD","amount":1000000,"note":"رصيد للاختبار"}');
set local role authenticated;
do $$declare p jsonb;m text;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003601',true);
 if jsonb_array_length(public.solar_cash_workspace()->'owners')<>1 then raise exception 'cash directory leaked';end if;
 foreach m in array array['deposit','expense','buy_usd','sell_usd','external_profit','capital_deposit','capital_withdraw'] loop
  begin perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode',m,'currency','IQD','amount',1,'note','محاولة بلا صلاحية'));raise exception 'cash view granted action %',m;exception when insufficient_privilege then null;end;
 end loop;
 begin perform public.solar_fx('wallet',gen_random_uuid(),'{"mode":"buy_usd","amount":1,"rate":1660,"note":"منفذ قديم"}');raise exception 'legacy exchange bypassed granular rights';exception when insufficient_privilege then null;end;
end$$;
reset role;
update profiles set permissions=permissions||'{"cashExternalProfit":true}' where id='00000000-0000-0000-0000-000000003601';
set local role authenticated;
do $$declare p jsonb;r jsonb;req uuid:=gen_random_uuid();a jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003601',true);
 p:=jsonb_build_object('ownerId',auth.uid(),'mode','external_profit','currency','IQD','amount',200000,'note','أرباح خدمة خارجية');
 r:=public.solar_cash_save(req,p);if(r->>'afterIQD')::numeric<>1200000 or(r->>'profitAmountIQD')::numeric<>200000 then raise exception 'external income missing from cash';end if;
 if public.solar_cash_save(req,p)<>r then raise exception 'external income replay differed';end if;
 perform set_config('test.external.id',r->>'id',true);
 a:=public.solar_profit_workspace('overview');if(a->>'available')::numeric<>200000 or not exists(select 1 from jsonb_array_elements(a->'rows') x where x->>'kind'='external_profit' and x->>'label' like 'أرباح خارجية%') then raise exception 'external income missing from own period profit %',a;end if;
 a:=public.solar_profit_detail('tx:'||(r->>'id'),auth.uid());if a->'invoice'->>'notes'<>'أرباح خدمة خارجية' then raise exception 'external profit statement lost description';end if;
 r:=public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','external_profit','currency','USD','amount',100,'rate',1660,'note','ربح خارجي دولار'));
 if(r->>'afterUSD')::numeric<>100 or(r->>'afterIQD')::numeric<>1200000 or(r->>'profitAmountIQD')::numeric<>166000 then raise exception 'USD external income posting wrong %',r;end if;
 begin perform public.solar_cash_save(gen_random_uuid(),p||'{"ownerId":"00000000-0000-0000-0000-000000003602"}');raise exception 'external profits posted to other cashbox';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003602',true);
 begin perform public.solar_profit_detail('tx:'||current_setting('test.external.id'),'00000000-0000-0000-0000-000000003601');raise exception 'other user profit leaked';exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003600',true);
select public.solar_exchange_rate_set(1700,(public.solar_exchange_rate_get()->>'revision')::bigint);
do $$begin if solar_private.retained_profit('00000000-0000-0000-0000-000000003601')<>366000 then raise exception 'external profit revalued or repeated';end if;end$$;
update profiles set permissions=permissions||'{"cashExternalProfit":false,"cashExpense":true,"cashExchange":true}' where id='00000000-0000-0000-0000-000000003601';
set local role authenticated;
do $$declare r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003601',true);
 begin perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','external_profit','currency','IQD','amount',1,'note','صلاحية مسحوبة'));raise exception 'revoked external permission allowed';exception when insufficient_privilege then null;end;
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','expense','currency','IQD','amount',50000,'note','مصروف تشغيلي'));
 perform public.solar_fx('wallet',gen_random_uuid(),'{"mode":"buy_usd","amount":10,"rate":1700,"note":"شراء دولار"}');
 begin perform public.solar_fx('wallet',gen_random_uuid(),'{"mode":"deposit","amount":10,"rate":1700,"note":"رأس مال"}');raise exception 'exchange granted capital tools';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin if solar_private.retained_profit('00000000-0000-0000-0000-000000003601')<>316000 then raise exception 'profit expenses or exchange wrong';end if;end$$;
set local role authenticated;
do $$declare c jsonb;r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003603',true);
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','capital_deposit','currency','IQD','amount',5000,'note','رأس مال قاصتي'));
 begin perform public.solar_cash_reconcile('context',null,'{}');raise exception 'staff tools exposed all boxes';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_reconcile('context',null,'{"ownerId":"00000000-0000-0000-0000-000000003601"}');raise exception 'staff tools exposed another box';exception when insufficient_privilege then null;end;
 c:=public.solar_cash_reconcile('context',null,jsonb_build_object('ownerId',auth.uid()));if jsonb_array_length(c->'owners')<>1 then raise exception 'other cashbox names leaked';end if;
 r:=public.solar_cash_reconcile('apply',gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','set','currency','IQD','target',7000,'note','مطابقة قاصتي','expectedToken',c->>'token'));
 if(r->'rows'->0->>'afterIQD')::numeric<>7000 then raise exception 'own reconciliation failed';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003604',true);
 begin perform public.solar_cash_reconcile('context',null,jsonb_build_object('ownerId',auth.uid()));raise exception 'warehouse stale admin gained cash tools';exception when insufficient_privilege then null;end;
end$$;
reset role;
update profiles set permissions=permissions||'{"cashExpense":false,"cashTransferSend":true}' where id='00000000-0000-0000-0000-000000003601';
set local role authenticated;
do $$declare rid uuid;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003601',true);
 begin perform public.solar_cash_transfer_send(gen_random_uuid(),'00000000-0000-0000-0000-000000003602',10000,1,'مصروف','');raise exception 'handover bypassed expense grant';exception when insufficient_privilege then null;end;
 rid:=public.solar_cash_transfer_send(gen_random_uuid(),'00000000-0000-0000-0000-000000003602',10000,0,'','تحويل بلا مصروف');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003602',true);perform public.solar_cash_transfer_decide(rid,'accepted');
 if(public.solar_cash_workspace()->'summary'->>'IQD')::numeric<>10000 then raise exception 'receive-only permission failed';end if;
end$$;
reset role;
do $$begin
 if solar_private.retained_profit('00000000-0000-0000-0000-000000003602')<>0 then raise exception 'cash receipt treated as external profit';end if;
 if(select count(*) from transactions where cash_purpose='external_profit')<>2 then raise exception 'duplicate external transaction';end if;
 if has_function_privilege('anon','solar_private.cash_allowed(text)','execute') then raise exception 'private cash authorization exposed';end if;
 raise notice 'PASS granular cash actions and legacy exchange, own cash administration, independent transfer expenses, external IQD/USD profit exactly once and fixed-rate periods, revocation, ownership and role isolation';
end$$;
rollback;
