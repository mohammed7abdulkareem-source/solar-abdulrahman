\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003520','Contact Admin','contact_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003521','صاحب الوصل','contact_owner',false,'admin_staff','{"sale":true,"profit":true,"profitSettlement":true,"customerPayment":true}'),
('00000000-0000-0000-0000-000000003522','مستخدم آخر','contact_other',false,'admin_staff','{"profit":true}'),
('00000000-0000-0000-0000-000000003523','بدون أرباح','contact_none',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003524','Warehouse','contact_warehouse',false,'warehouse','{}');
insert into customers(id,name,customer_type,owner_id) values(-352001,'عميل الهاتف','wholesale','00000000-0000-0000-0000-000000003521');
insert into products(id,code,name,qty,cost) values(-352001,'CONTACT','مادة ضمان',10,50000);
create temporary table before_phone as select to_jsonb(p)-array['phone','updated_at'] data from profiles p where id='00000000-0000-0000-0000-000000003521';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003521',true);
do $$declare r jsonb;a jsonb;c jsonb;s jsonb;begin
 r:=public.solar_my_phone('٠٧٧٠ ١٢٣-٤٥٦٧');if r->>'phone'<>'07701234567' then raise exception 'phone normalization';end if;
 begin perform public.solar_my_phone('123<script>');raise exception 'invalid accepted';exception when raise_exception then if sqlerrm='invalid accepted' then raise;end if;end;
 c:=public.solar_receipt_contacts();if jsonb_array_length(c)<>1 or c->0->>'creatorPhone'<>'07701234567' then raise exception 'contact directory scope';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","party":"عميل الهاتف","sourceCurrency":"IQD","expenses":0,"items":[{"id":-352001,"qty":2,"price":150000}],"warranty":{"enabled":true,"items":[{"id":-352001,"duration":2,"unit":"years"}],"maintenance":{"duration":6,"unit":"months"}}}');
 if r->>'creatorPhone' is distinct from '07701234567' or r->>'creatorName' is distinct from 'صاحب الوصل' then raise exception 'new save lacks creator contact %',r;end if;
 perform set_config('test.contact_id',r->>'id',true);perform set_config('test.contact_account',(r->'invoiceAccount')::text,true);
 a:=public.solar_profit_detail('tx:'||(r->>'id'));
 if a->'invoice'->>'creatorPhone'<>'07701234567' or jsonb_array_length(a->'invoice'->'items')<>1 or not(a->'invoice'->'warranty'->>'enabled')::boolean or a->'invoice'->>'warranty_token' is null then raise exception 'incomplete source invoice details %',a;end if;
 if(a->'movement'->>'value')::numeric<>200000 then raise exception 'profit changed';end if;
 c:=public.solar_customer_payment_context(-352001);
 if c->>'creatorPhone'<>'07701234567' then raise exception 'draft context contact';end if;
 s:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-352001,'amount',50000,'mode','payment','expectedToken',c->>'token'));
 if s->>'creatorPhone' is distinct from '07701234567' then raise exception 'payment contact missing %',s;end if;
 perform set_config('test.contact_payment',s->>'id',true);
 perform public.solar_my_phone('+964 770 765 4321');
 a:=public.solar_profit_detail('tx:'||(r->>'id'));
 if a->'invoice'->>'creatorPhone'<>'+9647707654321' or a->'invoice'->'invoice_account'<>current_setting('test.contact_account')::jsonb then raise exception 'contact update changed account snapshot';end if;
end$$;
reset role;
do $$begin if(select to_jsonb(p)-array['phone','updated_at'] from profiles p where id='00000000-0000-0000-0000-000000003521')<>(select data from before_phone) then raise exception 'self phone update changed permissions';end if;end$$;
-- A profit-only user may view their source invoice without needing sales-history privileges.
update profiles set permissions='{"profit":true}' where id='00000000-0000-0000-0000-000000003521';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003521',true);
do $$begin if public.solar_profit_detail('tx:'||current_setting('test.contact_id'))->'invoice' is null then raise exception 'own profit-only invoice missing';end if;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003522',true);
do $$declare r jsonb;begin
 begin perform public.solar_profit_detail('tx:'||current_setting('test.contact_id'));raise exception 'foreign invoice exposed';exception when insufficient_privilege then null;end;
 begin perform public.solar_profit_detail('tx:'||current_setting('test.contact_id'),'00000000-0000-0000-0000-000000003521');raise exception 'foreign report exposed';exception when insufficient_privilege then null;end;
 r:=solar_private.receipt_contact_json(jsonb_build_object('id',current_setting('test.contact_id')),'transaction');if r ? 'creatorPhone' then raise exception 'forged response exposed foreign phone';end if;
 if jsonb_array_length(public.solar_receipt_contacts())<>1 then raise exception 'foreign contact directory';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003523',true);
do $$begin begin perform public.solar_profit_detail('tx:'||current_setting('test.contact_id'));raise exception 'permission bypass';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003524',true);
do $$begin begin perform public.solar_profit_detail('tx:'||current_setting('test.contact_id'));raise exception 'warehouse financial leak';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003520',true);
do $$declare r jsonb;begin
 r:=public.solar_profit_detail('tx:'||current_setting('test.contact_id'),'00000000-0000-0000-0000-000000003521');
 if r->'invoice'->>'creatorPhone'<>'+9647707654321' or r->'invoice'->>'creatorName'<>'صاحب الوصل' then raise exception 'admin print replaced creator';end if;
 r:=public.solar_customer_payment_manage('get',null,jsonb_build_object('id',current_setting('test.contact_payment')::bigint));
 if r->>'creatorPhone'<>'+9647707654321' then raise exception 'old payment reprint lacks creator';end if;
end$$;
reset role;
update profiles set active=false where id='00000000-0000-0000-0000-000000003521';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003521',true);
do $$begin begin perform public.solar_my_phone('07700000000');raise exception 'inactive phone update';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin if has_function_privilege('anon','public.solar_profit_detail(text,uuid)','execute') or has_function_privilege('anon','public.solar_my_phone(text)','execute') then raise exception 'anonymous access';end if;raise notice 'PASS own-only drill-down, profit-only permission, warranty/account preservation, phone normalization/self-edit, immediate save contact, customer receipt/reprint contact, admin retains original creator, denied foreign/inactive/warehouse access';end$$;
rollback;
