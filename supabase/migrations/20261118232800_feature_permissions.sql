-- Scope flags (ownSales, salesDeleteOwn, etc.) limit an operation; they do not grant it.
create function solar_private.any_feature(grants jsonb, variadic names text[]) returns boolean
language sql immutable parallel safe set search_path='' as $$
 select exists(select 1 from unnest(names) k where grants->k='true'::jsonb)
$$;
create function solar_private.history_feature(grants jsonb, kind text) returns boolean
language sql immutable parallel safe set search_path='' as $$
 select case when grants ? 'salesHistory' and grants->'salesHistory' is distinct from 'true'::jsonb then false
  when solar_private.any_feature(grants,'sale','system') then solar_private.any_feature(grants,kind)
  else solar_private.any_feature(grants,'salesHistory') and kind in ('sale','system') end
$$;
create function solar_private.cash_feature(grants jsonb) returns boolean
language sql immutable parallel safe set search_path='' as $$
 select solar_private.any_feature(grants,'cash','cashDeposit','cashExpense','cashExchange','cashExternalProfit','cashTransferSend','financeReceive')
$$;
create function solar_private.catalog_feature(grants jsonb) returns boolean
language sql immutable parallel safe set search_path='' as $$
 select solar_private.any_feature(grants,'stock','stockMovement','stockAdjust','warehouse','products','sale','system','purchase','wholesalePricingManage')
$$;
create function solar_private.receipt_feature(grants jsonb,kind text,writing boolean) returns boolean
language sql immutable parallel safe set search_path='' as $$
 select case kind
  when 'sale' then solar_private.any_feature(grants,'sale') or (not writing and solar_private.history_feature(grants,kind))
  when 'system' then solar_private.any_feature(grants,'system') or (not writing and solar_private.history_feature(grants,kind))
  when 'purchase' then solar_private.any_feature(grants,'purchase') or (not writing and solar_private.any_feature(grants,'supplierStatement','suppliers'))
  when 'customer_payment' then solar_private.any_feature(grants,'customerPayment') or (not writing and solar_private.any_feature(grants,'customerStatement','customers','customerCreate'))
  when 'system_payment' then solar_private.any_feature(grants,'systemPayment') or (not writing and solar_private.any_feature(grants,'customerStatement','customers','customerCreate'))
  when 'supplier_payment' then solar_private.any_feature(grants,'supplierPayment') or (not writing and solar_private.any_feature(grants,'supplierStatement'))
  when 'profit_expense' then solar_private.any_feature(grants,'cashExpense') or(not writing and solar_private.any_feature(grants,'profit','profitSettlement'))
  when 'cash_income' then case when writing then solar_private.any_feature(grants,'cashDeposit','cashExternalProfit') else solar_private.cash_feature(grants) end
  when 'cash_expense' then case when writing then solar_private.any_feature(grants,'cashExpense') else solar_private.cash_feature(grants) end
  when 'profit_distribution' then not writing and solar_private.cash_feature(grants)
  else false end
$$;
create function solar_private.office_features() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select p.permissions from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('warehouse','installer')),'{}'::jsonb)
$$;
revoke all on function solar_private.any_feature(jsonb,text[]),solar_private.history_feature(jsonb,text),
 solar_private.cash_feature(jsonb),solar_private.catalog_feature(jsonb),solar_private.receipt_feature(jsonb,text,boolean),
 solar_private.office_features() from public,anon;
grant execute on function solar_private.any_feature(jsonb,text[]),solar_private.history_feature(jsonb,text),
 solar_private.cash_feature(jsonb),solar_private.catalog_feature(jsonb),solar_private.receipt_feature(jsonb,text,boolean),
 solar_private.office_features() to authenticated;

create policy solar_feature_receipt_read on public.transactions as restrictive for select to authenticated
 using((select solar_private.role_name())='admin' or solar_private.receipt_feature((select solar_private.office_features()),kind,false));
create policy solar_feature_receipt_insert on public.transactions as restrictive for insert to authenticated
 with check((select solar_private.role_name())='admin' or solar_private.receipt_feature((select solar_private.office_features()),kind,true));
create policy solar_feature_receipt_update on public.transactions as restrictive for update to authenticated
 using((select solar_private.role_name())='admin' or solar_private.receipt_feature((select solar_private.office_features()),kind,true))
 with check((select solar_private.role_name())='admin' or solar_private.receipt_feature((select solar_private.office_features()),kind,true));
