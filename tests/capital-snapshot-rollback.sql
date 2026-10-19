\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003530','Capital Admin','capital_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003531','Capital Staff','capital_staff',false,'admin_staff','{"capital":true}'),
('00000000-0000-0000-0000-000000003532','Denied Staff','capital_denied',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003533','Warehouse','capital_warehouse',true,'warehouse','{"capital":true}');
insert into products(id,code,name,qty,cost) values(-353001,'CAPITAL','مخزون الكلفة',8906542,100);
insert into customers(id,name,customer_type,owner_id) values(-353001,'عميل الرصيد القديم','wholesale','00000000-0000-0000-0000-000000003530'),(-353002,'عميل السلفة','wholesale','00000000-0000-0000-0000-000000003531');
insert into suppliers(id,name) values(-353001,'ABDULRAHMAN CAPITAL'),(-353002,'مورد سلفة');
insert into transactions(id,kind,party_type,party_id,party_name,payment_mode,total,cash,created_by,notes) values
(-353001,'customer_payment','customer',-353001,'عميل الرصيد القديم','opening_balance',-156843000,false,'00000000-0000-0000-0000-000000003530','رصيد العملاء القديم'),
(-353002,'sale','customer',-353001,'عميل الرصيد القديم','credit',113025000,false,'00000000-0000-0000-0000-000000003530','صافي الحركات اللاحقة'),
(-353003,'supplier_payment','supplier',-353001,'ABDULRAHMAN CAPITAL','charge_old_balance',-188194000,false,'00000000-0000-0000-0000-000000003530','حساب الديون سابق'),
(-353004,'purchase','supplier',-353001,'ABDULRAHMAN CAPITAL','credit',1044049006.66,false,'00000000-0000-0000-0000-000000003530','شراء مستقل'),
(-353005,'cash_income',null,null,null,'cash',48089000,true,'00000000-0000-0000-0000-000000003530','رصيد نقدي');
create temporary table financial_before as select md5(solar_private.reset_snapshot()::text) fingerprint;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003530',true);
set local role authenticated;
do $$declare s jsonb;a jsonb;begin
 s:=public.solar_capital_snapshot();
 if(s->>'net')::numeric<>-23631806.66 or(s->>'assets')::numeric<>1208611200 or(s->>'liabilities')::numeric<>1232243006.66 then raise exception 'known capital mismatch %',s;end if;
 if(s->'opening'->>'net')::numeric<>-31351000 or(s->>'otherMovements')::numeric<>7719193.34 then raise exception 'opening bridge mismatch';end if;
 if(s->'opening'->>'supplierNet')::numeric<>188194000 then raise exception 'confirmed independent old debt lost';end if;
 a:=public.solar_fx('account',null,'{"supplierId":-353001}');
 perform public.solar_fx('currency',gen_random_uuid(),jsonb_build_object('supplierId',-353001,'currency','USD','rate',1660,'expectedRevision',a->'revision','expectedToken',a->>'token','note','اتفاق حساب الدولار'));
 if public.solar_capital_snapshot()->>'net' is distinct from s->>'net' then raise exception 'currency conversion double counted or revalued capital';end if;
 begin
  perform public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-353099,"supplierId":-353001,"amount":188194000,"currency":"IQD","rate":1660,"accountRevision":1,"mode":"charge_old_balance","note":"حساب الديون سابق"}');
  raise exception 'duplicate supplier old debt accepted through financial RPC';exception when sqlstate 'PT409' then null;
 end;
