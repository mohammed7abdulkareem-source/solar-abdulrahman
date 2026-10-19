-- A user's receipt contact is separate from the customer's number and financial data.
alter table public.profiles add column phone text;
alter table public.profiles add constraint solar_profile_phone_check check(phone is null or phone ~ '^\+?[0-9]{7,15}$');

create function solar_private.normalize_user_phone(value text) returns text language plpgsql immutable set search_path='' as $$
declare result text;begin
 result:=regexp_replace(translate(btrim(coalesce(value,'')),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),'[[:space:]()‎‏-]','','g');
 if left(result,2)='00' then result:='+'||substr(result,3);end if;
 if result !~ '^\+?[0-9]{7,15}$' then raise exception 'أدخل رقم هاتف صحيحاً من 7 إلى 15 رقماً، ويمكن إضافة رمز الدولة';end if;
 return result;
end$$;
revoke all on function solar_private.normalize_user_phone(text) from public,anon,authenticated;

create function solar_private.my_phone(value text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles;begin
 select * into p from public.profiles where id=auth.uid() and active for update;
 if p.id is null then raise exception 'يجب تسجيل الدخول بحساب فعال' using errcode='42501';end if;
 update public.profiles set phone=solar_private.normalize_user_phone(value),updated_at=now() where id=p.id returning * into p;
 return jsonb_build_object('phone',p.phone);
end$$;
create function public.solar_my_phone(phone text) returns jsonb language sql security invoker set search_path='' as $$select solar_private.my_phone(phone)$$;
revoke all on function solar_private.my_phone(text),public.solar_my_phone(text) from public,anon;
grant execute on function solar_private.my_phone(text),public.solar_my_phone(text) to authenticated;

-- Used by the existing cloud snapshot so old invoices also show their author's current phone.
-- Staff get their own contact only; the staff directory does not expose other staff phone numbers.
create function solar_private.receipt_contacts() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'creatorName',coalesce(x.display_name,x.username),'creatorPhone',x.phone)),'[]') from public.profiles x where p.is_admin or x.id=p.id);
end$$;
create function public.solar_receipt_contacts() returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.receipt_contacts()$$;
revoke all on function solar_private.receipt_contacts(),public.solar_receipt_contacts() from public,anon;
grant execute on function solar_private.receipt_contacts(),public.solar_receipt_contacts() to authenticated;

-- Decorate already authorized responses; never accept a submitted contact as the author's identity.
create function solar_private.receipt_contact_json(result jsonb,mode text default 'own') returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles;author public.profiles;t public.transactions;rows jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null then raise exception 'غير مسموح' using errcode='42501';end if;
 if result is null or jsonb_typeof(result)<>'object' then return result;end if;
 if jsonb_typeof(result->'replacement')='object' then result:=jsonb_set(result,'{replacement}',solar_private.receipt_contact_json(result->'replacement','transaction'));end if;
 if mode='rows' then
  select coalesce(jsonb_agg(solar_private.receipt_contact_json(value,'transaction') order by ordinal),'[]') into rows from jsonb_array_elements(coalesce(result->'rows','[]')) with ordinality r(value,ordinal);
  return jsonb_set(result,'{rows}',rows);
 elsif mode='transaction' then
  if coalesce(result->>'id','') !~ '^-?[0-9]+$' then return result;end if;
  select * into t from public.transactions where id=(result->>'id')::bigint;
  if t.id is null or p.user_type in('warehouse','installer') or not(p.is_admin or coalesce(t.created_by,t.cashbox_user_id)=p.id) then
   return result-'creatorName'-'creatorPhone';
  end if;
  select * into author from public.profiles where id=coalesce(t.created_by,t.cashbox_user_id);
 else author:=p;end if;
 return result||jsonb_build_object('creatorName',coalesce(author.display_name,author.username,''),'creatorPhone',author.phone);
end$$;
revoke all on function solar_private.receipt_contact_json(jsonb,text) from public,anon;
grant execute on function solar_private.receipt_contact_json(jsonb,text) to authenticated;

