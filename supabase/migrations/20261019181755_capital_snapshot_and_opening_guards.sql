-- Capital is a read-only reconciliation of the existing ledgers. No balance,
-- historical debt, exchange rate, stock cost or cash entry is changed here.
create function solar_private.capital_snapshot() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; company boolean; stock jsonb; customer_rows jsonb; supplier_rows jsonb;
 cash_rows jsonb; opening_rows jsonb; stock_value numeric; iqd numeric; usd numeric; usd_book numeric;
 receivable numeric; advances numeric; payable numeric; prepayments numeric;
 opening_customer numeric; opening_supplier numeric; flows numeric; assets numeric; liabilities numeric; net numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in('warehouse','installer') or not(p.is_admin or coalesce(p.permissions->'capital'='true'::jsonb,false)) then
  raise exception 'لا تملك صلاحية عرض رأس المال' using errcode='42501';
 end if;
 company:=p.is_admin;
 stock:=solar_private.inventory_catalog(null);
 select coalesce(sum((v->>'bookQty')::numeric*coalesce((v->>'cost')::numeric,0)),0)
 into stock_value from jsonb_array_elements(stock) v where (v->>'bookQty')::numeric>0;

 -- Resolve legacy names only when they identify exactly one registered party.
 -- Keep unresolved balances visible instead of silently discarding them.
 with movements as (
  select coalesce(t.party_id,c.id) party_id,coalesce(c.name,t.party_name,'غير محدد') name,coalesce(c.phone,'') phone,
   case when t.kind in('customer_payment','system_payment') then -t.total when t.kind='sale' and t.cash then 0 else t.total end delta
  from public.transactions t left join public.customers c on
   c.id=t.party_id or(t.party_id is null and solar_private.customer_name_key(c.name)=solar_private.customer_name_key(t.party_name)
    and(select count(*) from public.customers z where solar_private.customer_name_key(z.name)=solar_private.customer_name_key(t.party_name))=1)
  where t.kind in('sale','system','customer_payment','system_payment') and(company or t.created_by=p.id)
 ), grouped as (
  select party_id,name,phone,round(sum(delta),2) balance from movements group by party_id,name,phone
 ) select coalesce(jsonb_agg(jsonb_build_object('id',party_id,'name',name,'phone',phone,'balance',balance) order by balance desc,name),'[]')
 into customer_rows from grouped where balance<>0;

 -- Current currency revision is authoritative. Old conversion closing entries
 -- are not added to the new currency opening a second time. Book value stays IQD.
 with postings as (
  select s.id party_id,s.name,s.phone,s.account_currency currency,e.delta amount,e.book_delta delta
  from solar_private.supplier_fx_entries e join public.suppliers s on s.id=e.supplier_id and s.currency_revision=e.revision
  where company or e.owner_id=p.id
  union all
  select coalesce(t.party_id,s.id),coalesce(s.name,t.party_name,'غير محدد'),coalesce(s.phone,''),case when t.fx_accounted then t.account_currency else 'IQD' end,
   case when t.kind='supplier_payment' then -case when t.fx_accounted then t.account_amount else t.total end when t.cash then 0 when t.fx_accounted then t.account_amount else t.total end,
   case when t.kind='supplier_payment' then -t.total when t.cash then 0 else t.total end
  from public.transactions t left join public.suppliers s on
   s.id=t.party_id or(t.party_id is null and solar_private.customer_name_key(s.name)=solar_private.customer_name_key(t.party_name)
    and(select count(*) from public.suppliers z where solar_private.customer_name_key(z.name)=solar_private.customer_name_key(t.party_name))=1)
  where t.kind in('purchase','supplier_payment') and t.supplier_payment_voided_at is null and(company or t.created_by=p.id)
   and not exists(select 1 from solar_private.supplier_fx_entries e where e.transaction_id=t.id)
 ), grouped as (
  select party_id,name,phone,currency,round(sum(amount),2) amount,round(sum(delta),2) balance
  from postings group by party_id,name,phone,currency
 ) select coalesce(jsonb_agg(jsonb_build_object('id',party_id,'name',name,'phone',phone,'currency',currency,'amount',amount,'balance',balance) order by balance desc,name),'[]')
 into supplier_rows from grouped where balance<>0 or amount<>0;

 with movements as (
  select m.*,coalesce(u.display_name,u.username,'قاصة غير محددة') owner_name from solar_private.cash_movements() m
  left join public.profiles u on u.id=m.owner_id where company or m.owner_id=p.id
 ) select coalesce(sum(delta) filter(where currency='IQD'),0),coalesce(sum(delta) filter(where currency='USD'),0),
  coalesce(sum(book_delta) filter(where currency='USD'),0),
  coalesce(sum(case when currency='IQD' then delta else book_delta end) filter(where kind in('capital_deposit','capital_withdraw','deposit','withdraw')),0),
  coalesce(jsonb_agg(jsonb_build_object('id',id,'ownerId',owner_id,'ownerName',owner_name,'currency',currency,'delta',delta,'bookDelta',book_delta,
   'kind',kind,'party',party,'notes',note,'receiptNo',receipt_no,'date',created_at) order by created_at,id),'[]')
 into iqd,usd,usd_book,flows,cash_rows from movements;

 with openings as (
  select t.id,t.kind,t.payment_mode,t.receipt_no,t.party_name,t.created_at,t.notes,t.source_currency,t.source_subtotal,t.total,
   coalesce(u.display_name,u.username,'غير محدد') creator_name,
   case when t.kind='supplier_payment' then 'supplier' else 'customer' end party_type,-t.total effect
  from public.transactions t left join public.profiles u on u.id=t.created_by
  where not t.cash and t.kind in('supplier_payment','customer_payment','system_payment')
   and t.payment_mode in('opening_balance','charge_old_balance') and t.supplier_payment_voided_at is null
   and(company or t.created_by=p.id)
 ) select coalesce(sum(effect) filter(where party_type='customer'),0),coalesce(sum(effect) filter(where party_type='supplier'),0),
  coalesce(jsonb_agg(jsonb_build_object('id',id,'partyType',party_type,'party',party_name,'receiptNo',receipt_no,'date',created_at,'notes',notes,
   'creatorName',creator_name,'sourceCurrency',source_currency,'sourceAmount',abs(coalesce(source_subtotal,total)),'amount',effect) order by created_at,id),'[]')
 into opening_customer,opening_supplier,opening_rows from openings;

 select coalesce(sum(greatest((v->>'balance')::numeric,0)),0),coalesce(sum(greatest(-(v->>'balance')::numeric,0)),0)
 into receivable,advances from jsonb_array_elements(customer_rows) v;
 select coalesce(sum(greatest((v->>'balance')::numeric,0)),0),coalesce(sum(greatest(-(v->>'balance')::numeric,0)),0)
 into payable,prepayments from jsonb_array_elements(supplier_rows) v;
 assets:=round(stock_value+iqd+usd_book+receivable+prepayments,2);
 liabilities:=round(payable+advances,2);net:=assets-liabilities;
 return jsonb_build_object('asOf',statement_timestamp(),'scope',case when company then 'company' else 'own' end,'currency','IQD',
  'stock',jsonb_build_object('value',round(stock_value,2),'rows',stock),
  'cash',jsonb_build_object('iqd',round(iqd,2),'usd',round(usd,2),'usdBook',round(usd_book,2),'rows',cash_rows),
  'customers',jsonb_build_object('receivable',receivable,'advances',advances,'net',receivable-advances,'rows',customer_rows),
  'suppliers',jsonb_build_object('payable',payable,'prepayments',prepayments,'net',payable-prepayments,'rows',supplier_rows),
  'assets',assets,'liabilities',liabilities,'net',net,
  'opening',jsonb_build_object('customerNet',opening_customer,'supplierNet',opening_supplier,'net',opening_customer-opening_supplier,'rows',opening_rows),
  'capitalFlows',round(flows,2),'otherMovements',round(net-(opening_customer-opening_supplier)-flows,2));
