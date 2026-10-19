\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003590','مدير الإيقاف',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003591','صاحب الفاتورة',false,'admin_staff','{"sale":true,"system":true,"purchase":true,"operationControl":true}'),
('00000000-0000-0000-0000-000000003592','مخزن بصلاحية قديمة',true,'warehouse','{}');
insert into products(id,code,name,qty,cost) values(-358200,'PAUSE','مادة الإيقاف',100,1000);
insert into customers(id,name,customer_type,owner_id) values(-358200,'زبون الإيقاف','wholesale','00000000-0000-0000-0000-000000003591');
set local role authenticated;
do $$declare s jsonb;p jsonb;r jsonb;idempotent uuid:=gen_random_uuid();decision uuid:=gen_random_uuid();n int;kind text;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003591',true);s:=public.solar_operation_status();
 begin perform public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','sale','paused',true,'expectedRevision',s->'revision'));raise exception 'staff changed global control';exception when insufficient_privilege then null;end;
 p:='{"kind":"sale","mode":"credit","party":"زبون الإيقاف","items":[{"id":-358200,"qty":1,"price":2000}]}';
 r:=public.solar_invoice_save(idempotent,p);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003590',true);
 s:=public.solar_operation_control(decision,jsonb_build_object('kind','sale','paused',true,'expectedRevision',s->'revision'));
 if public.solar_operation_control(decision,jsonb_build_object('kind','sale','paused',true,'expectedRevision',(s->>'revision')::bigint-1))<>s then raise exception 'control replay changed';end if;
 if not(s->>'sale')::boolean or(s->>'system')::boolean or(s->>'purchase')::boolean then raise exception 'independent switches failed';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'admin sale bypassed pause';exception when sqlstate 'PT423' then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003591',true);
 if public.solar_invoice_save(idempotent,p)<>r then raise exception 'already saved receipt could not be confirmed while paused';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'staff sale bypassed pause';exception when sqlstate 'PT423' then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('invoiceId',r->'id','expectedRevision',r->'pricingRevision'));raise exception 'edit bypassed pause';exception when sqlstate 'PT423' then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003592',true);
 begin perform public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','sale','paused',false,'expectedRevision',s->'revision'));raise exception 'warehouse stale admin bypassed control';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003590',true);
 s:=public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','sale','paused',false,'expectedRevision',s->'revision'));
 for kind in select unnest(array['system','purchase']) loop
  s:=public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind',kind,'paused',true,'expectedRevision',s->'revision'));
  begin perform public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('kind',kind));raise exception 'other operation bypassed pause';exception when sqlstate 'PT423' then null;end;
  s:=public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind',kind,'paused',false,'expectedRevision',s->'revision'));
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003591',true);perform public.solar_invoice_save(gen_random_uuid(),p);
 perform set_config('test.pause.invoice',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003590',true);
 s:=public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','sale','paused',true,'expectedRevision',s->'revision'));
end$$;
reset role;
do $$begin
 begin insert into transactions(id,kind,total,created_by) values(-358201,'sale',1,'00000000-0000-0000-0000-000000003591');raise exception 'legacy sale insert bypassed pause';exception when sqlstate 'PT423' then null;end;
 begin update transactions set total=2001 where id=current_setting('test.pause.invoice')::bigint;raise exception 'legacy financial update bypassed pause';exception when sqlstate 'PT423' then null;end;
 begin update transaction_items set qty=2 where transaction_id=current_setting('test.pause.invoice')::bigint;raise exception 'legacy items bypassed pause';exception when sqlstate 'PT423' then null;end;
 if(select count(*) from solar_notifications where event='operation_paused' and title='بيع الجملة متوقف مؤقتًا')<>(select count(*)*2 from profiles where active) then raise exception 'global notifications missing or duplicated';end if;
 if has_table_privilege('authenticated','solar_private.operation_controls','update') or has_function_privilege('anon','public.solar_operation_status()','EXECUTE') then raise exception 'pause privileges exposed';end if;
 raise notice 'PASS independent admin switches, global notifications exactly once, all-account server enforcement including existing forms, legacy writes, resume, permissions and safe invoice retry after pause';
end$$;
rollback;