-- Receipt deletion already has protected, revision-checked RPC entry points.
create policy solar_no_direct_receipt_delete on public.transactions as restrictive for delete to authenticated using(false);
-- The existing line/ledger policies require a visible parent receipt. Client writes
-- to those rows must also have the parent receipt's write permission.
do $$declare tab text; condition text;begin
 foreach tab in array array['transaction_items','cash_ledger'] loop
  condition:=format('((select solar_private.role_name())=''admin'' or exists(select 1 from public.transactions t where t.id=%I.transaction_id and solar_private.receipt_feature((select solar_private.office_features()),t.kind,true)))',tab);
  execute format('create policy solar_feature_parent_insert on public.%I as restrictive for insert to authenticated with check(%s)',tab,condition);
  execute format('create policy solar_feature_parent_update on public.%I as restrictive for update to authenticated using(%s) with check(%s)',tab,condition,condition);
  execute format('create policy solar_feature_parent_delete on public.%I as restrictive for delete to authenticated using(%s)',tab,condition);
 end loop;
end$$;
create policy solar_feature_cash_entry on public.solar_cash_entries as restrictive for select to authenticated
 using((select solar_private.role_name())='admin' or (select solar_private.cash_feature(solar_private.office_features())));
-- Raw catalog/party rows are separate from intentionally projected quote or statement data.
do $$declare row record; read_condition text; write_condition text;begin
 for row in select * from(values
 ('products','solar_private.catalog_feature(solar_private.office_features())',array['products']),
 ('brands','solar_private.catalog_feature(solar_private.office_features()) or solar_private.any_feature(solar_private.office_features(),''brands'')',array['brands']),
 ('customers','solar_private.any_feature(solar_private.office_features(),''customers'',''customerCreate'',''customerStatement'',''customerPayment'',''systemPayment'',''customerDebts'',''sale'',''system'')',array['customers','customerCreate']),
 ('suppliers','solar_private.any_feature(solar_private.office_features(),''suppliers'',''supplierStatement'',''supplierPayment'',''supplierBalances'',''purchase'')',array['suppliers'])
 )v(tab,read_gate,write_keys) loop
  read_condition:='((select solar_private.role_name())=''admin'' or (select '||row.read_gate||'))';
  write_condition:=format('((select solar_private.role_name())=''admin'' or (select solar_private.any_feature(solar_private.office_features(),variadic %L::text[])))',row.write_keys);
  execute format('create policy solar_feature_read on public.%I as restrictive for select to authenticated using(%s)',row.tab,read_condition);
  execute format('create policy solar_feature_insert on public.%I as restrictive for insert to authenticated with check(%s)',row.tab,write_condition);
  execute format('create policy solar_feature_update on public.%I as restrictive for update to authenticated using(%s) with check(%s)',row.tab,write_condition,write_condition);
  execute format('create policy solar_feature_delete on public.%I as restrictive for delete to authenticated using(%s)',row.tab,write_condition);
 end loop;
end$$;

-- Legacy public entry points delegate to these definer functions. Add guards at
-- that common boundary, preserving their existing owner/warehouse/date filters.
create function pg_temp.solar_feature_patch(target regprocedure,anchor text,replacement text) returns void
language plpgsql set search_path='' as $$
declare definition text:=pg_get_functiondef(target);
begin
 if strpos(definition,anchor)=0 or strpos(substr(definition,strpos(definition,anchor)+length(anchor)),anchor)>0 then
  raise exception 'Review permission integration in %: unexpected anchor %',target,anchor;end if;
 execute replace(definition,anchor,replacement);
end$$;
do $$declare fn regprocedure;begin
 foreach fn in array array['solar_private.sales_history(text,text,date,date,text,integer,uuid)'::regprocedure,'solar_private.sales_period(text,text,date,date,text,uuid)'::regprocedure] loop
  perform pg_temp.solar_feature_patch(fn,' selected_user:=case', $patch$
 if not p.is_admin and not (solar_private.history_feature(p.permissions,'sale') or solar_private.history_feature(p.permissions,'system')) then
  raise exception 'لا تملك صلاحية المبيعات السابقة' using errcode='42501';end if;
 selected_user:=case$patch$);
  perform pg_temp.solar_feature_patch(fn,'and(p.is_admin or t.created_by=p.id)','and(p.is_admin or (t.created_by=p.id and solar_private.history_feature(p.permissions,t.kind)))');
 end loop;
end$$;

select pg_temp.solar_feature_patch('solar_private.cash_allowed(text)',
 $old$exists(select 1 from jsonb_each_text(p.permissions) e where e.key in('cash','cashDeposit','cashExpense','cashExchange','cashExternalProfit','cashAdminTools','cashTransferSend','financeReceive') and e.value='true')$old$,
 'solar_private.cash_feature(p.permissions)');
