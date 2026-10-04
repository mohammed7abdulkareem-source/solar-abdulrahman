-- Run only as a single transaction. All deletions and backups are rolled back.
begin;
do $$begin
 perform set_config('reset_test.admin',(select id::text from public.profiles where active and is_admin and user_type not in ('installer','warehouse') order by created_at limit 1),true);
 perform set_config('reset_test.before',md5(solar_private.reset_snapshot()::text),true);
 perform set_config('reset_test.profiles',(select md5(jsonb_agg(to_jsonb(p) order by id)::text) from public.profiles p),true);
 if current_setting('reset_test.admin')='' then raise exception 'No existing administrator';end if;
end $$;
set local role authenticated;
do $$declare p jsonb;begin
 perform set_config('request.jwt.claim.sub',current_setting('reset_test.admin'),true);
 p=public.solar_prepare_reset();
 perform set_config('reset_test.plan',p->>'requestId',true);
 if public.solar_reset_backup((p->>'requestId')::uuid)->'data'->>'format'<>'solar-reset-v1' then raise exception 'FAIL backup export';end if;
 begin perform public.solar_execute_reset(auth.uid(),(p->>'requestId')::uuid,'تصفير بيانات عبدالرحمن سولار');raise exception 'FAIL client may bypass password gate';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Ensure the fingerprint blocks deleting changes made after the reviewed backup.
insert into public.solar_quotes(id,user_id,payload) values(gen_random_uuid(),current_setting('reset_test.admin')::uuid,'{"resetTest":true}');
set local role service_role;
do $$begin
 begin perform public.solar_execute_reset(current_setting('reset_test.admin')::uuid,current_setting('reset_test.plan')::uuid,'wrong');raise exception 'FAIL invalid confirmation';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_execute_reset(current_setting('reset_test.admin')::uuid,current_setting('reset_test.plan')::uuid,'تصفير بيانات عبدالرحمن سولار');raise exception 'FAIL stale backup accepted';exception when serialization_failure then null;end;
end $$;
reset role;
set local role authenticated;
do $$declare p jsonb;begin p=public.solar_prepare_reset();perform set_config('reset_test.plan',p->>'requestId',true);end $$;
reset role;
set local role service_role;
do $$declare result jsonb;begin
 result=public.solar_execute_reset(current_setting('reset_test.admin')::uuid,current_setting('reset_test.plan')::uuid,'تصفير بيانات عبدالرحمن سولار');
 if result->>'ok'<>'true' then raise exception 'FAIL reset result';end if;
 begin perform public.solar_execute_reset(current_setting('reset_test.admin')::uuid,current_setting('reset_test.plan')::uuid,'تصفير بيانات عبدالرحمن سولار');raise exception 'FAIL replay accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
reset role;
do $$begin
 if exists(select 1 from jsonb_each(solar_private.reset_snapshot()) where jsonb_array_length(value)<>0) then raise exception 'FAIL business rows remain';end if;
 if (select md5(jsonb_agg(to_jsonb(p) order by id)::text) from public.profiles p)<>current_setting('reset_test.profiles') then raise exception 'FAIL user accounts changed';end if;
 if not exists(select 1 from solar_private.reset_requests where id=current_setting('reset_test.plan')::uuid and consumed_at is not null) then raise exception 'FAIL reset audit missing';end if;
end $$;
-- The owner being demoted or deactivated revokes access to the reset feature.
update public.profiles set is_admin=false where id=current_setting('reset_test.admin')::uuid;
set local role authenticated;
do $$begin
 begin perform public.solar_prepare_reset();raise exception 'FAIL nonadmin prepare';exception when insufficient_privilege then null;end;
 begin perform public.solar_reset_backup(current_setting('reset_test.plan')::uuid);raise exception 'FAIL nonadmin backup';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: backup, password-gated permissions, fingerprint drift, wipe, account preservation, replay and nonadmin denial; all changes rolled back' as result;
rollback;
