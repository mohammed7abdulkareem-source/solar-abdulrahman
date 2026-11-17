-- Manual cashbox corrections and capital tools require an active office admin.
-- Legacy granular flags cannot grant these reserved administrative operations.
-- No historical receipt, balance, profile, permission, or ledger row is rewritten.
do $migration$
declare definition text; old_gate text; new_gate text; signature text; expected_hash text;
begin
 -- Check all current definitions before any replacement, in one atomic block.
 for signature,expected_hash in select key,value from jsonb_each_text('{
  "solar_private.cash_reconcile(text,uuid,jsonb)":"ca8acc6b898ebd6b220071c6c5890c31",
  "solar_private.cash_allowed(text)":"a863188343d03b899418c1cfe4648bca",
  "solar_private.cash_save(uuid,jsonb)":"b9e5a7485a596253ac3ddb5951d11f0c",
  "solar_private.fx(text,uuid,jsonb)":"d5e246676b4f11e5573ea328b45289bd"
 }'::jsonb) loop
  if md5(pg_get_functiondef(signature::regprocedure))<>expected_hash then
   raise exception 'Review current % definition before applying V4.1.7',signature;
  end if;
 end loop;
 definition:=pg_get_functiondef('solar_private.cash_reconcile(text,uuid,jsonb)'::regprocedure);
 old_gate:=$old$select * into actor from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer') and solar_private.cash_allowed('cashAdminTools');$old$;
 new_gate:=$new$select * into actor from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer') and is_admin;$new$;
 if strpos(definition,old_gate)=0 or strpos(definition,'لا تملك صلاحية أدوات إدارة القاصة')=0 then
  raise exception 'Review cash reconciliation authorization anchors before applying V4.1.7';
 end if;
 -- The first actor lookup protects context, fresh apply, and cached apply replay.
 definition:=replace(definition,old_gate,new_gate);
 definition:=replace(definition,'لا تملك صلاحية أدوات إدارة القاصة','تعديل وتصفير القاصات متاح للأدمن فقط');
 execute definition;

 definition:=pg_get_functiondef('solar_private.cash_allowed(text)'::regprocedure);
 old_gate:=$old$p.is_admin or case when permission='view' then$old$;
 new_gate:=$new$p.is_admin or case when permission in('cashAdminTools','adminOnly') then false when permission='view' then$new$;
 if strpos(definition,old_gate)=0 then raise exception 'Review reserved cash permission anchor';end if;
 execute replace(definition,old_gate,new_gate);

 -- Recheck reserved operations before idempotent replay, including requests
 -- previously saved while their actor still had the old granular permission.
 definition:=pg_get_functiondef('solar_private.cash_save(uuid,jsonb)'::regprocedure);
 old_gate:=$old$if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;$old$;
 new_gate:=$new$if payload->>'mode' in('capital_deposit','capital_withdraw','distribution') and not solar_private.cash_allowed('cashAdminTools') then raise exception 'إدارة رأس المال وتوزيع الأرباح متاحة للأدمن فقط' using errcode='42501';end if;
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب';end if;$new$;
 if strpos(definition,old_gate)=0 then raise exception 'Review cash save replay authorization anchor';end if;
 execute replace(definition,old_gate,new_gate);

 definition:=pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure);
 old_gate:=$old$if action='state' then$old$;
 new_gate:=$new$if action='wallet' and payload->>'mode' in('deposit','withdraw') and not solar_private.cash_allowed('cashAdminTools') then raise exception 'إضافة وسحب رأس مال الدولار متاح للأدمن فقط' using errcode='42501';end if;
 if action='state' then$new$;
 if strpos(definition,old_gate)=0 then raise exception 'Review legacy wallet replay authorization anchor';end if;
 execute replace(definition,old_gate,new_gate);
end $migration$;

notify pgrst, 'reload schema';
