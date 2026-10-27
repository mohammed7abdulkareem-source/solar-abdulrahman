-- Adjust approved installation costs in the same transaction as the invoice,
-- stock, customer balance, warranty, profit and audit. Reuse the existing signed
-- cash posting routine: pay only increases and refund original payers.
CREATE OR REPLACE FUNCTION solar_private.invoice_save(request_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare invoice_result jsonb;before_row public.transactions;after_row public.transactions;location bigint;before_stock jsonb;old_lines jsonb:='[]';new_lines jsonb;ids bigint[];cached boolean;approved_expenses numeric;expense_change boolean:=false;begin
 perform pg_advisory_xact_lock(7311,1);
 if exists(select 1 from solar_private.invoice_attempt_cancellations c where c.request_id=invoice_save.request_id) then raise exception 'المحاولة السابقة انتهت دون حفظ؛ راجع البيانات واضغط حفظ مجددًا' using errcode='PT410';end if;
 if payload->>'invoiceId' is not null then
  select warehouse_id into location from public.transactions where id=(payload->>'invoiceId')::bigint;
  if payload->>'warehouseId' is not null and location is distinct from (payload->>'warehouseId')::bigint then raise exception 'لا يمكن تغيير مخزن الفاتورة المحفوظة' using errcode='42501';end if;
 else location:=coalesce(nullif(payload->>'warehouseId','')::bigint,solar_private.primary_warehouse());end if;
 if not solar_private.warehouse_access_allowed(auth.uid(),location) then raise exception 'لا تملك صلاحية مخزن الفاتورة' using errcode='42501';end if;
 perform set_config('solar.warehouse_id',location::text,true);
 if payload->>'kind' in('sale','system') and payload->>'invoiceId' is not null then select * into before_row from public.transactions where id=(payload->>'invoiceId')::bigint;end if;
 if payload->>'kind'='purchase' then perform set_config('solar.fx_context',case when payload ? 'marketRate' then payload::text else '{}' end,true);end if;
 select exists(select 1 from solar_private.invoice_requests r where r.request_id=invoice_save.request_id) into cached;
 if not cached and payload->>'kind' in('sale','system') then
  if before_row.id is not null then select coalesce(jsonb_agg(to_jsonb(i)),'[]') into old_lines from public.transaction_items i where transaction_id=before_row.id;end if;
  select array_agg(distinct id) into ids from(select (v->>'id')::bigint id from jsonb_array_elements(payload->'items')v union select (v->>'product_id')::bigint from jsonb_array_elements(old_lines)v)s;
  before_stock:=solar_private.valuation_stock_snapshot(ids);
  if payload->>'valuationRevision' is not null and (payload->>'valuationRevision')::bigint is distinct from(select revision from solar_private.exchange_settings where id) then raise exception 'تغير سعر الصرف؛ تم تحديث الكلفة، راجع الربح وأعد الحفظ' using errcode='PT409';end if;
 end if;
 if not cached and payload ? 'approvedInstallationExpenses' then
  if before_row.id is null or before_row.kind<>'system' or payload->>'kind'<>'system' then raise exception 'تعديل مصاريف التنصيب خاص بفاتورة منظومة محفوظة' using errcode='22023';end if;
  if jsonb_typeof(payload->'approvedInstallationExpenses') is distinct from 'number' then raise exception 'أدخل مصاريف تنصيب صحيحة' using errcode='22023';end if;
  approved_expenses:=(payload->>'approvedInstallationExpenses')::numeric;
  if approved_expenses::text in('NaN','Infinity','-Infinity') or approved_expenses<0 or approved_expenses>1000000000 or round(approved_expenses,2)<>approved_expenses then raise exception 'أدخل مصاريف تنصيب صحيحة' using errcode='22023';end if;
  expense_change:=approved_expenses is distinct from coalesce(before_row.installation_expenses,0) or approved_expenses is distinct from -(select coalesce(sum(e.delta),0)from public.solar_cash_entries e where e.job_id=before_row.id);
  if expense_change and not coalesce(solar_private.can_close_installation(before_row.created_by),false) then raise exception 'لا تملك صلاحية اعتماد مصاريف هذه المنظومة' using errcode='42501';end if;
  if expense_change and (before_row.profit_settlement_id is not null or before_row.profit_supplier_settlement_id is not null) then raise exception 'أرباح الفاتورة مسوّاة؛ راجع الإدارة قبل تغيير مصاريفها' using errcode='PT409';end if;
 end if;
 invoice_result:=solar_private.invoice_save_v333(request_id,payload);
 if not cached and payload->>'kind' in('sale','system') then
  select coalesce(jsonb_agg(to_jsonb(i)),'[]') into new_lines from public.transaction_items i where transaction_id=(invoice_result->>'id')::bigint;
  perform solar_private.valuation_reconcile_sale(before_stock,old_lines,new_lines);
 end if;
 if not cached and expense_change then
  perform solar_private.post_installation_cash(before_row.id,approved_expenses,auth.uid());
  update public.transactions set installation_expenses=approved_expenses,
   profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0)-approved_expenses
  where id=before_row.id;
  select * into after_row from public.transactions where id=before_row.id;
  invoice_result:=invoice_result||jsonb_build_object('profit',after_row.profit,'installationExpenses',after_row.installation_expenses,
   'installationPaidExpenses',-(select coalesce(sum(e.delta),0)from public.solar_cash_entries e where e.job_id=before_row.id),
   'installationRevision',after_row.installation_revision);
  update solar_private.invoice_requests set result=invoice_result where invoice_requests.request_id=invoice_save.request_id;
 end if;
 perform set_config('solar.fx_context','',true);perform set_config('solar.warehouse_id','',true);
 if before_row.id is not null then
  select * into after_row from public.transactions where id=before_row.id;
  if before_row.cash is not distinct from after_row.cash and not exists(select 1 from solar_private.receipt_change_audit a where a.request_id=invoice_save.request_id) then
   insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row) values(request_id,auth.uid(),before_row.id,'invoice_edit',to_jsonb(before_row),to_jsonb(after_row));
  end if;
  if before_row.cash is distinct from after_row.cash then
   insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row) values(request_id,auth.uid(),before_row.id,'sale_payment_mode',to_jsonb(before_row),to_jsonb(after_row));
  end if;
 end if;
 return invoice_result;
