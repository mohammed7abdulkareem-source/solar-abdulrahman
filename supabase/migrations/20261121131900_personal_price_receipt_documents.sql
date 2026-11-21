-- These projections are applied after the receipt's existing ownership, scope,
-- and action checks. The stored warehouse valuation and deletion audit stay intact.
create function solar_private.personal_archive_priced(receipt_id bigint) returns boolean
language sql stable security invoker set search_path='' as $$
 select solar_private.personal_price_enabled(auth.uid()) or exists (
  select 1 from solar_private.personal_price_receipts r
  join public.profiles p on p.id=r.source_user_id
  where r.invoice_id=$1 and p.id=auth.uid() and not p.is_admin
 )
$$;
revoke all on function solar_private.personal_archive_priced(bigint) from public,anon,authenticated;

create function solar_private.personal_archive_line(receipt_id bigint, product_id bigint, document jsonb)
returns jsonb language sql stable security invoker set search_path='' as $$
 select case when not solar_private.personal_archive_priced(receipt_id) then document else
    (document - array['cost','cost_basis','landed_cost','source_price'])
    || jsonb_build_object('personalPriceBasis',true,'cost',solar_private.personal_line_cost(receipt_id,product_id,null),
                          'personalCostHidden',not solar_private.personal_line_has_price(receipt_id,product_id))
 end
$$;

