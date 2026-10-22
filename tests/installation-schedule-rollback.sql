\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003660','إدارة التنصيب',true,'admin_staff','07700003660','{}'),
('00000000-0000-0000-0000-000000003661','مسؤول الفاتورة الأول',false,'admin_staff','07700003661','{"system":true,"installations":true}'),
('00000000-0000-0000-0000-000000003662','مسؤول الفاتورة الثاني',false,'admin_staff','07700003662','{"system":true,"installations":true}'),
('00000000-0000-0000-0000-000000003663','المهندس الأول',false,'installer','07700003663','{}'),
('00000000-0000-0000-0000-000000003664','المهندس الثاني',false,'installer','07700003664','{}'),
('00000000-0000-0000-0000-000000003665','مخزن علم قديم',true,'warehouse','07700003665','{}'),
('00000000-0000-0000-0000-000000003666','بلا صلاحية',false,'admin_staff','07700003666','{}');
insert into products(id,code,name,qty,cost) values(-366001,'SCHEDULE','لوح حجز',100,100);
insert into customers(id,name,customer_type,owner_id) values(-366001,'عميل الموعد السري','system','00000000-0000-0000-0000-000000003661');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003661',true);
select set_config('test.payload','{"kind":"system","mode":"credit","partyId":-366001,"party":"عميل الموعد السري","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003663","customerAddress":"عنوان التنصيب","total":10000,"installDate":"2026-10-26","installTime":"10:00","items":[{"id":-366001,"qty":1,"price":0}]}',true);
select set_config('test.job',public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb)->>'id',true);
reset role;
select set_config('test.stock',(select qty::text from products where id=-366001),true);
select set_config('test.books',(select count(*)::text from transactions),true);
set local role authenticated;
do $$declare r jsonb;t text;begin
 foreach t in array array['04:01','09:00','10:00','15:59'] loop
  begin perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||jsonb_build_object('installTime',t));raise exception 'FAIL overlap %',t;exception when sqlstate 'PT409' then null;end;
 end loop;
 foreach t in array array['04:00','16:00'] loop
  perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||jsonb_build_object('installTime',t));
 end loop;
 perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||'{"installerId":"00000000-0000-0000-0000-000000003664"}');
 begin perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||'{"installDate":"2026-10-27","installTime":""}');raise exception 'FAIL missing time';exception when invalid_parameter_value or raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 r:=public.solar_installation_schedule('2026-10-26','2026-10-26','00000000-0000-0000-0000-000000003663',current_setting('test.job')::bigint);
 if jsonb_array_length(r->'slots')<>2 or r::text like '%"id": '||current_setting('test.job')||',%' then raise exception 'FAIL exclusion';end if;
 perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||'{"installDate":"2026-10-28","installTime":"22:00"}');
 begin perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||'{"installDate":"2026-10-29","installTime":"03:59"}');raise exception 'FAIL midnight overlap';exception when sqlstate 'PT409' then null;end;
 perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb||'{"installDate":"2026-10-29","installTime":"04:00"}');
end$$;
do $$declare r jsonb;t public.transactions;candidate jsonb;begin
 begin
  candidate:=current_setting('test.payload')::jsonb||'{"installDate":"2026-11-10"}';
  r:=public.solar_invoice_save(gen_random_uuid(),candidate);
  select * into t from transactions where id=(r->>'id')::bigint;
  candidate:=candidate||jsonb_build_object('invoiceId',t.id,'expectedRevision',t.pricing_revision,'expectedInstallationRevision',t.installation_revision,'expenses',0,'installDate','2026-11-11');
  perform public.solar_invoice_save(gen_random_uuid(),candidate);
  if jsonb_array_length(public.solar_installation_schedule('2026-11-10','2026-11-10')->'slots')<>0 or jsonb_array_length(public.solar_installation_schedule('2026-11-11','2026-11-11')->'slots')<>1 then raise exception 'FAIL reschedule failed to release old slot';end if;
  raise exception 'ROLLBACK RESCHEDULE CHECK';
 exception when raise_exception then if sqlerrm<>'ROLLBACK RESCHEDULE CHECK' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003662',true);
do $$declare r jsonb;begin
 r:=public.solar_installation_schedule('2026-10-26','2026-10-26');
 if jsonb_array_length(r->'slots')<>4 then raise exception 'FAIL shared calendar';end if;
 if exists(select 1 from jsonb_array_elements(r->'slots') x where x ?|array['id','receiptNo','party','creatorName','status'] or(x->>'own')::boolean) then raise exception 'FAIL shared calendar privacy %',r;end if;
 if exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) x where(x->>'id')::bigint=current_setting('test.job')::bigint) then raise exception 'FAIL other user full job leak';end if;
 begin perform public.solar_installation_schedule('2026-10-26','2026-10-26',null,current_setting('test.job')::bigint);raise exception 'FAIL other-user exclusion';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003663',true);
do $$declare r jsonb;j jsonb;begin
 r:=public.solar_installation_schedule('2026-10-26','2026-10-26');
 if jsonb_array_length(r->'engineers')<>1 or jsonb_array_length(r->'slots')<>3 then raise exception 'FAIL engineer resources scope';end if;
 select x into j from jsonb_array_elements(public.solar_installation_jobs()) x where(x->>'id')::bigint=current_setting('test.job')::bigint;
 if j->>'creatorName'<>'مسؤول الفاتورة الأول' or j->>'creatorPhone'<>'07700003661' or j ?|array['cost','total','profit','expenses','installationExpenses'] then raise exception 'FAIL engineer author/financial scope %',j;end if;
 begin perform public.solar_installation_schedule('2026-10-26','2026-10-26','00000000-0000-0000-0000-000000003664');raise exception 'FAIL other engineer schedule';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin
 if(select qty from products where id=-366001)<>current_setting('test.stock')::numeric-5 or(select count(*) from transactions)<>current_setting('test.books')::int+5 then raise exception 'FAIL rejected booking changed stock/books';end if;