select pg_temp.solar_feature_patch('solar_private.cash_read_balances()','if actor.id is null then','if actor.id is null or not solar_private.cash_allowed(''view'') then');
select pg_temp.solar_feature_patch('solar_private.exchange_get()','if p.id is null or p.user_type in (''warehouse'',''installer'') then',$patch$if p.id is null or p.user_type in ('warehouse','installer') or not(p.is_admin or solar_private.cash_feature(p.permissions) or solar_private.any_feature(p.permissions,'exchangeRate','exchangeRateEdit','sale','system','purchase','stock','stockMovement','products','supplierPayment','supplierStatement','customerPayment','systemPayment','wholesalePricingManage')) then$patch$);
select pg_temp.solar_feature_patch('solar_private.fx(text,uuid,jsonb)', $s$if action='state' then$s$, $s$if action='state' then
  if not(p.is_admin or solar_private.cash_feature(p.permissions) or solar_private.any_feature(p.permissions,'purchase','supplierPayment','supplierStatement','suppliers')) then
   raise exception 'لا تملك صلاحية الحركات المالية' using errcode='42501';end if;$s$);
select pg_temp.solar_feature_patch('solar_private.fx(text,uuid,jsonb)',
 'from solar_private.wallet_fx_entries e where p.is_admin or e.owner_id=p.id)',
 'from solar_private.wallet_fx_entries e where p.is_admin or (solar_private.cash_feature(p.permissions) and e.owner_id=p.id))');
select pg_temp.solar_feature_patch('solar_private.fx(text,uuid,jsonb)',
 'from solar_private.supplier_fx_entries e where p.is_admin or e.owner_id=p.id)',
 'from solar_private.supplier_fx_entries e where p.is_admin or (solar_private.any_feature(p.permissions,''purchase'',''supplierPayment'',''supplierStatement'',''suppliers'') and e.owner_id=p.id))');

select pg_temp.solar_feature_patch('solar_private.inventory(text,uuid,jsonb)', ' location:=nullif(', $patch$
 if not(person.is_admin or person.user_type='warehouse' or solar_private.catalog_feature(person.permissions)) then
  if action='catalog' and (case when person.permissions ? 'tahseel' then solar_private.any_feature(person.permissions,'tahseel') else solar_private.any_feature(person.permissions,'system') end) then
   return(select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'code',m.code,'name',m.name,'brand_id',m.brand_id,'brand',b.name,'brands',jsonb_build_object('name',b.name),'category',m.category)||
    case when solar_private.any_feature(person.permissions,'tahseelFull') then jsonb_build_object('cost',solar_private.current_unit_cost(m.id,m.cost_basis,m.cost)) else '{}'::jsonb end
    order by m.name,m.id),'[]'::jsonb)from public.products m left join public.brands b on b.id=m.brand_id);
  end if;
  raise exception 'لا تملك صلاحية المخزون' using errcode='42501';
 end if;
 location:=nullif($patch$);
select pg_temp.solar_feature_patch('solar_private.profit_detail(text,uuid)', $s$not(p.is_admin or p.permissions->>'profit'='true' or p.permissions->>'profitSettlement'='true')$s$, $s$not(p.is_admin or solar_private.any_feature(p.permissions,'profit','profitSettlement'))$s$);
-- Internal balance engine is never a user-callable balance lookup by arbitrary user ID.
revoke execute on function solar_private.cash_balance(uuid) from public,anon,authenticated;

create function solar_private.delete_kind_feature(grants jsonb,kind text) returns boolean
language sql immutable parallel safe set search_path='' as $$
 select case when kind in('sale','system','purchase') then solar_private.any_feature(grants,kind)
  when kind='customer_payment' then solar_private.any_feature(grants,'customerPayment')
  when kind='system_payment' then solar_private.any_feature(grants,'systemPayment')
  when kind='supplier_payment' then solar_private.any_feature(grants,'supplierPayment')
  when kind in('cash_income','cash_expense','profit_distribution') then solar_private.cash_feature(grants)
  else false end
$$;
revoke all on function solar_private.delete_kind_feature(jsonb,text) from public,anon,authenticated;

select pg_temp.solar_feature_patch('solar_private.receipt_delete_context(bigint)',' context:=solar_private.receipt_delete_context_v3102(invoice_id);',$patch$
 if solar_private.role_name() is distinct from 'admin' and not exists(
  select 1 from public.transactions t where t.id=invoice_id
   and solar_private.delete_kind_feature(solar_private.office_features(),t.kind)
   and (t.kind in('sale','system','purchase') or solar_private.any_feature(solar_private.office_features(),'deletionRequests'))
 ) then raise exception 'لا تملك صلاحية حذف هذا النوع من الوصولات' using errcode='42501';end if;
 context:=solar_private.receipt_delete_context_v3102(invoice_id);$patch$);
select pg_temp.solar_feature_patch('solar_private.receipt_delete_context(bigint)','return context||eligibility;',
  'return context||eligibility||jsonb_build_object(''canRequest'',solar_private.role_name()=''admin'' or solar_private.any_feature(solar_private.office_features(),''deletionRequests''));');
