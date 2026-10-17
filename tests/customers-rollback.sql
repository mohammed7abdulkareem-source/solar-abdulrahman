-- Isolated PostgreSQL fixture only; no customer production records are used.
begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000003320','Customers Admin',true,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003321','Customers Staff',false,'{"customers":true,"customerStatement":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003322','Other Staff',false,'{"customers":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003323','Engineer',false,'{"customers":true}','installer'),
 ('00000000-0000-0000-0000-000000003324','No permissions',false,'{}','admin_staff');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003321',true);
do $$declare result jsonb;again jsonb; payload jsonb;begin
 payload:='{"id":-332001,"name":"أحمد  علي","phone":"07701234567","customerType":"system","openingBalance":2000000}';
 result:=public.solar_customer_save('create','00000000-0000-0000-0000-000000332001',payload);
 if (result->>'openingBalance')::numeric<>2000000 or (result->>'balance')::numeric<>2000000 then raise exception 'FAIL initial opening balance';end if;
 again:=public.solar_customer_save('create','00000000-0000-0000-0000-000000332001',payload);
 if again is distinct from result or (select count(*) from public.transactions where party_id=-332001)<>1 then raise exception 'FAIL retry duplicated opening';end if;
 if jsonb_array_length(public.solar_customer_check('احمدعلي','',null))<>1 then raise exception 'FAIL normalized name lookup';end if;
 if jsonb_array_length(public.solar_customer_check('','+964 770 123 4567',null))<>1 then raise exception 'FAIL phone lookup';end if;
 begin perform public.solar_customer_save('create','00000000-0000-0000-0000-000000332002','{"id":-332002,"name":"احمد علي","phone":"","customerType":"system","openingBalance":0}');raise exception 'FAIL duplicate name accepted';exception when unique_violation then null;end;
 begin perform public.solar_customer_save('create','00000000-0000-0000-0000-000000332003','{"id":-332003,"name":"زبون آخر","phone":"009647701234567","customerType":"system","openingBalance":0}');raise exception 'FAIL duplicate phone accepted';exception when unique_violation then null;end;
end $$;
reset role;
-- A received customer payment must keep its amount, cashbox and date when the
-- opening balance is subsequently corrected.
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)
 values(-332010,'system_payment',-332001,'أحمد علي',500000,true,'payment','00000000-0000-0000-0000-000000003321','00000000-0000-0000-0000-000000003321');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003321',true);
do $$declare current jsonb; changed jsonb; old_token text;payload jsonb;begin
 current:=public.solar_customer_get(-332001);old_token:=current->>'token';
 payload:=jsonb_build_object('id',-332001,'token',old_token,'name','أحمد علي','phone','07701234567','customerType','system','openingBalance',3000000);
 changed:=public.solar_customer_save('update','00000000-0000-0000-0000-000000332004',payload);
 if (changed->>'openingBalance')::numeric<>3000000 or (changed->>'balance')::numeric<>2500000 then raise exception 'FAIL opening correction totals';end if;
 if (select count(*) from public.transactions where party_id=-332001 and payment_mode='opening_balance')<>1 then raise exception 'FAIL edit created another opening';end if;
 if not exists(select 1 from public.transactions where id=-332010 and total=500000 and cash and payment_mode='payment') then raise exception 'FAIL edit rewrote receipt';end if;
 perform public.solar_customer_save('update','00000000-0000-0000-0000-000000332004',payload);
 if (public.solar_customer_get(-332001)->>'balance')::numeric<>2500000 then raise exception 'FAIL edit retry double applied';end if;
 begin perform public.solar_customer_save('update','00000000-0000-0000-0000-000000332005',payload);raise exception 'FAIL stale edit accepted';exception when serialization_failure then null;end;
 current:=public.solar_customer_get(-332001);
 changed:=public.solar_customer_save('update','00000000-0000-0000-0000-000000332006',jsonb_build_object('id',-332001,'token',current->>'token','name','احمد علي الجديد','phone','07701234567','customerType','wholesale','openingBalance',-1000000));
 if (changed->>'balance')::numeric<>-1500000 or (changed->>'openingBalance')::numeric<>-1000000 then raise exception 'FAIL opening credit direction';end if;
 if not exists(select 1 from public.transactions where id=-332010 and party_name='احمد علي الجديد' and total=500000) then raise exception 'FAIL rename lost old account';end if;
 current:=public.solar_customer_get(-332001);
 changed:=public.solar_customer_save('update','00000000-0000-0000-0000-000000332007',jsonb_build_object('id',-332001,'token',current->>'token','name','احمد علي الجديد','phone','07701234567','customerType','wholesale','openingBalance',0));
 if (changed->>'balance')::numeric<>-500000 then raise exception 'FAIL removing opening changed payments';end if;
 begin perform public.solar_customer_save('delete','00000000-0000-0000-0000-000000332008',jsonb_build_object('id',-332001,'token',changed->>'token'));raise exception 'FAIL deleting financial customer';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003322',true);