end $$;
revoke all on function solar_private.capital_snapshot() from public,anon;
grant execute on function solar_private.capital_snapshot() to authenticated;
create function public.solar_capital_snapshot() returns jsonb language sql stable set search_path='' as $$
 select solar_private.capital_snapshot()
$$;
revoke all on function public.solar_capital_snapshot() from public,anon;
grant execute on function public.solar_capital_snapshot() to authenticated;

-- An identical old-balance entry is usually a double click/re-entry. Distinct
-- documented old debts remain valid. Existing entries are never rewritten.
create index solar_old_balance_lookup on public.transactions
 (kind,payment_mode,source_currency,(coalesce(source_subtotal,total)),party_id)
 where not cash and supplier_payment_voided_at is null
 and kind in('customer_payment','system_payment','supplier_payment')
 and payment_mode in('opening_balance','charge_old_balance');
create function solar_private.guard_duplicate_old_balance() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or new.cash or new.total=0 or new.supplier_payment_voided_at is not null
  or new.kind not in('customer_payment','system_payment','supplier_payment')
  or coalesce(new.payment_mode,'') not in('opening_balance','charge_old_balance') then return new;end if;
 perform pg_advisory_xact_lock(7311,1);
 if exists(select 1 from public.transactions t where t.id<>new.id and t.kind=new.kind and not t.cash
  and t.supplier_payment_voided_at is null and t.payment_mode=new.payment_mode
  and ((new.party_id is not null and t.party_id=new.party_id)
   or((new.party_id is null or t.party_id is null) and solar_private.customer_name_key(t.party_name)=solar_private.customer_name_key(new.party_name)))
  and sign(t.total)=sign(new.total) and t.source_currency=new.source_currency
  and coalesce(t.source_subtotal,t.total)=coalesce(new.source_subtotal,new.total)
  and regexp_replace(trim(coalesce(t.notes,'')),'\s+',' ','g')=regexp_replace(trim(coalesce(new.notes,'')),'\s+',' ','g')
 ) then raise exception 'يوجد حساب قديم مماثل لهذا الطرف بنفس المبلغ والبيان. راجع القيد السابق أو اكتب بياناً يميز الدين المستقل. لم يتم الحفظ.' using errcode='PT409';end if;
 return new;
end $$;
revoke all on function solar_private.guard_duplicate_old_balance() from public,anon,authenticated;
create trigger solar_zzzz_old_balance_duplicate before insert or update on public.transactions
 for each row execute function solar_private.guard_duplicate_old_balance();
notify pgrst,'reload schema';