end$$;
reset role;
-- Snapshot itself is read-only (currency conversion is a separate authorized test action).
create temporary table read_before as select md5(solar_private.reset_snapshot()::text) fingerprint;
do $$begin perform public.solar_capital_snapshot();end$$;
do $$begin if md5(solar_private.reset_snapshot()::text)<>(select fingerprint from read_before) then raise exception 'snapshot mutated ledger';end if;end$$;
-- Opposite balances belong to different parties: retain both gross sides.
select set_config('request.jwt.claim.sub','',true);
insert into transactions(id,kind,party_type,party_id,party_name,payment_mode,total,cash,created_by,notes) values
(-353006,'customer_payment','customer',-353002,'عميل السلفة','charge_other',50,false,'00000000-0000-0000-0000-000000003531','سلفة عميل'),
(-353007,'supplier_payment','supplier',-353002,'مورد سلفة','charge_other',70,false,'00000000-0000-0000-0000-000000003531','دفعة لدى المورد');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003530',true);
set local role authenticated;
do $$declare s jsonb;before_net numeric;ctx jsonb;payload jsonb;req uuid:=gen_random_uuid();r jsonb;begin
 s:=public.solar_capital_snapshot();
 if(s->'customers'->>'receivable')::numeric<>269868000 or(s->'customers'->>'advances')::numeric<>50
  or(s->'suppliers'->>'payable')::numeric<>1232243006.66 or(s->'suppliers'->>'prepayments')::numeric<>70
  or(s->>'net')::numeric<>-23631786.66 then raise exception 'gross advances hidden %',s;end if;
 before_net:=(s->>'net')::numeric;
 -- USD book cost is fixed; another deposit at a different rate must not revalue it.
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003530","mode":"capital_deposit","currency":"USD","amount":100,"rate":1660,"note":"رأس مال دولار"}');
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003530","mode":"capital_deposit","currency":"USD","amount":1,"rate":1700,"note":"دولار بصرف مختلف"}');
 s:=public.solar_capital_snapshot();
 if(s->'cash'->>'usd')::numeric<>101 or(s->'cash'->>'usdBook')::numeric<>167700 or(s->>'net')::numeric<>before_net+167700
  or(s->>'capitalFlows')::numeric<>167700 then raise exception 'USD book cost/flow mismatch %',s;end if;
 before_net:=(s->>'net')::numeric;
 payload:='{"paymentId":-353008,"supplierId":-353001,"amount":10000,"currency":"IQD","rate":1660,"accountRevision":1,"mode":"cash","note":"تسديد قابل للإلغاء"}';
 perform public.solar_fx('payment',req,payload);perform public.solar_fx('payment',req,payload);
 ctx:=public.solar_supplier_payment_manage('get',null,'{"id":-353008}');
 perform public.solar_supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',-353008,'expectedToken',ctx->>'token','note','إلغاء اختباري'));
 if(public.solar_capital_snapshot()->>'net')::numeric<>before_net then raise exception 'void/refund changed original net';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003531',true);
do $$declare s jsonb;begin
 s:=public.solar_capital_snapshot();if s->>'scope'<>'own' or(s->'customers'->>'receivable')::numeric<>0 or(s->'customers'->>'advances')::numeric<>50
  or(s->'suppliers'->>'prepayments')::numeric<>70 or jsonb_array_length(s->'opening'->'rows')<>0 or(s->'cash'->>'iqd')::numeric<>0 then raise exception 'foreign financial data leaked %',s;end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003532',true);
do $$begin begin perform public.solar_capital_snapshot();raise exception 'missing permission bypass';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003533',true);
do $$begin begin perform public.solar_capital_snapshot();raise exception 'warehouse stale admin bypass';exception when insufficient_privilege then null;end;end$$;
reset role;
update profiles set active=false where id='00000000-0000-0000-0000-000000003531';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003531',true);
do $$begin begin perform public.solar_capital_snapshot();raise exception 'inactive bypass';exception when insufficient_privilege then null;end;end$$;
reset role;
-- The new guard also covers definer RPC writes, not just direct authenticated DML.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003530',true);
do $$begin
 begin
  insert into transactions(id,kind,party_type,party_id,party_name,payment_mode,total,cash,created_by,notes)
  values(-353009,'customer_payment','customer',-353001,'عميل الرصيد القديم','opening_balance',-156843000,false,auth.uid(),'رصيد العملاء القديم');
  raise exception 'exact duplicate accepted';exception when sqlstate 'PT409' then null;
 end;
 insert into transactions(id,kind,party_type,party_id,party_name,payment_mode,total,cash,created_by,notes)
 values(-353010,'customer_payment','customer',-353001,'عميل الرصيد القديم','opening_balance',-156843000,false,auth.uid(),'دين مستقل موثق آخر');
 if not exists(select 1 from transactions where id=-353003 and total=-188194000) then raise exception 'independent supplier old debt changed';end if;
 if has_function_privilege('anon','public.solar_capital_snapshot()','execute') then raise exception 'anonymous snapshot access';end if;
 raise notice 'PASS known capital bridge, independent old debt, gross advances, current revision, USD book cost, capital flows, idempotent payment/void, own scope, inactive/warehouse/permission denial, duplicate old balance, read-only snapshot';
end$$;
rollback;