end$$;
update transactions set warehouse_status='ready',warehouse_prepared_at=now() where id=current_setting('test.job')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003661',true);
-- Owner is allowed to close from pending; engineer and office must see one state.
select public.solar_installation_action(current_setting('test.job')::bigint,0,'close','{"amount":0}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003663',true);
do $$declare j jsonb;begin
 select x into j from jsonb_array_elements(public.solar_installation_jobs()) x where(x->>'id')::bigint=current_setting('test.job')::bigint;
 if j->>'installationStatus'<>'closed' or(j->>'installationRevision')::int<>1 or j->>'installationClosedAt' is null then raise exception 'FAIL engineer stale closure';end if;
 begin perform public.solar_installation_action(current_setting('test.job')::bigint,0,'start');raise exception 'FAIL stale engineer stage';exception when sqlstate 'PT409' then null;end;
end$$;
reset role;
do $$begin
 if(select count(*) from solar_notifications where user_id='00000000-0000-0000-0000-000000003663' and job_id=current_setting('test.job')::bigint and event='installation_updated')<>1 then raise exception 'FAIL engineer closure notification';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003661',true);
do $$begin
 begin perform public.solar_invoice_save(gen_random_uuid(),current_setting('test.payload')::jsonb);raise exception 'FAIL closed appointment released too early';exception when sqlstate 'PT409' then null;end;
 perform public.solar_installation_action(current_setting('test.job')::bigint,1,'reopen');
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003663',true);
do $$declare j jsonb;begin
 select x into j from jsonb_array_elements(public.solar_installation_jobs()) x where(x->>'id')::bigint=current_setting('test.job')::bigint;
 if j->>'installationStatus'<>'completed' or(j->>'installationRevision')::int<>2 then raise exception 'FAIL reopened engineer state';end if;
end$$;
reset role;
-- Live permission changes and specialized roles override stale admin flags.
update profiles set is_admin=true where id='00000000-0000-0000-0000-000000003663';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003663',true);
do $$begin if jsonb_array_length(public.solar_installation_schedule('2026-10-26','2026-10-26')->'engineers')<>1 then raise exception 'FAIL installer stale admin';end if;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003665',true);
do $$begin begin perform public.solar_installation_schedule('2026-10-26','2026-10-26');raise exception 'FAIL warehouse schedule';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003666',true);
do $$begin begin perform public.solar_installation_schedule('2026-10-26','2026-10-26');raise exception 'FAIL permissionless schedule';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_installation_schedule(date,date,uuid,bigint)','EXECUTE') or has_function_privilege('authenticated','solar_private.installation_booking_guard()','EXECUTE') or has_function_privilege('authenticated','solar_private.installation_update_notice(uuid,public.transactions)','EXECUTE') then raise exception 'FAIL helper grant';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003660',true);
do $$declare r jsonb;req uuid:=gen_random_uuid();begin
 r:=public.solar_admin_announcement('preview','installers','تنبيه مهندسين','موعد اجتماع التنصيب');
 if (r->>'recipients')::int<>2 then raise exception 'FAIL announcement preview';end if;
 if exists(select 1 from solar_notifications where event='admin_message') then raise exception 'FAIL preview sent';end if;
 r:=public.solar_admin_announcement('send','installers','تنبيه مهندسين','موعد اجتماع التنصيب',req);
 if public.solar_admin_announcement('send','installers','تنبيه مهندسين','موعد اجتماع التنصيب',req)<>r then raise exception 'FAIL announcement retry response';end if;
 begin perform public.solar_admin_announcement('send','all','تنبيه مهندسين','رسالة مختلفة',req);raise exception 'FAIL changed retry accepted';exception when sqlstate 'PT409' then null;end;
 if (public.solar_admin_announcement('preview','staff','اجتماع','موعد الاجتماع')->>'recipients')::int<>4 then raise exception 'FAIL staff grouping';end if;
 if (public.solar_admin_announcement('preview','warehouse','اجتماع','موعد الاجتماع')->>'recipients')::int<>1 then raise exception 'FAIL warehouse grouping';end if;
 if (public.solar_admin_announcement('preview','all','اجتماع','موعد الاجتماع')->>'recipients')::int<>7 then raise exception 'FAIL all grouping';end if;
end$$;
reset role;
do $$begin if(select count(*) from solar_notifications where event='admin_message')<>2 or exists(select 1 from solar_notifications n join profiles p on p.id=n.user_id where event='admin_message' and p.user_type<>'installer') then raise exception 'FAIL announcement duplicate or wrong group';end if;end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003663',true);
do $$begin begin perform public.solar_admin_announcement('send','all','غير مسموح','غير مسموح',gen_random_uuid());raise exception 'FAIL installer stale admin broadcast';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003665',true);
do $$begin begin perform public.solar_admin_announcement('preview','all','غير مسموح','غير مسموح');raise exception 'FAIL warehouse stale admin broadcast';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003662',true);
do $$begin begin perform public.solar_admin_announcement('send','all','غير مسموح','غير مسموح',gen_random_uuid());raise exception 'FAIL staff broadcast';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
\echo PASS six-hour shared calendar, boundaries, midnight, canonical closure/reopen, creator contact, scoped privacy, stale revision, notifications, atomic stock and role guards
rollback;
