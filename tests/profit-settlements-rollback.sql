\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,permissions) values
('00000000-0000-0000-0000-000000003430','مدير الأرباح','profit_admin',true,'{}'),
('00000000-0000-0000-0000-000000003431','صاحب الأرباح','profit_staff',false,'{"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003432','آخر','profit_other',false,'{"profit":true}'),
('00000000-0000-0000-0000-000000003433','بدون صلاحية','profit_none',false,'{}');
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,created_at) values
(-343001,'sale',1000000,1000000,300000,true,false,'credit','00000000-0000-0000-0000-000000003431','00000000-0000-0000-0000-000000003431',now()-interval '1 day'),
(-343002,'sale',700000,700000,200000,true,false,'credit','00000000-0000-0000-0000-000000003432','00000000-0000-0000-0000-000000003432',now()-interval '1 day');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003430',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003430","mode":"capital_deposit","currency":"IQD","amount":1000000,"note":"قاصة للاختبار"}');
do $$declare c jsonb;r jsonb;b jsonb;d jsonb;old_result jsonb;req uuid:=gen_random_uuid();decision uuid:=gen_random_uuid();begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003433',true);
 begin perform public.solar_profit_workspace('overview');raise exception 'no permission allowed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003431',true);
 c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>300000 or jsonb_array_length(c->'rows')<>1 then raise exception 'credit profit / scope';end if;
 begin perform public.solar_profit_workspace('overview',null,'{"ownerId":"00000000-0000-0000-0000-000000003432"}');raise exception 'owner leak';exception when insufficient_privilege then null;end;
 if(public.solar_profit_workspace('overview',null,jsonb_build_object('from',(now() at time zone 'Asia/Baghdad')::date))->>'available')::numeric<>0 then raise exception 'date period ignored';end if;
 b:=jsonb_build_object('expectedToken',c->>'token');r:=public.solar_profit_workspace('request',req,b);
 if public.solar_profit_workspace('request',req,b)<>r then raise exception 'request replay';end if;
 begin perform public.solar_profit_workspace('request',gen_random_uuid(),b);raise exception 'duplicate pending allowed';exception when raise_exception then if sqlerrm='duplicate pending allowed' then raise;end if;end;
 c:=public.solar_profit_workspace('overview');d:=c->'requests'->0;
 b:=jsonb_build_object('id',req,'expectedToken',d->>'token','share',75000,'cashOwnerId','00000000-0000-0000-0000-000000003430','collectionConfirmed',true);
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b);raise exception 'staff approval allowed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003430',true);
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b||'{"collectionConfirmed":false}');raise exception 'unconfirmed allowed';exception when raise_exception then if sqlerrm='unconfirmed allowed' then raise;end if;end;
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b||'{"share":300001}');raise exception 'excess share allowed';exception when raise_exception then if sqlerrm='excess share allowed' then raise;end if;end;
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b||'{"cashOwnerId":"00000000-0000-0000-0000-000000003432"}');raise exception 'overdraft allowed';exception when sqlstate 'P0002' then null;end;
 old_result:=public.solar_profit_workspace('approve',decision,b);
 if public.solar_profit_workspace('approve',decision,b)<>old_result then raise exception 'decision replay';end if;
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b);raise exception 'paid twice';exception when serialization_failure or sqlstate 'PT409' then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003431',true);
 c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>0 or(c->'requests'->0->>'share')::numeric<>75000 then raise exception 'reset/history';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003432',true);
 c:=public.solar_profit_workspace('overview');if jsonb_array_length(c->'requests')<>0 then raise exception 'history leak';end if;
 begin perform public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token'));raise exception 'view-only request allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$begin
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003430')<>925000 then raise exception 'payer cash';end if;
 if(select count(*) from transactions where profit_settlement_id is not null)<>1 then raise exception 'expense duplicated';end if;
 if(select sum(total) from transactions where cash_purpose='expense')<>75000 then raise exception 'company expense';end if;
 if(select profit from transactions where id=-343001)<>300000 then raise exception 'source invoice changed';end if;
 if has_function_privilege('anon','public.solar_profit_workspace(text,uuid,jsonb)','EXECUTE') then raise exception 'anon execute';end if;
end $$;
-- Corrections to an already settled sale remain visible, including deletion.
update transactions set profit=250000 where id=-343001;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003431',true);
do $$declare c jsonb;begin c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>-50000 then raise exception 'post-settlement correction lost';end if;end $$;
reset role;
delete from transactions where id=-343001;
set local role authenticated;
do $$declare c jsonb;begin c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>-300000 then raise exception 'deleted settled profit lost';end if;end $$;
reset role;
-- Pending request cannot be paid after its source changes.
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,created_by,cashbox_user_id) values(-343003,'sale',2000000,2000000,700000,true,false,'00000000-0000-0000-0000-000000003431','00000000-0000-0000-0000-000000003431');
set local role authenticated;
do $$declare c jsonb;r jsonb;begin c:=public.solar_profit_workspace('overview');r:=public.solar_profit_workspace('request','00000000-0000-0000-0000-000000003439',jsonb_build_object('expectedToken',c->>'token'));end $$;
reset role;
update transactions set profit=650000 where id=-343003;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003430',true);
do $$declare c jsonb;r jsonb;begin
 c:=public.solar_profit_workspace('overview');select x into r from jsonb_array_elements(c->'requests')x where x->>'id'='00000000-0000-0000-0000-000000003439';
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',r->>'token','share',100000,'cashOwnerId','00000000-0000-0000-0000-000000003430','collectionConfirmed',true));raise exception 'stale approval allowed';exception when serialization_failure or sqlstate 'PT409' then null;end;
 perform public.solar_profit_workspace('reject',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',r->>'token','note','تغيرت الكلفة؛ إصدار طلب جديد'));
end $$;
reset role;
do $$begin
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003430')<>925000 then raise exception 'failed approval changed cash';end if;
 if(select count(*) from transactions where profit_settlement_id is not null)<>1 then raise exception 'failed approval expense';end if;
 raise notice 'PASS own-only profits, credit sales, periods, request/review permissions, exact retry, single expense/payout, cash guard, historical snapshot, correction/deletion, stale approval and rejection';
end $$;
-- New transactions after submission must not invalidate or be closed by it.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003431',true);
do $$declare c jsonb;begin c:=public.solar_profit_workspace('overview');perform public.solar_profit_workspace('request','00000000-0000-0000-0000-000000003440',jsonb_build_object('expectedToken',c->>'token'));end $$;
reset role;
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,created_by,cashbox_user_id) values(-343004,'sale',500000,500000,100000,true,false,'00000000-0000-0000-0000-000000003431','00000000-0000-0000-0000-000000003431');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003430',true);
do $$declare c jsonb;r jsonb;begin
 c:=public.solar_profit_workspace('overview');select x into r from jsonb_array_elements(c->'requests')x where x->>'id'='00000000-0000-0000-0000-000000003440';
 perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',r->>'token','share',50000,'cashOwnerId','00000000-0000-0000-0000-000000003430','collectionConfirmed',true));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003431',true);
 if(public.solar_profit_workspace('overview')->>'available')::numeric<>100000 then raise exception 'new business accidentally closed';end if;
end $$;
reset role;
do $$begin
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003430')<>875000 then raise exception 'new business payout cash';end if;
 if has_table_privilege('authenticated','solar_private.profit_settlements','select') or has_table_privilege('authenticated','solar_private.profit_checkpoints','update') then raise exception 'audit table exposed';end if;
 raise notice 'PASS period filters, new business after request stays open, private audit access denied';
end $$;
rollback;