-- Details stay within the same owner and profit permission as the report itself.
create function solar_private.profit_detail(source_key text,owner_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;uid uuid;movement jsonb;t public.transactions;invoice jsonb;begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not(p.is_admin or p.permissions->>'profit'='true' or p.permissions->>'profitSettlement'='true') then raise exception 'لا تملك صلاحية الأرباح' using errcode='42501';end if;
 uid:=coalesce(owner_id,p.id);
 if not p.is_admin and uid<>p.id then raise exception 'يمكنك مشاهدة وصولات أرباحك فقط' using errcode='42501';end if;
 select value into movement from jsonb_array_elements(solar_private.profit_rows(uid)) where value->>'key'=source_key;
 if movement is null then raise exception 'الحركة غير متاحة ضمن هذا الحساب' using errcode='42501';end if;
 if source_key ~ '^tx:-?[0-9]+$' and not coalesce((movement->>'deleted')::boolean,false) then
  select * into t from public.transactions where id=substr(source_key,4)::bigint;
  if t.id is not null then
   if not p.is_admin and coalesce(t.created_by,t.cashbox_user_id)<>p.id then raise exception 'الوصل يخص مستخدماً آخر' using errcode='42501';end if;
   invoice:=solar_private.receipt_contact_json(to_jsonb(t)||jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'),
    'installerName',(select coalesce(display_name,username) from public.profiles where id=t.installer_id)),'transaction');
  end if;
 end if;
 return jsonb_build_object('movement',movement,'invoice',invoice);
end$$;
create function public.solar_profit_detail(source_key text,owner_id uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.profit_detail(source_key,owner_id)$$;
revoke all on function solar_private.profit_detail(text,uuid),public.solar_profit_detail(text,uuid) from public,anon;
grant execute on function solar_private.profit_detail(text,uuid),public.solar_profit_detail(text,uuid) to authenticated;

-- Keep the existing financial functions, idempotency, and authorization unchanged.
CREATE OR REPLACE FUNCTION public.solar_sales_history(search_text text DEFAULT ''::text, sale_kind text DEFAULT ''::text, date_from date DEFAULT NULL::date, date_to date DEFAULT NULL::date, job_status text DEFAULT ''::text, page_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select solar_private.receipt_contact_json(solar_private.sales_history(search_text,sale_kind,date_from,date_to,job_status,page_offset),'rows')$function$;
revoke all on function public.solar_sales_history(search_text text, sale_kind text, date_from date, date_to date, job_status text, page_offset integer) from public,anon;
grant execute on function public.solar_sales_history(search_text text, sale_kind text, date_from date, date_to date, job_status text, page_offset integer) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_fx(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.fx(action,request_id,payload),case when action in('payment','purchase') then 'transaction' else 'own' end)$function$;
revoke all on function public.solar_fx(action text, request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_fx(action text, request_id uuid, payload jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_supplier_payment_save(request_id uuid, payment_id bigint, supplier_id bigint, amount numeric, note text DEFAULT ''::text, expected_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.supplier_payment_save(request_id,payment_id,supplier_id,amount,note,expected_token),'transaction')$function$;
revoke all on function public.solar_supplier_payment_save(request_id uuid, payment_id bigint, supplier_id bigint, amount numeric, note text, expected_token text) from public,anon;
grant execute on function public.solar_supplier_payment_save(request_id uuid, payment_id bigint, supplier_id bigint, amount numeric, note text, expected_token text) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_invoice_save(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.invoice_save(request_id,payload),'transaction')$function$;
revoke all on function public.solar_invoice_save(request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_invoice_save(request_id uuid, payload jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_customer_payment_save(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.customer_payment_save(request_id,payload),'transaction')$function$;
revoke all on function public.solar_customer_payment_save(request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_customer_payment_save(request_id uuid, payload jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_system_payment_context(customer_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.system_payment_context(customer_id),'own')$function$;
revoke all on function public.solar_system_payment_context(customer_id bigint) from public,anon;
grant execute on function public.solar_system_payment_context(customer_id bigint) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_system_payment_save(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.system_payment_save(request_id,payload),'transaction')$function$;
revoke all on function public.solar_system_payment_save(request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_system_payment_save(request_id uuid, payload jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_customer_payment_manage(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.customer_payment_manage(action,request_id,payload),case when action='list' then 'rows' else 'transaction' end)$function$;
revoke all on function public.solar_customer_payment_manage(action text, request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_customer_payment_manage(action text, request_id uuid, payload jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_supplier_payment_manage(action text, request_id uuid DEFAULT NULL::uuid, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.supplier_payment_manage(action,request_id,payload),case when action='list' then 'rows' else 'transaction' end)$function$;
revoke all on function public.solar_supplier_payment_manage(action text, request_id uuid, payload jsonb) from public,anon;
grant execute on function public.solar_supplier_payment_manage(action text, request_id uuid, payload jsonb) to authenticated;
CREATE OR REPLACE FUNCTION public.solar_customer_payment_context(customer_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select solar_private.receipt_contact_json(solar_private.customer_payment_context(customer_id),'own')$function$;
revoke all on function public.solar_customer_payment_context(customer_id bigint) from public,anon;
grant execute on function public.solar_customer_payment_context(customer_id bigint) to authenticated;
