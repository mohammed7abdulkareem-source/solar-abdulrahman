\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003760','إدارة فحص الحفظ',true,'admin_staff','07701234567','{}'),
('00000000-0000-0000-0000-000000003761','مستخدم فحص الحفظ',false,'admin_staff','07701234567','{"system":true,"sale":true,"salesHistory":true,"salesDeleteOwn":true,"purchase":true}'),
('00000000-0000-0000-0000-000000003762','مستخدم آخر',false,'admin_staff','07701234567','{"system":true,"sale":true}'),
('00000000-0000-0000-0000-000000003763','مهندس فحص الحفظ',true,'installer','07701234567','{}'),
('00000000-0000-0000-0000-000000003764','مخزن فحص الحفظ',true,'warehouse','07701234567','{}');
insert into products(id,code,name,qty,cost)values(-376001,'ACK-001','مادة فحص تأكيد الحفظ',20,1000000);
insert into customers(id,name,customer_type,owner_id)values(-376001,'زبون فحص تأكيد الحفظ','system','00000000-0000-0000-0000-000000003761');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003761',true);
do $$declare p jsonb;r jsonb;status jsonb;old_nonce uuid:=gen_random_uuid();new_nonce uuid:=gen_random_uuid();fingerprint text;token text;begin
 p:='{"kind":"system","party":"زبون فحص تأكيد الحفظ","mode":"credit","total":4800000,"warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003763","customerAddress":"عنوان الفحص","items":[{"id":-376001,"qty":9,"price":0}]}';
 status:=public.solar_invoice_attempt_resolve(old_nonce,p);if status->>'state'<>'not_saved' then raise exception 'FAIL absent request status';end if;
 if public.solar_invoice_attempt_resolve(old_nonce,p)<>status then raise exception 'FAIL resolving absent twice';end if;
 if exists(select 1 from transactions where kind='system' and party_id=-376001) or(select qty from products where id=-376001)<>20 then raise exception 'FAIL resolution posted invoice';end if;
 begin perform public.solar_invoice_save(old_nonce,p);raise exception 'FAIL late original accepted';exception when sqlstate 'PT410' then null;end;
 r:=public.solar_invoice_save(new_nonce,p||'{"total":4900000}'::jsonb);
 if(select qty from products where id=-376001)<>11 then raise exception 'FAIL new draft stock once';end if;
 select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)) from transactions t),'items',(select jsonb_agg(to_jsonb(i)) from transaction_items i),'products',(select jsonb_agg(to_jsonb(x)) from products x))::text) into fingerprint;
 status:=public.solar_invoice_attempt_resolve(new_nonce,p||'{"total":4900000}'::jsonb);
 if status->>'state'<>'saved' or(status->'invoice'->>'id')::bigint<>(r->>'id')::bigint or(status->'invoice'->>'total')::numeric<>4900000 or status->'invoice'->>'receiptNo' is null then raise exception 'FAIL saved receipt confirmation';end if;
 if fingerprint<>(select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)) from transactions t),'items',(select jsonb_agg(to_jsonb(i)) from transaction_items i),'products',(select jsonb_agg(to_jsonb(x)) from products x))::text)) then raise exception 'FAIL confirmation changed business data';end if;
 if public.solar_invoice_save(new_nonce,p||'{"total":4900000}'::jsonb)<>r then raise exception 'FAIL exact original retry';end if;
 begin perform public.solar_invoice_save(old_nonce,p);raise exception 'FAIL cancelled nonce revived';exception when sqlstate 'PT410' then null;end;
 begin perform public.solar_invoice_attempt_resolve(new_nonce,p);raise exception 'FAIL incorrect original payload';exception when insufficient_privilege then null;end;
 perform set_config('test.attempt.old_nonce',old_nonce::text,true);perform set_config('test.attempt.new_nonce',new_nonce::text,true);perform set_config('test.attempt.payload',(p||'{"total":4900000}'::jsonb)::text,true);
 token:=public.solar_sale_delete_preview((r->>'id')::bigint)->>'token';perform public.solar_sale_delete((r->>'id')::bigint,token);
 status:=public.solar_invoice_attempt_resolve(new_nonce,p||'{"total":4900000}'::jsonb);if status->>'state'<>'deleted' then raise exception 'FAIL deleted original status';end if;
 begin perform public.solar_invoice_save(new_nonce,p||'{"total":4900000}'::jsonb);raise exception 'FAIL deleted original recreated';exception when sqlstate 'PT409' then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003762',true);
do $$begin
 begin perform public.solar_invoice_attempt_resolve(current_setting('test.attempt.new_nonce')::uuid,current_setting('test.attempt.payload')::jsonb);raise exception 'FAIL other user saved status';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_attempt_resolve(current_setting('test.attempt.old_nonce')::uuid,current_setting('test.attempt.payload')::jsonb);raise exception 'FAIL other user cancellation';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_attempt_resolve(null,'{}');raise exception 'FAIL invalid request';exception when invalid_parameter_value then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003763',true);
do $$begin begin perform public.solar_invoice_attempt_resolve(gen_random_uuid(),'{"kind":"system"}');raise exception 'FAIL engineer stale admin';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003764',true);
do $$begin begin perform public.solar_invoice_attempt_resolve(gen_random_uuid(),'{"kind":"system"}');raise exception 'FAIL warehouse stale admin';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_invoice_attempt_resolve(uuid,jsonb)','execute') or has_table_privilege('authenticated','solar_private.invoice_attempt_cancellations','insert') then raise exception 'FAIL recovery grants';end if;
 if(select count(*) from solar_private.invoice_attempt_cancellations)<>1 then raise exception 'FAIL cancellation metadata count';end if;
end$$;
set constraints all immediate;
\echo PASS uncertain invoice absent/saved/deleted states, original-envelope validation, cancelled late request fenced, exact retry, unchanged financial data, scoped identities and roles, protected metadata
rollback;