do $$declare checks jsonb;begin
 if jsonb_array_length(public.solar_customer_directory())<>0 then raise exception 'FAIL cross-user customer directory';end if;
 begin perform public.solar_customer_get(-332001);raise exception 'FAIL cross-user opening access';exception when insufficient_privilege then null;end;
 checks:=public.solar_customer_check('احمد علي الجديد','',null);
 if jsonb_array_length(checks)<>1 or checks->0->>'id' is not null or checks->0->>'name' is not null then raise exception 'FAIL cross-user duplicate privacy';end if;
 begin update public.customers set phone='07709876543' where id=-332001;raise exception 'FAIL raw cross-user edit';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003324',true);
do $$begin
 begin perform public.solar_customer_directory();raise exception 'FAIL missing permission directory';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_save('create','00000000-0000-0000-0000-000000332009','{"id":-332009,"name":"غير مسموح","customerType":"system","openingBalance":0}');raise exception 'FAIL missing permission create';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003323',true);
do $$begin begin perform public.solar_customer_directory();raise exception 'FAIL engineer financial directory';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if (select count(*) from solar_private.customer_changes)<>4 then raise exception 'FAIL customer audit count';end if;
 if not exists(select 1 from solar_private.customer_changes where before_opening=2000000 and after_opening=3000000 and jsonb_array_length(before_entries)=1) then raise exception 'FAIL opening audit contents';end if;
 if has_table_privilege('authenticated','solar_private.customer_changes','SELECT') then raise exception 'FAIL private audit exposed';end if;
end $$;
-- Legacy multiple opening entries are corrected as an aggregate without
-- deleting entries. A customer without an opening can acquire one later.
insert into public.customers(id,name,customer_type,owner_id) values
 (-332030,'رصيد متعدد','system','00000000-0000-0000-0000-000000003321'),
 (-332031,'بلا افتتاحي','system','00000000-0000-0000-0000-000000003321');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values
 (-332030,'system_payment',-332030,'رصيد متعدد',-1000000,false,'opening_balance','00000000-0000-0000-0000-000000003321','00000000-0000-0000-0000-000000003321'),
 (-332031,'system_payment',-332030,'رصيد متعدد',-2000000,false,'opening_balance','00000000-0000-0000-0000-000000003321','00000000-0000-0000-0000-000000003321');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003321',true);
do $$declare c jsonb;r jsonb;begin
 c:=public.solar_customer_get(-332030);
 r:=public.solar_customer_save('update','00000000-0000-0000-0000-000000332030',jsonb_build_object('id',-332030,'token',c->>'token','name','رصيد متعدد','customerType','system','openingBalance',4000000));
 if (r->>'openingBalance')::numeric<>4000000 or (r->>'openingCount')::int<>2 then raise exception 'FAIL aggregate legacy openings';end if;
 c:=public.solar_customer_get(-332031);
 r:=public.solar_customer_save('update','00000000-0000-0000-0000-000000332031',jsonb_build_object('id',-332031,'token',c->>'token','name','بلا افتتاحي','customerType','system','openingBalance',250000));
 if (r->>'openingBalance')::numeric<>250000 or (r->>'openingCount')::int<>1 then raise exception 'FAIL adding opening on edit';end if;
 c:=r;
 r:=public.solar_customer_save('update','00000000-0000-0000-0000-000000332032',jsonb_build_object('id',-332031,'token',c->>'token','name','بلا افتتاحي','phone','07709998877','customerType','system','openingBalance',250000));
 if (r->>'openingBalance')::numeric<>250000 or (r->>'openingCount')::int<>1 then raise exception 'FAIL metadata edit changed opening';end if;
end $$;
reset role;
rollback;
