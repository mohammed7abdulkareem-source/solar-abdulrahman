-- Permission and persistence checks: all fixtures and profile edits roll back.
begin;
do $$declare actor uuid; other_actor uuid; begin
 select id into actor from public.profiles where active and user_type='admin_staff' and not is_admin order by created_at limit 1;
 select id into other_actor from public.profiles where active and id<>actor order by created_at limit 1;
 if actor is null or other_actor is null then raise exception 'Need two existing profiles for the rollback test'; end if;
 perform set_config('quote_test.actor',actor::text,true);
 perform set_config('quote_test.other',other_actor::text,true);
 perform set_config('quote_test.id',gen_random_uuid()::text,true);
 perform set_config('quote_test.other_id',gen_random_uuid()::text,true);
 update public.profiles set permissions=coalesce(permissions,'{}')||'{"tahseel":true}' where id=actor;
 insert into public.solar_quotes(id,user_id,payload) values(current_setting('quote_test.other_id')::uuid,other_actor,'{"private":"other"}');
end $$;
set local role authenticated;
do $$declare n integer; begin
 perform set_config('request.jwt.claim.sub',current_setting('quote_test.actor'),true);
 insert into public.solar_quotes(id,user_id,payload) values(current_setting('quote_test.id')::uuid,auth.uid(),'{"schema":1,"customer":"ROLLBACK QUOTE"}');
 if not exists(select 1 from public.solar_quotes where id=current_setting('quote_test.id')::uuid) then raise exception 'FAIL own saved quote unreadable'; end if;
 if exists(select 1 from public.solar_quotes where id=current_setting('quote_test.other_id')::uuid) then raise exception 'FAIL other quote readable'; end if;
 begin
  insert into public.solar_quotes(id,user_id,payload) values(gen_random_uuid(),current_setting('quote_test.other')::uuid,'{}');
  raise exception 'FAIL other user insert allowed';
 exception when insufficient_privilege then null;end;
 begin
  update public.solar_quotes set user_id=current_setting('quote_test.other')::uuid where id=current_setting('quote_test.id')::uuid;
  raise exception 'FAIL ownership reassignment allowed';
 exception when insufficient_privilege then null;end;
 update public.solar_quotes set payload='{"customer":"UPDATED"}',revision=2 where id=current_setting('quote_test.id')::uuid and revision=1;
 get diagnostics n=row_count;if n<>1 then raise exception 'FAIL own update';end if;
 update public.solar_quotes set revision=3 where id=current_setting('quote_test.id')::uuid and revision=1;
 get diagnostics n=row_count;if n<>0 then raise exception 'FAIL stale revision overwritten';end if;
 delete from public.solar_quotes where id=current_setting('quote_test.other_id')::uuid;
 get diagnostics n=row_count;if n<>0 then raise exception 'FAIL other quote deleted';end if;
end $$;
reset role;
update public.profiles set permissions=permissions||'{"tahseel":false,"system":true}' where id=current_setting('quote_test.actor')::uuid;
set local role authenticated;
do $$begin
 if exists(select 1 from public.solar_quotes) then raise exception 'FAIL explicit permission denial ignored';end if;
 begin
  insert into public.solar_quotes(id,user_id,payload) values(gen_random_uuid(),auth.uid(),'{}');
  raise exception 'FAIL denied user insert';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set user_type='warehouse',permissions='{"tahseel":true}' where id=current_setting('quote_test.actor')::uuid;
set local role authenticated;
do $$begin if exists(select 1 from public.solar_quotes) then raise exception 'FAIL warehouse leak';end if;end $$;
reset role;
update public.profiles set user_type='installer',permissions='{"tahseel":true}' where id=current_setting('quote_test.actor')::uuid;
set local role authenticated;
do $$begin if exists(select 1 from public.solar_quotes) then raise exception 'FAIL installer leak';end if;end $$;
reset role;
update public.profiles set user_type='admin_staff',active=false,permissions='{"tahseel":true}' where id=current_setting('quote_test.actor')::uuid;
set local role authenticated;
do $$begin if exists(select 1 from public.solar_quotes) then raise exception 'FAIL inactive leak';end if;end $$;
reset role;
update public.profiles set active=true where id=current_setting('quote_test.actor')::uuid;
set local role authenticated;
do $$declare n integer;begin
 delete from public.solar_quotes where id=current_setting('quote_test.id')::uuid and revision=2;
 get diagnostics n=row_count;if n<>1 then raise exception 'FAIL own delete';end if;
end $$;
reset role;
set local role anon;
do $$begin
 begin perform 1 from public.solar_quotes;raise exception 'FAIL anonymous read';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: quote CRUD, ownership, revision conflict, explicit permission, blocked roles, inactive and anonymous access' as result;
rollback;
