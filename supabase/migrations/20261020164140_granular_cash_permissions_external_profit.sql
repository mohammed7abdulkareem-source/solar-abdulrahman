-- Cash viewing and each posting action are separate, explicitly granted rights.
-- Staff administration is restricted to their own cashbox. Existing financial
-- rows and permissions are not rewritten by this migration.
create function solar_private.cash_allowed(permission text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select p.is_admin or case when permission='view' then
  exists(select 1 from jsonb_each_text(p.permissions) e where e.key in('cash','cashDeposit','cashExpense','cashExchange','cashExternalProfit','cashAdminTools','cashTransferSend','financeReceive') and e.value='true')
  else coalesce(p.permissions->>permission,'false')='true' end
 from public.profiles p where p.id=auth.uid() and p.active and p.user_type not in('warehouse','installer')),false)
$$;
revoke all on function solar_private.cash_allowed(text) from public,anon,authenticated;
alter table public.transactions drop constraint transactions_cash_purpose_check;
alter table public.transactions add constraint transactions_cash_purpose_check check(cash_purpose in('income','expense','capital','withdrawal','external_profit'));

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure);
 old:=$old$not(p.is_admin or coalesce(p.permissions->>'cash','false')='true')$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_workspace(jsonb)';end if;
 d:=replace(d,old,$new$not solar_private.cash_allowed('view')$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.cash_receipt(uuid)'::regprocedure);
 old:=$old$not(p.is_admin or coalesce(p.permissions->>'cash','false')='true')$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_receipt(uuid)';end if;
 d:=replace(d,old,$new$not solar_private.cash_allowed('view')$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.cash_save(uuid,jsonb)'::regprocedure);
 old:=$old$not(p.is_admin or coalesce(p.permissions->>'cash','false')='true')$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_save(uuid,jsonb)';end if;
 d:=replace(d,old,$new$not solar_private.cash_allowed('view')$new$);
 old:=$old$'sell_usd','distribution')$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_save(uuid,jsonb)';end if;
 d:=replace(d,old,$new$'sell_usd','distribution','external_profit')$new$);
 old:=$old$if mode in ('capital_deposit','capital_withdraw','distribution') and not p.is_admin then raise exception 'هذه الحركة للمدير فقط' using errcode='42501';end if;$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_save(uuid,jsonb)';end if;
 d:=replace(d,old,$new$if not solar_private.cash_allowed(case mode when 'deposit' then 'cashDeposit' when 'expense' then 'cashExpense' when 'external_profit' then 'cashExternalProfit' when 'capital_deposit' then 'cashAdminTools' when 'capital_withdraw' then 'cashAdminTools' when 'distribution' then 'adminOnly' else 'cashExchange' end) then raise exception 'لا تملك صلاحية هذه العملية في الصندوق' using errcode='42501';end if; if mode='distribution' and not p.is_admin then raise exception 'توزيع أرباح الإدارة للمدير فقط' using errcode='42501';end if;$new$);
 old:=$old$if cur='USD' and mode='deposit' and not p.is_admin then raise exception 'إضافة رصيد دولار للمدير فقط؛ استخدم الصرافة لشراء الدولار' using errcode='42501';end if;$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_save(uuid,jsonb)';end if;
 d:=replace(d,old,$new$$new$);
 old:=$old$purpose:=case mode when 'expense' then 'expense'$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_save(uuid,jsonb)';end if;
 d:=replace(d,old,$new$purpose:=case mode when 'external_profit' then 'external_profit' when 'expense' then 'expense'$new$);
 old:=$old$'requestId',request_id,'mode',mode$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_save(uuid,jsonb)';end if;
 d:=replace(d,old,$new$'profitAmountIQD',case when mode='external_profit' then value_iqd end,'requestId',request_id,'mode',mode$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.fx(text,uuid,jsonb)'::regprocedure);
 old:=$old$not(p.is_admin or coalesce(p.permissions->>'cash','false')='true')$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.fx(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$not solar_private.cash_allowed('view')$new$);
 old:=$old$amt:=(payload->>'amount')::numeric;mode:=payload->>'mode';r:=solar_private.fx_rate((payload->>'rate')::numeric);$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.fx(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$amt:=(payload->>'amount')::numeric;mode:=payload->>'mode';
  if not solar_private.cash_allowed(case when mode in('deposit','withdraw') then 'cashAdminTools' else 'cashExchange' end) then raise exception 'لا تملك صلاحية الصرافة أو أدوات القاصة' using errcode='42501';end if;
  r:=solar_private.fx_rate((payload->>'rate')::numeric);$new$);
 old:=$old$if mode in ('deposit','withdraw') and not p.is_admin then raise exception 'إضافة أو سحب رأس مال الدولار للمدير فقط' using errcode='42501';end if;$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.fx(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.cash_transfer_send(uuid,uuid,numeric,numeric,text,text)'::regprocedure);
 old:=$old$if solar_private.cash_balance(p.id)<send_amount+expense_amount$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_transfer_send(uuid,uuid,numeric,numeric,text,text)';end if;
 d:=replace(d,old,$new$if expense_amount>0 and not solar_private.cash_allowed('cashExpense') then raise exception 'تسجيل مصروف قبل التسليم يحتاج صلاحية المصروف' using errcode='42501';end if;
 if solar_private.cash_balance(p.id)<send_amount+expense_amount$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.cash_reconcile(text,uuid,jsonb)'::regprocedure);
 old:=$old$where id=auth.uid() and active and is_admin;$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_reconcile(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$where id=auth.uid() and active and user_type not in('warehouse','installer') and solar_private.cash_allowed('cashAdminTools');$new$);
 old:=$old$تعديل وتصفير القاصات متاح للأدمن فقط$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_reconcile(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$لا تملك صلاحية أدوات إدارة القاصة$new$);
 old:=$old$uid:=nullif(payload->>'ownerId','')::uuid;$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_reconcile(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$uid:=nullif(payload->>'ownerId','')::uuid;
 if not actor.is_admin and(uid is null or uid<>actor.id) then raise exception 'أدوات الإدارة متاحة على قاصتك فقط' using errcode='42501';end if;$new$);
 old:=$old$where u.user_type not in ('installer','warehouse') or b.owner_id is not null or u.id=uid;$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_reconcile(text,uuid,jsonb)';end if;
 d:=replace(d,old,$new$where (u.user_type not in ('installer','warehouse') or b.owner_id is not null or u.id=uid) and(actor.is_admin or u.id=actor.id);$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.cash_movements()'::regprocedure);
 old:=$old$case t.cash_purpose when 'capital'$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.cash_movements()';end if;
 d:=replace(d,old,$new$case t.cash_purpose when 'external_profit' then 'external_profit' when 'capital'$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.profit_rows(uuid)'::regprocedure);
 old:=$old$t.created_at date,t.kind,case when$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.profit_rows(uuid)';end if;
 d:=replace(d,old,$new$t.created_at date,case when t.cash_purpose='external_profit' then 'external_profit' else t.kind end kind,case when t.cash_purpose='external_profit' then 'أرباح خارجية · '||coalesce(t.notes,'') when$new$);
 old:=$old$round(case when t.kind='system'$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.profit_rows(uuid)';end if;
 d:=replace(d,old,$new$round(case when t.cash_purpose='external_profit' then t.total when t.kind='system'$new$);
 old:=$old$or t.cash_purpose='expense')$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.profit_rows(uuid)';end if;
 d:=replace(d,old,$new$or t.cash_purpose in('expense','external_profit'))$new$);
 execute d;
end $patch$;

do $patch$declare d text;old text;begin
 d:=pg_get_functiondef('solar_private.retained_profit(uuid)'::regprocedure);
 old:=$old$
$function$$old$;
 if strpos(d,old)=0 then raise exception 'Review cash permission migration anchor: solar_private.retained_profit(uuid)';end if;
 d:=replace(d,old,$new$
 +coalesce((select sum(t.total) from public.transactions t where t.cash_purpose='external_profit' and coalesce(t.cashbox_user_id,t.created_by)=uid),0)
$function$$new$);
 execute d;
end $patch$;

notify pgrst,'reload schema';
