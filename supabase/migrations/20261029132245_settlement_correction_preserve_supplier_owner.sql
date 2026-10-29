-- A different administrator may correct an allocation, while its original
-- supplier ledger owner and receipt author remain stable. The audit records
-- the administrator who actually performs the correction.
do $migration$
declare definition text;needle text:=$needle$   addition:=solar_private.fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',solar_private.next_transaction_id(),'supplierId',supplier.id,'amount',remaining,'currency','IQD','rate',rate,'accountRevision',supplier.currency_revision,'mode','charge_other','note','بقية أرباح '||(ctx->>'ownerName')||' بعد تعديل التسوية'));
   perform set_config('solar.fx_context',jsonb_build_object('marketRate',rate,'accountRevision',supplier.currency_revision,'cashCurrency','IQD')::text,true);
   update public.transactions set profit_supplier_settlement_id=r.id,profit_supplier_owner_id=r.owner_id where id=(addition->>'id')::bigint;
   perform set_config('solar.fx_context','',true);$needle$;
begin
 definition:=pg_get_functiondef('solar_private.cash_record(text,text,uuid,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Settlement supplier replacement contract missing';end if;
 execute replace(definition,needle,$replacement$   if remaining>1000000000000 then raise exception 'بقية أرباح المورد تتجاوز الحد المسموح للحركة';end if;
   number:=solar_private.next_transaction_id();
   perform set_config('solar.fx_context',jsonb_build_object('marketRate',rate,'accountRevision',supplier.currency_revision,'cashCurrency','IQD')::text,true);
   insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes,source_currency,exchange_rate,source_subtotal,profit_supplier_settlement_id,profit_supplier_owner_id)
   values(number,'supplier_payment','supplier',supplier.id,supplier.name,-remaining,false,'charge_other',
    coalesce(old_charge.created_by,r.decided_by,p.id),coalesce(old_charge.cashbox_user_id,old_charge.created_by,r.decided_by,p.id),
    'بقية أرباح '||(ctx->>'ownerName')||' بعد تعديل التسوية','IQD',1,-remaining,r.id,r.owner_id);
   perform set_config('solar.fx_context','',true);
   addition:=solar_private.supplier_payment_get(number)||jsonb_build_object('accountContext',solar_private.fx('account',null,jsonb_build_object('supplierId',supplier.id,'paymentId',number)));$replacement$);
end$migration$;
notify pgrst,'reload schema';