select pg_temp.solar_feature_patch('solar_private.receipt_delete_requests(text,uuid,jsonb)',
 ' if action is null or action not in(', $patch$ if solar_private.role_name() is distinct from 'admin' and action not in('context','delete_direct') and
    not solar_private.any_feature(solar_private.office_features(),'deletionRequests') then
  raise exception 'لا تملك صلاحية طلبات حذف الوصولات' using errcode='42501';end if;
 if action is null or action not in($patch$);
select pg_temp.solar_feature_patch('solar_private.receipt_delete_requests(text,uuid,jsonb)',
 'if e.mode=''direct'' and e.actor_id=p.id', 'if e.mode=''direct'' and (p.is_admin or solar_private.delete_kind_feature(p.permissions,e.snapshot->>''kind'')) and e.actor_id=p.id');
select pg_temp.solar_feature_patch('solar_private.receipt_delete_requests_v3102(text,uuid,jsonb)',
 ' where(p.is_admin or q.owner_id=p.id)and(q.kind', ' where(p.is_admin or(q.owner_id=p.id and solar_private.delete_kind_feature(p.permissions,q.kind)))and(q.kind');
select pg_temp.solar_feature_patch('solar_private.receipt_delete_requests_v3102(text,uuid,jsonb)',
 'if r.id is null or(not p.is_admin and r.owner_id<>p.id)then',
 'if r.id is null or(not p.is_admin and(r.owner_id<>p.id or not solar_private.delete_kind_feature(p.permissions,r.kind)))then');
select pg_temp.solar_feature_patch('solar_private.receipt_delete_requests_v3102(text,uuid,jsonb)',
 'if r.requested_by=p.id and r.submission=payload', 'if (p.is_admin or solar_private.delete_kind_feature(p.permissions,r.kind)) and r.requested_by=p.id and r.submission=payload');
select pg_temp.solar_feature_patch('solar_private.cash_movement_delete_context(text)',' if movement_id~',
 $patch$ if solar_private.role_name() is distinct from 'admin' and not solar_private.any_feature(solar_private.office_features(),'deletionRequests') then return jsonb_build_object('canRequest',false);end if;
 if movement_id~$patch$);
select pg_temp.solar_feature_patch('solar_private.sale_delete_data(bigint)','if t.id is null or not solar_private.can_delete_sale(t.created_by)',
 'if t.id is null or not solar_private.can_delete_sale(t.created_by) or (solar_private.role_name()<>''admin'' and not solar_private.any_feature(solar_private.office_features(),t.kind))');
select pg_temp.solar_feature_patch('solar_private.invoice_attempt_resolve(uuid,jsonb)',' if p.id is null then',
 ' if p.id is null or not(p.is_admin or solar_private.any_feature(p.permissions,payload->>''kind'')) then');
select pg_temp.solar_feature_patch('solar_private.invoice_save(uuid,jsonb)',' perform pg_advisory_xact_lock(7311,1);',
 $patch$ if solar_private.role_name() is distinct from 'admin' and not solar_private.any_feature(solar_private.office_features(),payload->>'kind') then raise exception 'لا تملك صلاحية حفظ هذه الفاتورة' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);$patch$);
select pg_temp.solar_feature_patch('solar_private.warehouse_statuses(bigint[])','and t.created_by=p.id)',
 'and t.created_by=p.id and(solar_private.receipt_feature(p.permissions,t.kind,false) or solar_private.any_feature(p.permissions,''warehouse'',''installations'')))');
select pg_temp.solar_feature_patch('solar_private.sales_history(text,text,date,date,text,integer,uuid)',
 '''canDelete'',solar_private.can_delete_sale(t.created_by)', '''canDelete'',solar_private.can_delete_sale(t.created_by) and(p.is_admin or solar_private.any_feature(p.permissions,t.kind))');
select pg_temp.solar_feature_patch('solar_private.sale_preparation(text,bigint,text,uuid)','if p.id is null then',
 'if p.id is null or not(p.is_admin or solar_private.any_feature(p.permissions,''sale'',''warehouse'') or (action=''get'' and solar_private.history_feature(p.permissions,''sale''))) then');
select pg_temp.solar_feature_patch('solar_private.cash_record(text,text,uuid,jsonb)','if p.id is null then','if p.id is null or not solar_private.cash_allowed(''view'') then');
select pg_temp.solar_feature_patch('solar_private.fx(text,uuid,jsonb)', ' if action=''wallet'' and payload', $patch$
 if (action='payment' and not(p.is_admin or solar_private.any_feature(p.permissions,'supplierPayment')))
  or (action='wallet' and not solar_private.cash_allowed('view'))
  or (action='currency' and not p.is_admin) then
  raise exception 'لا تملك صلاحية هذه العملية المالية' using errcode='42501';end if;
 if action='wallet' and payload$patch$);
drop function pg_temp.solar_feature_patch(regprocedure,text,text);
notify pgrst,'reload schema';
