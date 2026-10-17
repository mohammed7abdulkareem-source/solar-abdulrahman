-- Positive input amounts: cash payments reduce supplier debt; charge_* entries
-- increase it with a negative, non-cash supplier_payment. No stock/cost changes.
create or replace function solar_private.supplier_payment_get(payment_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; t public.transactions;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true') then raise exception 'لا تملك صلاحية حركة المورد' using errcode='42501';end if;
 select * into t from public.transactions where id=payment_id and kind='supplier_payment';
 if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية هذا الوصل' using errcode='42501';end if;
 return jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'supplierId',t.party_id,'party',t.party_name,'total',t.total,'cash',t.cash,'mode',t.payment_mode,
 'notes',t.notes,'date',t.created_at,'token',md5(to_jsonb(t)::text));
end $$;

create function solar_private.supplier_account(supplier_id bigint,payment_id bigint default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;s public.suppliers;t public.transactions;payer uuid;balance numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true') then raise exception 'لا تملك صلاحية حساب المورد' using errcode='42501';end if;
 select * into s from public.suppliers where id=supplier_id;
 if s.id is null then raise exception 'المورد غير موجود';end if;
 payer:=p.id;
 if payment_id is not null then
  select * into t from public.transactions where id=payment_id and kind='supplier_payment';
  if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية هذا الوصل' using errcode='42501';end if;
  payer:=coalesce(t.cashbox_user_id,t.created_by);
 end if;
 select coalesce(sum(case when x.kind='supplier_payment' then -x.total when x.cash then 0 else x.total end),0) into balance
 from public.transactions x where x.kind in ('purchase','supplier_payment') and
 (x.party_id=s.id or(x.party_id is null and solar_private.customer_name_key(x.party_name)=solar_private.customer_name_key(s.name) and(select count(*) from public.suppliers a where solar_private.customer_name_key(a.name)=solar_private.customer_name_key(s.name))=1))
 and (p.is_admin or coalesce(x.cashbox_user_id,x.created_by)=p.id);
 return jsonb_build_object('supplierId',s.id,'balance',balance,'cashBalance',solar_private.cash_balance(payer),
 'cashOwnerName',(select coalesce(x.display_name,x.username,'مستخدم') from public.profiles x where x.id=payer));
end $$;

-- Existing cash API remains compatible with old request fingerprints. It may
-- not turn a non-cash charge into a cash receipt through an older client.
do $$declare definition text;needle text;begin
 select pg_get_functiondef('solar_private.supplier_payment_save(uuid,bigint,bigint,numeric,text,text)'::regprocedure) into definition;
 needle:='if expected_token is distinct from md5(to_jsonb(t)::text) then';
 if strpos(definition,needle)=0 then raise exception 'Supplier payment definition changed; review cash integration';end if;
 execute replace(definition,needle,'if t.cash is false and t.total<0 then raise exception ''هذه إضافة غير نقدية؛ استخدم تعديل إضافة حساب المورد'';end if; '||needle);
end $$;

create function solar_private.supplier_movement_save(request_id uuid,payment_id bigint,supplier_id bigint,amount numeric,movement_mode text,note text default '',expected_token text default null)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare p public.profiles;t public.transactions;s public.suppliers;prior solar_private.supplier_payment_requests;
args jsonb;result jsonb;before_row jsonb;payer uuid;before_balance numeric;after_account jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true') then raise exception 'لا تملك صلاحية تسديد أو إضافة حساب مورد' using errcode='42501';end if;
 if request_id is null or payment_id is null or abs(payment_id)>9007199254740991 or amount is null or not(amount>0 and amount<=1000000000000) or round(amount,2)<>amount or length(coalesce(note,''))>2000 or movement_mode is null or movement_mode not in ('cash','charge_extra_expense','charge_old_balance','charge_other') then raise exception 'أدخل مبلغاً ونوع حركة صحيحين';end if;
 perform pg_advisory_xact_lock(7311,1);
 if movement_mode='cash' then return solar_private.supplier_payment_save(request_id,payment_id,supplier_id,amount,note,expected_token);end if;
 if length(trim(coalesce(note,'')))=0 then raise exception 'اكتب سبب الإضافة على حساب المورد';end if;
 args:=jsonb_build_object('id',payment_id,'supplierId',supplier_id,'amount',amount,'mode',movement_mode,'note',coalesce(note,''),'token',expected_token);
 select * into prior from solar_private.supplier_payment_requests r where r.request_id=supplier_movement_save.request_id;
 if found then
  if prior.actor_id=p.id and prior.arguments=args then return prior.response;end if;
  raise exception 'طلب مكرر ببيانات مختلفة' using errcode='40001';
 end if;
 select * into s from public.suppliers where id=supplier_id;
 if s.id is null then raise exception 'المورد غير موجود';end if;
 select * into t from public.transactions where id=payment_id for update;
 if found then
  if t.kind<>'supplier_payment' or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'لا تملك صلاحية هذا الوصل' using errcode='42501';end if;
  if t.cash or t.total>=0 or coalesce(t.payment_mode,'') not in ('charge_extra_expense','charge_old_balance','charge_other') then raise exception 'لا يمكن تحويل تسديد نقدي إلى إضافة على الحساب؛ سجّل إضافة مستقلة';end if;
  if expected_token is distinct from md5(to_jsonb(t)::text) then raise exception 'تغير الوصل؛ افتحه مجدداً قبل التعديل' using errcode='40001';end if;
  before_row:=to_jsonb(t);payer:=coalesce(t.cashbox_user_id,t.created_by);
 else
  if expected_token is not null then raise exception 'تغير الوصل؛ افتحه مجدداً قبل التعديل' using errcode='40001';end if;
  payer:=p.id;
 end if;
 if payer is null then raise exception 'المستخدم المسؤول عن الوصل غير موجود';end if;
 before_balance:=(solar_private.supplier_account(s.id)->>'balance')::numeric;
 if t.id is null then
  insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes)
  values(payment_id,'supplier_payment','supplier',s.id,s.name,-amount,false,movement_mode,p.id,payer,note);
 else
  update public.transactions set party_type='supplier',party_id=s.id,party_name=s.name,total=-amount,cash=false,payment_mode=movement_mode,notes=note where id=payment_id;
 end if;
 after_account:=solar_private.supplier_account(s.id);
 result:=solar_private.supplier_payment_get(payment_id)||jsonb_build_object('beforeBalance',before_balance,'afterBalance',(after_account->>'balance')::numeric,'cashAfter',(after_account->>'cashBalance')::numeric);
 insert into solar_private.supplier_payment_requests(request_id,actor_id,arguments,before_row,response) values(request_id,p.id,args,before_row,result);
 return result;
end $$;
revoke all on function solar_private.supplier_account(bigint,bigint),solar_private.supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text) from public,anon;
grant execute on function solar_private.supplier_account(bigint,bigint),solar_private.supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text) to authenticated;
create function public.solar_supplier_account(supplier_id bigint,payment_id bigint default null) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.supplier_account(supplier_id,payment_id)$$;
create function public.solar_supplier_movement_save(request_id uuid,payment_id bigint,supplier_id bigint,amount numeric,movement_mode text,note text default '',expected_token text default null) returns jsonb language sql security invoker set search_path='' as $$select solar_private.supplier_movement_save(request_id,payment_id,supplier_id,amount,movement_mode,note,expected_token)$$;
revoke all on function public.solar_supplier_account(bigint,bigint),public.solar_supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text) from public,anon;
grant execute on function public.solar_supplier_account(bigint,bigint),public.solar_supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text) to authenticated;