create function solar_private.personal_archive_header(receipt_id bigint, document jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare t public.transactions; visible_cost numeric; personal_profit numeric;
begin
 if document is null then return null;end if;
 if solar_private.personal_receipt_priced(receipt_id) then
  document:=document||jsonb_build_object('personalBasisAtSale',true);
 end if;
 if not solar_private.personal_archive_priced(receipt_id) then return document;end if;
 select * into t from public.transactions where id=receipt_id and kind in ('sale','system') and created_by=auth.uid();
 if found then
  personal_profit:=solar_private.receipt_profit_on_basis(t,true);
  if solar_private.personal_receipt_priced(t.id) and not exists (select 1 from public.transaction_items i where i.transaction_id=t.id
   and not solar_private.personal_line_has_price(t.id,i.product_id)) then
   visible_cost:=solar_private.personal_material_cost(t.id,t.cost);
  end if;
 end if;
 return (document - array['cost','profit','purchase_stock'])
     || jsonb_build_object('cost',visible_cost,'profit',personal_profit,'personalPriceBasis',true,'personalCostHidden',visible_cost is null);
end
$$;
revoke all on function solar_private.personal_archive_line(bigint,bigint,jsonb),
 solar_private.personal_archive_header(bigint,jsonb) from public,anon,authenticated;

-- Both versions of the sales archive dispatch to this scoped implementation.
do $migration$
declare original text:=pg_get_functiondef('solar_private.sales_work_history(text,text,date,date,text,integer,uuid,boolean)'::regprocedure);definition text;
 a constant text:='then to_jsonb(t)-''assigned_to'' else';
 b constant text:='then to_jsonb(i)'||chr(10);
begin
 if strpos(original,a)=0 or strpos(original,b)=0 then raise exception 'Review sale archive projection before installing personal prices';end if;
 definition:=replace(original,a,'then solar_private.personal_archive_header(t.id,to_jsonb(t)-''assigned_to'') else');
 execute replace(definition,b,'then solar_private.personal_archive_line(t.id,i.product_id,to_jsonb(i))'||chr(10));
end $migration$;

-- The original public join depended on raw table RLS. Selected staff now read
-- the scoped document through a definer so the ordinary statement editor keeps
-- working when direct transaction/item reads are disabled.
do $migration$
declare source text:=pg_get_functiondef('public.solar_statement_sale_for_edit(bigint,bigint)'::regprocedure);
 old text:='jsonb_agg(jsonb_build_object(''product_id'',i.product_id,''product_name'',i.product_name,';
 ending text:='''cost'',i.cost) order by i.id)';
begin
 if strpos(source,old)=0 or strpos(source,ending)=0 or strpos(source,'t.created_by=auth.uid()')=0 then
  raise exception 'Review customer-statement edit document scope';end if;
 source:=replace(source,'public.solar_statement_sale_for_edit','solar_private.statement_sale_for_edit');
 source:=replace(source,'LANGUAGE sql','LANGUAGE sql SECURITY DEFINER');
 source:=replace(source,'''party_id'',c.id','''personalBasisAtSale'',solar_private.personal_receipt_priced(t.id),''party_id'',c.id');
 source:=replace(source,old,'jsonb_agg(solar_private.personal_archive_line(t.id,i.product_id,jsonb_build_object(''product_id'',i.product_id,''product_name'',i.product_name,');
 execute replace(source,ending,'''cost'',i.cost)) order by i.id)');
end $migration$;
revoke all on function solar_private.statement_sale_for_edit(bigint,bigint) from public,anon;
grant execute on function solar_private.statement_sale_for_edit(bigint,bigint) to authenticated;
create or replace function public.solar_statement_sale_for_edit(customer_id bigint,movement_id bigint)
returns jsonb language sql stable security invoker set search_path='' as $$
 select solar_private.statement_sale_for_edit(customer_id,movement_id)
$$;

-- The deletion dialog uses the saved full-document token, but its staff copy
-- needs only identifiers, item quantities, cash effects and sale prices.
create function solar_private.personal_deletion_document(doc jsonb) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
declare visible_lines jsonb; key text;
begin
 if doc is null or jsonb_typeof(doc)<>'object' then return doc;end if;
 foreach key in array array['current','snapshot'] loop
  if jsonb_typeof(doc->key)='object' then
   doc:=jsonb_set(doc,array[key],solar_private.personal_deletion_document(doc->key));
  end if;
 end loop;
 if doc ? 'invoice' then
  doc:=jsonb_set(doc,'{invoice}',(doc->'invoice')-'cost'-'profit'-'purchase_stock');
 end if;
 if jsonb_typeof(doc->'items')='array' then
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id',x->'id','product_id',x->'product_id',
    'product_name',x->'product_name','brand_name',x->'brand_name','category',x->'category','qty',x->'qty',
    'price',case when doc->>'kind'='sale' then x->'price' end)) order by ord),'[]'::jsonb)
  into visible_lines from jsonb_array_elements(doc->'items') with ordinality l(x,ord);
  doc:=jsonb_set(doc,'{items}',visible_lines);
 end if;
 return doc-'purchaseCancellation';
end
$$;
revoke all on function solar_private.personal_deletion_document(jsonb) from public,anon,authenticated;

alter function solar_private.receipt_delete_requests(text,uuid,jsonb) rename to receipt_delete_requests_v4124;
do $rename$
declare original text:=pg_get_functiondef('solar_private.receipt_delete_requests_v4124(text,uuid,jsonb)'::regprocedure);
begin
 -- Its PL/pgSQL parameter references use the original implicit function label.
 execute replace(original,'receipt_delete_requests.request_id','receipt_delete_requests_v4124.request_id');
end $rename$;
revoke all on function solar_private.receipt_delete_requests_v4124(text,uuid,jsonb) from public,anon,authenticated;
create function solar_private.receipt_delete_requests(action text,request_id uuid default null,payload jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=solar_private.receipt_delete_requests_v4124(action,request_id,payload);
 if action in ('get','context') and solar_private.personal_archive_priced(
  case when action='context' then (result->>'id')::bigint else (result#>>'{snapshot,id}')::bigint end
 ) then
  result:=solar_private.personal_deletion_document(result);
 end if;
 return result;
end
$$;
revoke all on function solar_private.receipt_delete_requests(text,uuid,jsonb) from public,anon;
grant execute on function solar_private.receipt_delete_requests(text,uuid,jsonb) to authenticated;

-- An original purchase cash entry is still money paid by this cashier. Its
-- receipt and balance remain usable; purchase unit prices are privileged.
do $migration$
declare source text:=pg_get_functiondef('solar_private.cash_movement_detail(text)'::regprocedure);
 anchor constant text:='return solar_private.cash_read_projection(result||';
begin
 if strpos(source,anchor)=0 then raise exception 'Review cash receipt detail projection';end if;
 execute replace(source,anchor,$new$
 if result#>>'{document,kind}'='purchase' and solar_private.personal_price_enabled(auth.uid()) then
  result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(item-'price'-'total' order by ordinal)
       from jsonb_array_elements(result->'items') with ordinality as l(item,ordinal)),'[]'::jsonb));
 end if;
 return solar_private.cash_read_projection(result||$new$);
end $migration$;
notify pgrst,'reload schema';
