-- Read-only, bounded lookups. Recheck the live profile and warehouse scope on every request.
create function solar_private.quick_search_key(value text) returns text language sql immutable parallel safe set search_path='' as $$
 select trim(regexp_replace(lower(translate(regexp_replace(normalize(coalesce(value,''),NFKC),'[ً-ٰٟـ]','','g'),
 'أإآٱى٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','ااااي01234567890123456789')),'[[:space:]]+',' ','g'))
$$;
create function solar_private.quick_search_matches(value text, words text[]) returns boolean language sql immutable parallel safe set search_path='' as $$
 select not exists(select 1 from unnest(words) w where strpos(solar_private.quick_search_key(value),w)=0)
$$;
revoke all on function solar_private.quick_search_key(text),solar_private.quick_search_matches(text,text[]) from public,anon,authenticated;

create index quick_search_item_product_idx on public.transaction_items(product_id,transaction_id);

create function solar_private.quick_search(term text,category text default 'all') returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='5s' as $$
#variable_conflict use_column
declare p public.profiles; words text[]; q text; n integer; allowed text[]:='{}';
 customers jsonb:='[]';products jsonb:='[]';suppliers jsonb:='[]'; more jsonb:='{}';
 financial boolean; customer_allowed boolean; stock_allowed boolean; supplier_allowed boolean;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null then raise exception 'سجّل الدخول للبحث' using errcode='42501';end if;
 if category is null or category not in('all','customers','products','suppliers') or term is null or length(term)>100 then raise exception 'بحث غير صحيح' using errcode='22023';end if;
 financial:=p.user_type not in('warehouse','installer');
 customer_allowed:=financial and(p.is_admin or p.permissions->>'customers'='true' or p.permissions->>'customerCreate'='true');
 supplier_allowed:=financial and(p.is_admin or p.permissions->>'suppliers'='true');
 stock_allowed:=p.user_type<>'installer' and(p.user_type='warehouse' or p.is_admin or p.permissions->>'stock'='true' or p.permissions->>'stockMovement'='true' or p.permissions->>'warehouse'='true' or p.permissions->>'sale'='true' or p.permissions->>'system'='true' or p.permissions->>'purchase'='true');
 if coalesce(customer_allowed,false) then allowed:=array_append(allowed,'customers');end if;
 if coalesce(stock_allowed,false) then allowed:=array_append(allowed,'products');end if;
 if coalesce(supplier_allowed,false) then allowed:=array_append(allowed,'suppliers');end if;
 q:=solar_private.quick_search_key(term);words:=string_to_array(q,' ');n:=case when category='all' then 6 else 20 end;
 if length(q)<2 then return jsonb_build_object('customers',customers,'products',products,'suppliers',suppliers,'more',more,'available',allowed);end if;
 if customer_allowed and category in('all','customers') then
  with matched as materialized(select c.id,c.name from public.customers c where c.active and(p.is_admin or c.owner_id=p.id)
   and solar_private.quick_search_matches(c.name||' '||coalesce(c.phone,'')||' '||solar_private.customer_phone_key(c.phone),words)
   order by (solar_private.quick_search_key(c.name)=q) desc,c.name,c.id limit n+1),
  page as(select id,name from matched limit n)
  select coalesce((select jsonb_agg(solar_private.customer_get(id)-'rows'-'token'-'openingCount'-'revision' order by name,id) from page),'[]'),
   more||jsonb_build_object('customers',(select count(*)>n from matched)) into customers,more;
 end if;
 if stock_allowed and category in('all','products') then
  with matched as materialized(select m.*,b.name brand from public.products m left join public.brands b on b.id=m.brand_id
   where exists(select 1 from solar_private.warehouses w where solar_private.warehouse_access_allowed(p.id,w.id))
   and solar_private.quick_search_matches(m.name||' '||coalesce(m.code,'')||' '||coalesce(b.name,'')||' '||coalesce(m.category,''),words)
   order by (solar_private.quick_search_key(m.code)=q) desc,(solar_private.quick_search_key(m.name)=q) desc,m.name,m.id limit n+1),
  page as(select * from matched limit n), rows as(
   select m.id,m.name,m.code,m.brand,m.category,
    (select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'active',w.active,'qty',coalesce(s.qty,0),'reserved',coalesce(s.reserved_qty,0)) order by w.is_primary desc,w.id),'[]')
     from solar_private.warehouses w left join solar_private.warehouse_stocks s on s.warehouse_id=w.id and s.product_id=m.id
     where solar_private.warehouse_access_allowed(p.id,w.id)) warehouses,
    case when financial then m.cost end cost,
    case when financial then(select jsonb_build_object('amount',i.price,'date',t.created_at,'currency','IQD') from public.transaction_items i join public.transactions t on t.id=i.transaction_id
     where i.product_id=m.id and t.kind in('sale','system') and(t.kind='sale' or i.price>0) and i.qty>0 and(p.is_admin or t.created_by=p.id)
      and solar_private.warehouse_access_allowed(p.id,t.warehouse_id) order by t.created_at desc,t.id desc,i.id desc limit 1) end last_sale
   from page m)
  select coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code,'brand',brand,'category',category,'warehouses',warehouses,
    'qty',(select coalesce(sum((w->>'qty')::numeric),0) from jsonb_array_elements(warehouses) w),
    'reserved',(select coalesce(sum((w->>'reserved')::numeric),0) from jsonb_array_elements(warehouses) w))||
     case when financial then jsonb_build_object('cost',cost,'lastSale',last_sale) else '{}'::jsonb end order by name,id) from rows),'[]'),
    more||jsonb_build_object('products',(select count(*)>n from matched)) into products,more;
 end if;
 if supplier_allowed and category in('all','suppliers') then
  with matched as materialized(select s.* from public.suppliers s
   where solar_private.quick_search_matches(s.name||' '||coalesce(s.phone,''),words)
   order by (solar_private.quick_search_key(s.name)=q) desc,s.name,s.id limit n+1),page as(select * from matched limit n)
  select coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'phone',s.phone,'currency',s.account_currency,
   'balance',coalesce((select sum(e.delta) from solar_private.supplier_fx_entries e where e.supplier_id=s.id and e.revision=s.currency_revision and(p.is_admin or e.owner_id=p.id)),0)) order by s.name,s.id) from page s),'[]'),
   more||jsonb_build_object('suppliers',(select count(*)>n from matched)) into suppliers,more;
 end if;
 return jsonb_build_object('customers',customers,'products',products,'suppliers',suppliers,'more',more,'available',allowed);
end$$;
create function public.solar_quick_search(term text,category text default 'all') returns jsonb
 language sql stable security invoker set search_path='' as $$select solar_private.quick_search(term,category)$$;
revoke all on function solar_private.quick_search(text,text),public.solar_quick_search(text,text) from public,anon;
grant execute on function solar_private.quick_search(text,text),public.solar_quick_search(text,text) to authenticated;
