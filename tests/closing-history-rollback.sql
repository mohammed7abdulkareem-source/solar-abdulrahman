-- Run against the Solar test/production schema in a rollback-only transaction.
-- Existing user identities are looked up; no passwords or permanent fixtures.
begin;
select set_config('solar_test.engineer',(select id::text from public.profiles where active and user_type='installer' order by created_at limit 1),true);
select set_config('solar_test.admin',(select id::text from public.profiles where active and is_admin and user_type<>'installer' limit 1),true);
select set_config('solar_test.staff',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
select set_config('solar_test.other',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' and id<>current_setting('solar_test.staff')::uuid order by created_at limit 1),true);
update public.profiles set permissions=permissions||'{"installations":true,"installationsAll":false}'::jsonb where id=current_setting('solar_test.staff')::uuid;
insert into public.transactions(id,kind,cash,total,cost,created_by,cashbox_user_id,installer_id,installation_status)
values
(-910001,'cash_income',true,500,0,current_setting('solar_test.admin')::uuid,current_setting('solar_test.staff')::uuid,null,'none'),
(-910002,'cash_income',true,900,0,current_setting('solar_test.other')::uuid,current_setting('solar_test.other')::uuid,null,'none'),
(-910003,'system',false,300,100,current_setting('solar_test.staff')::uuid,current_setting('solar_test.staff')::uuid,current_setting('solar_test.engineer')::uuid,'pending'),
(-910004,'system',false,800,400,current_setting('solar_test.other')::uuid,current_setting('solar_test.other')::uuid,null,'pending');
insert into public.transaction_items(id,transaction_id,product_name,qty,price,cost) values(-910001,-910003,'TEST MODULE',2,150,50),(-910002,-910004,'OTHER MODULE',1,800,400);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('solar_test.engineer'),true);
do $$ declare jobs jsonb; begin
 if exists(select 1 from public.transactions) or exists(select 1 from public.products) or exists(select 1 from public.transaction_items) or exists(select 1 from public.cash_ledger) then raise exception 'FAIL engineer financial access'; end if;
 jobs:=public.solar_installation_jobs();
 if not exists(select 1 from jsonb_array_elements(jobs) j where (j->>'id')::bigint=-910003) then raise exception 'FAIL missing assigned job'; end if;
 if exists(select 1 from jsonb_array_elements(jobs) j where (j->>'id')::bigint=-910004 or j ?| array['total','cost','expenses','profit','cash','cashboxUserId','installationExpenses']) then raise exception 'FAIL leaked job finance'; end if;
 if exists(select 1 from jsonb_array_elements(jobs) j,jsonb_array_elements(j->'items') i where i ?| array['price','cost','landedCost']) then raise exception 'FAIL leaked item prices'; end if;
 begin perform public.solar_installation_action(-910004,0,'start');raise exception 'FAIL unassigned job started';exception when insufficient_privilege then null;end;
 perform public.solar_installation_action(-910003,0,'start');
 begin perform public.solar_installation_action(-910003,0,'start');raise exception 'FAIL stale revision accepted';exception when serialization_failure then null;end;
 begin perform public.solar_installation_action(-910003,1,'complete','{"notes":"test","checks":{},"expenses":[]}');raise exception 'FAIL unchecked completion';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform public.solar_installation_action(-910003,1,'complete','{"notes":"Test commissioning complete","checks":{"materials":true,"tested":true,"handover":true},"expenses":[{"description":"transport","amount":20}]}');
 begin perform public.solar_installation_action(-910003,2,'close','{"amount":20}');raise exception 'FAIL engineer closed finances';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('solar_test.staff'),true);
