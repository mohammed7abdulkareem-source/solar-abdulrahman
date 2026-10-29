-- Preparation records fulfillment only. Stock and money were posted at save.
create function solar_private.sale_preparation(action text,invoice_id bigint,expected_token text default null,request_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare p public.profiles;t public.transactions;prior solar_private.inventory_requests;submission jsonb;result jsonb;lines jsonb;allowed boolean;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'التجهيز المباشر للمستخدم الإداري صاحب الوصل أو الإدارة' using errcode='42501';end if;
 if action not in('get','ready') or action is null then raise exception 'عملية تجهيز غير صحيحة' using errcode='22023';end if;
 if action='ready' then perform pg_advisory_xact_lock(7311,1);end if;
 select * into t from public.transactions where id=invoice_id and kind='sale';
 if t.id is null or (not p.is_admin and t.created_by is distinct from p.id) or not solar_private.warehouse_access_allowed(p.id,t.warehouse_id) then
  raise exception 'وصل الجملة غير متاح ضمن صلاحياتك أو مخازنك' using errcode='42501';end if;
 allowed:=p.is_admin or p.permissions->>'sale'='true' or p.permissions->>'warehouse'='true';
 result:=jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'warehouseId',t.warehouse_id,'warehouseName',t.warehouse_name,
  'warehouseStatus',t.warehouse_status,'warehouseRevision',t.warehouse_revision,'warehousePreparedAt',t.warehouse_prepared_at,
  'token',solar_private.warehouse_token(t.id),'pricingPending',exists(select 1 from solar_private.warehouse_price_edits e where e.invoice_id=t.id),'canPrepare',coalesce(allowed,false));
 if action='get' then return result;end if;
 if not coalesce(allowed,false) then raise exception 'لا تملك صلاحية تأكيد تجهيز هذا الوصل' using errcode='42501';end if;
 if request_id is null then raise exception 'أعد فتح الوصل لتأكيد التجهيز' using errcode='22023';end if;
 submission:=jsonb_build_object('invoiceId',invoice_id,'expectedToken',expected_token);
 select * into prior from solar_private.inventory_requests where id=request_id;
 if prior.id is not null then
  if prior.actor_id<>p.id or prior.action<>'sale_ready' or prior.payload<>submission then raise exception 'طلب تجهيز مكرر ببيانات مختلفة' using errcode='PT409';end if;
  return result||jsonb_build_object('replayed',true);
 end if;
 perform 1 from public.transactions where id=t.id for update;
 if expected_token is null or solar_private.warehouse_token(t.id) is distinct from expected_token then raise exception 'تغيّرت مواد الوصل أو حالته؛ حمّل آخر نسخة وراجعها قبل التجهيز' using errcode='PT409';end if;
 if (result->>'pricingPending')::boolean then raise exception 'المواد الجديدة بانتظار تسعير الإدارة قبل إكمال التجهيز';end if;
 if not exists(select 1 from public.transaction_items where transaction_id=t.id) then raise exception 'الوصل بدون مواد؛ راجع فقراته قبل التجهيز';end if;
 if t.warehouse_status<>'ready' then
  select jsonb_agg(to_jsonb(i) order by i.id) into lines from public.transaction_items i where transaction_id=t.id;
  update public.transactions set warehouse_status='ready',warehouse_prepared_at=now(),warehouse_prepared_by=p.id,
   warehouse_revision=warehouse_revision+1 where id=t.id returning * into t;
  insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items) values(t.id,p.id,'ready',lines,lines);
 end if;
 result:=result||jsonb_build_object('warehouseStatus',t.warehouse_status,'warehouseRevision',t.warehouse_revision,'warehousePreparedAt',t.warehouse_prepared_at,'token',solar_private.warehouse_token(t.id));
 insert into solar_private.inventory_requests(id,actor_id,action,payload,result) values(request_id,p.id,'sale_ready',submission,result);
 return result;
end$$;
create function public.solar_sale_preparation(action text,invoice_id bigint,expected_token text default null,request_id uuid default null) returns jsonb
language sql security invoker set search_path='' as $$select solar_private.sale_preparation(action,invoice_id,expected_token,request_id)$$;
revoke all on function solar_private.sale_preparation(text,bigint,text,uuid),public.solar_sale_preparation(text,bigint,text,uuid) from public,anon;
grant execute on function solar_private.sale_preparation(text,bigint,text,uuid),public.solar_sale_preparation(text,bigint,text,uuid) to authenticated;

-- The checkbox uses the same atomic, idempotent request as invoice creation.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save(uuid,jsonb)'::regprocedure);
 needle:='invoice_result:=solar_private.invoice_save_v333(request_id,payload);';
 if strpos(definition,needle)=0 then raise exception 'Invoice save preparation contract missing';end if;
 definition:=replace(definition,needle,$n$
 if payload ? 'directPreparation' and (jsonb_typeof(payload->'directPreparation') is distinct from 'boolean' or payload->>'kind'<>'sale' or payload->>'invoiceId' is not null) then
  raise exception 'خيار التجهيز المباشر خاص بوصل جملة جديد' using errcode='22023';end if;
 perform set_config('solar.direct_preparation',case when payload->>'directPreparation'='true' then 'true' else '' end,true);
 invoice_result:=solar_private.invoice_save_v333(request_id,payload);
 perform set_config('solar.direct_preparation','',true);$n$);
 needle:='return invoice_result;';
 if strpos(definition,needle)=0 then raise exception 'Invoice save result contract missing';end if;
 definition:=replace(definition,needle,$n$
 if not cached and payload->>'directPreparation'='true' then
  invoice_result:=invoice_result||solar_private.sale_preparation('ready',(invoice_result->>'id')::bigint,solar_private.warehouse_token((invoice_result->>'id')::bigint),request_id);
  update solar_private.invoice_requests set result=invoice_result where invoice_requests.request_id=invoice_save.request_id;
 end if;
 return invoice_result;$n$);
 execute definition;
 -- A directly prepared sale must not announce a pending warehouse task.
 definition:=pg_get_functiondef('solar_private.warehouse_notify()'::regprocedure);
 needle:='if tg_op=''INSERT'' then event_name:=''warehouse_new'';';
 if strpos(definition,needle)=0 then raise exception 'Warehouse creation notification contract missing';end if;
 definition:=replace(definition,needle,$n$if tg_op='INSERT' then
  if new.kind='sale' and current_setting('solar.direct_preparation',true)='true' then return new;end if;
  event_name:='warehouse_new';$n$);
 execute definition;
end$$;
notify pgrst,'reload schema';
