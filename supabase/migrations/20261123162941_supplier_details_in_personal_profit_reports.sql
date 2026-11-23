-- Keep personal settlements and exchange gains in the user's profit account.
-- Their receipt references and supplier-side terms follow statement access.
create or replace function solar_private.profit_read_projection(value jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare result jsonb:=value; name text; source_key text; wallet_type text;
begin
 if value is null or solar_private.can_access_invoice(null,false) then return value;end if;
 if jsonb_typeof(value)='array' then
  select coalesce(jsonb_agg(solar_private.profit_read_projection(x.value) order by x.ordinality),'[]'::jsonb) into result from jsonb_array_elements(value) with ordinality x;
 elsif jsonb_typeof(value)='object' then
  foreach name in array array['rows','snapshot','requests','movement'] loop
   if value ? name then result:=jsonb_set(result,array[name],solar_private.profit_read_projection(value->name));end if;
  end loop;
  source_key:=value->>'key';
  if (value ? 'supplier_receipt' or source_key ~ '^(supplierfx|walletfx):-?[0-9]+$')
    and not solar_private.any_feature(solar_private.office_features(),'supplierStatement') then
   if value ? 'supplier_receipt' then
    result:=result-array['supplier_id','supplier_amount','supplier_currency','supplier_rate','supplier_receipt'];
   elsif source_key like 'walletfx:%' then
    select w.entry_type into wallet_type from solar_private.wallet_fx_entries w where w.id=substr(source_key,10)::bigint;
    -- A checkpoint can survive its source. In that case an archived note
    -- cannot be identified as safe, but the recorded gain still belongs here.
    if wallet_type is null or wallet_type in('supplier_cash','supplier_payment_refund','purchase_refund','purchase_correction') then
     result:=result||jsonb_build_object('label','فرق صرف قاصة','receiptNo',null);
    end if;
   else
    result:=result||jsonb_build_object('label','فرق صرف مورد','receiptNo',null);
   end if;
  end if;
  if source_key ~ '^tx:-?[0-9]+$' and value->>'kind' in('sale','system') and not solar_private.invoice_read_allowed(substr(source_key,4)::bigint) then
   select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) into result from jsonb_each(value) as x(k,v)
   where k=any(array['date','kind','value','settled','available','deleted','ownerId']);
   result:=result||jsonb_build_object('key','restricted:'||md5(auth.uid()::text||':'||source_key),
    'receiptNo',null,'label','ربح محوّل إلى حسابك','receiptRestricted',true);
  end if;
 end if;
 return result;
end $function$;