end $function$
;

CREATE OR REPLACE FUNCTION solar_private.installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; j public.transactions; amount numeric; e jsonb; report jsonb;
begin
 if solar_private.role_name()='warehouse' then raise exception 'Not permitted' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 select * into j from public.transactions where id=job_id and kind='system' for update;
 if j.id is null then raise exception 'Job unavailable' using errcode='42501'; end if;
 if p.user_type='installer' then
  if j.installer_id is distinct from p.id or action not in ('start','complete') then raise exception 'Not permitted' using errcode='42501'; end if;
 else
  if not (solar_private.can_close_installation(j.created_by)) or action not in ('close','reopen','clear_expenses') then raise exception 'Not permitted' using errcode='42501'; end if;
 end if;
 if expected_revision is distinct from j.installation_revision then raise exception 'Job changed; refresh and retry' using errcode='PT409'; end if;
 if action in('start','complete','close') and j.warehouse_status<>'ready' then raise exception 'يجب تجهيز مواد المنظومة قبل اعتماد المصاريف وإغلاق الملف أو بدء التنصيب';end if; if action='start' then
  if j.installation_status<>'pending' then raise exception 'Invalid stage'; end if;
  update public.transactions set installation_status='in_progress',installation_started_at=now(),installation_revision=installation_revision+1 where id=j.id;
 elsif action='complete' then
  if j.installation_status<>'in_progress' then raise exception 'Start the installation first'; end if;
  if jsonb_typeof(payload) is distinct from 'object' or length(trim(coalesce(payload->>'notes','')))=0 or length(payload->>'notes')>4000 then raise exception 'Completion report required'; end if;
  if payload->'checks'->>'materials' is distinct from 'true' or payload->'checks'->>'tested' is distinct from 'true' or payload->'checks'->>'handover' is distinct from 'true' then raise exception 'Complete the checklist'; end if;
  if jsonb_typeof(payload->'expenses') is distinct from 'array' then raise exception 'Invalid expenses'; end if;
  if jsonb_array_length(payload->'expenses')>50 then raise exception 'Too many expense lines'; end if;
  amount:=0;
  for e in select value from jsonb_array_elements(payload->'expenses') loop
   if jsonb_typeof(e->'amount') is distinct from 'number' or (e->>'amount')::numeric<=0 or (e->>'amount')::numeric>1000000000 or length(trim(coalesce(e->>'description','')))=0 or length(e->>'description')>500 then raise exception 'Invalid expense line'; end if;
   amount:=amount+(e->>'amount')::numeric;
  end loop;
  report:=jsonb_build_object('notes',trim(payload->>'notes'),'checks',payload->'checks','expenses',payload->'expenses','expenseTotal',amount,'submittedAt',now(),'submittedBy',p.id);
  update public.transactions set installation_status='completed',installation_completed_at=now(),installation_report=report,installation_revision=installation_revision+1 where id=j.id;
 elsif action='close' then
  if j.installation_status not in('pending','in_progress','completed') then raise exception 'الملف مغلق مسبقاً؛ افتحه للمراجعة قبل تعديل المصاريف';end if;
  if jsonb_typeof(payload->'amount') is distinct from 'number' then raise exception 'Invalid approved expenses'; end if;
  amount:=(payload->>'amount')::numeric;
  if amount::text in('NaN','Infinity','-Infinity') or round(amount,2)<>amount or amount<0 or amount>1000000000 then raise exception 'Invalid approved expenses'; end if;
  if length(coalesce(payload->>'notes',''))>4000 then raise exception 'Notes too long'; end if;
  perform solar_private.post_installation_cash(j.id,amount,p.id);
  update public.transactions set installation_status='closed',installation_closed_at=now(),installation_expenses=amount,installation_expense_notes=payload->>'notes',profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0)-amount,installation_revision=installation_revision+1 where id=j.id;
 elsif action='clear_expenses' then
  if j.installation_status='closed' then raise exception 'افتح الملف للمراجعة أولاً لإلغاء المصاريف';end if;
  if j.profit_settlement_id is not null or j.profit_supplier_settlement_id is not null then raise exception 'أرباح الفاتورة مسوّاة؛ راجع الإدارة قبل إلغاء مصاريفها' using errcode='PT409';end if;
  if length(coalesce(payload->>'notes',''))>4000 then raise exception 'Notes too long';end if;
  perform solar_private.post_installation_cash(j.id,0,p.id);
  update public.transactions set installation_expenses=0,installation_expense_notes=coalesce(nullif(payload->>'notes',''),'إلغاء مصاريف التنصيب المعتمدة'),
   profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0),installation_revision=installation_revision+1 where id=j.id;
  insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)
   select gen_random_uuid(),p.id,j.id,'installation_expenses_cancelled',to_jsonb(j),to_jsonb(t) from public.transactions t where t.id=j.id;
 elsif action='reopen' then
  if j.installation_status<>'closed' then raise exception 'Only closed files can reopen'; end if;
  update public.transactions set installation_status='completed',installation_closed_at=null,installation_revision=installation_revision+1 where id=j.id;
 else raise exception 'Invalid action'; end if;
end $function$
;
notify pgrst,'reload schema';


-- A statement retains dated cash flows while identifying cancelled expenses.
do $$declare d text;needle text;begin
 d:=pg_get_functiondef('solar_private.cash_statement(uuid,date,date,text)'::regprocedure);
 needle:='coalesce(t.payment_mode,j.payment_mode) payment_mode,';
 if strpos(d,needle)=0 then raise exception 'Statement expense metadata contract missing';end if;
 d:=replace(d,needle,needle||'j.installation_expenses current_expenses,paid.net current_paid,');
 needle:='left join public.transactions j on j.id=e.job_id';
 if strpos(d,needle)=0 then raise exception 'Statement expense source contract missing';end if;
 execute replace(d,needle,needle||' left join(select job_id,-sum(delta)net from public.solar_cash_entries where job_id is not null group by job_id)paid on paid.job_id=e.job_id');
end$$;
notify pgrst,'reload schema';