do $$ begin
 if (select count(*) from public.transactions where id between -910004 and -910001)<>2 then raise exception 'FAIL staff row scope';end if;
 if (select sum(total) from public.transactions where cash and id between -910004 and -910001)<>500 then raise exception 'FAIL assigned cash not included';end if;
 if (select count(*) from public.transaction_items where id in (-910001,-910002))<>1 then raise exception 'FAIL item isolation';end if;
 begin insert into public.transactions(id,kind,created_by,cashbox_user_id) values(-910005,'cash_income',auth.uid(),current_setting('solar_test.other')::uuid);raise exception 'FAIL spoofed cashbox';exception when insufficient_privilege then null;end;
 begin update public.transactions set installation_status='closed' where id=-910003;raise exception 'FAIL generic stage bypass';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 perform public.solar_installation_action(-910003,2,'close','{"amount":20}');
 if (select profit from public.transactions where id=-910003)<>180 then raise exception 'FAIL final profit';end if;
 begin perform public.solar_installation_action(-910004,0,'close','{"amount":0}');raise exception 'FAIL other staff file mutation';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('solar_test.other'),true);
do $$ begin
 if exists(select 1 from public.transactions where id=-910001) then raise exception 'FAIL other staff cash readable';end if;
 if exists(select 1 from jsonb_array_elements(public.solar_installation_jobs()) j where (j->>'id')::bigint=-910003) then raise exception 'FAIL other staff report readable';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('solar_test.admin'),true);
do $$ begin
 if (select count(*) from public.transactions where id between -910004 and -910001)<>4 then raise exception 'FAIL admin access';end if;
 perform public.solar_installation_action(-910003,3,'reopen');
 perform public.solar_installation_action(-910003,4,'close','{"amount":40,"notes":"approved extra transport"}');
 if (select profit from public.transactions where id=-910003)<>160 then raise exception 'FAIL expenses double counted on reopen';end if;
end $$;
reset role;

-- Temporary permission modes and fixtures are all rolled back.
update public.profiles set permissions='{"installations":false,"installationsAll":false,"salesHistory":true}' where id=current_setting('solar_test.staff')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('solar_test.staff'),true);
do $$ declare h jsonb; begin
 begin perform public.solar_installation_action(-910003,5,'reopen');raise exception 'FAIL no-scope close allowed';exception when insufficient_privilege then null;end;
 h:=public.solar_sales_history(search_text=>'-91000');
 if jsonb_array_length(h->'rows')<>1 then raise exception 'FAIL own history scope: %',h;end if;
end $$;
reset role;
update public.profiles set permissions='{"installationsAll":true}' where id=current_setting('solar_test.staff')::uuid;
update public.transactions set installation_status='completed',installation_report='{"expenseTotal":50}' where id=-910004;
set local role authenticated;
do $$ declare h jsonb; j jsonb; begin
 j:=public.solar_installation_jobs();
 if not exists(select 1 from jsonb_array_elements(j) x where (x->>'id')::bigint=-910004 and x->>'canManage'='true') then raise exception 'FAIL all closer missing job';end if;
 -- Changes approved expenses without requiring a note; zero is valid.
 perform public.solar_installation_action(-910004,0,'close','{"amount":0,"notes":""}');
 perform public.solar_installation_action(-910004,1,'reopen');
 perform public.solar_installation_action(-910004,2,'close','{"amount":150,"notes":""}');
 h:=public.solar_sales_history(search_text=>'-91000');
 if jsonb_array_length(h->'rows')<>2 then raise exception 'FAIL all closer history: %',h;end if;
 if exists(select 1 from public.transactions where id=-910002) then raise exception 'FAIL cross-user cash leaked';end if;
 if exists(select 1 from public.transactions where id=-910004) then raise exception 'FAIL table scope widened';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('solar_test.engineer'),true);
do $$ begin
 begin perform public.solar_sales_history();raise exception 'FAIL engineer history allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if (select profit from public.transactions where id=-910004)<>250 then raise exception 'FAIL cross-owner final profit';end if;
 if has_function_privilege('anon','public.solar_sales_history(text,text,date,date,text,integer)','execute') then raise exception 'FAIL anonymous history access';end if;
end $$;

select 'PASS: scoped closing, no notes, zero expenses, sales history, engineer redaction, assigned jobs, staff cash ownership, cross-user denial, state sequence, stale revision, report checks, close/reopen profit' as verification;
rollback;
