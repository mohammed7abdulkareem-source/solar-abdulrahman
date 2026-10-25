-- Cash purchases paid in IQD may overdraw their owner's dinar cashbox.
-- Keep the signed ledger, owner checks, purchase costing and USD book basis intact.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.invoice_save_v333(uuid,jsonb)'::regprocedure);
 needle:=$n$if cash and kind='purchase' and coalesce(payload->>'cashCurrency','IQD')='IQD' and (total-case when existing and old_invoice.cash and old_invoice.cash_currency='IQD' then old_invoice.total else 0 end)>greatest(0,solar_private.cash_balance(owner_id)) then raise exception 'رصيد قاصة صاحب الفاتورة غير كافٍ' using errcode='P0002';end if;$n$;
 if strpos(definition,needle)=0 then raise exception 'IQD purchase balance contract missing';end if;
 execute replace(definition,needle,'-- IQD cash purchases can overdraw; receipts repay the signed balance.');

 definition:=pg_get_functiondef('solar_private.fx_prepare()'::regprocedure);
 needle:=$n$elsif new.total>solar_private.cash_balance(coalesce(new.cashbox_user_id,new.created_by))+refund then$n$;
 if strpos(definition,needle)=0 then raise exception 'Supplier cash balance contract missing';end if;
 execute replace(definition,needle,$n$elsif new.kind<>'purchase' and new.total>solar_private.cash_balance(coalesce(new.cashbox_user_id,new.created_by))+refund then$n$);
end$$;
notify pgrst,'reload schema';
