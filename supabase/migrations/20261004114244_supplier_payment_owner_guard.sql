create or replace function solar_private.supplier_payment_get(payment_id bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; t public.transactions;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' or not (p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true' or coalesce(p.permissions->>'supplierStatement','false')='true') then raise exception 'Not permitted' using errcode='42501';end if;
 select * into t from public.transactions where id=payment_id and kind='supplier_payment';
 if t.id is null or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'Not permitted' using errcode='42501';end if;
 return jsonb_build_object('id',t.id,'supplierId',t.party_id,'party',t.party_name,'total',t.total,'notes',t.notes,'date',t.created_at,'token',md5(to_jsonb(t)::text));
end $$;

create or replace function solar_private.supplier_payment_save(request_id uuid,payment_id bigint,supplier_id bigint,amount numeric,note text default '',expected_token text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.profiles; t public.transactions; s public.suppliers; prior solar_private.supplier_payment_requests;
 args jsonb; result jsonb; payer uuid; old_amount numeric:=0; before_json jsonb;
begin
 perform pg_advisory_xact_lock(7311,1);
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type='installer' or not(p.is_admin or coalesce(p.permissions->>'supplierPayment','false')='true') then raise exception 'Not permitted' using errcode='42501';end if;
 if request_id is null or payment_id is null or abs(payment_id)>9007199254740991 or amount is null or not(amount>0 and amount<=1000000000000) or length(coalesce(note,''))>2000 then raise exception 'Invalid payment';end if;
 args:=jsonb_build_object('id',payment_id,'supplierId',supplier_id,'amount',amount,'note',coalesce(note,''),'token',expected_token);
 select * into prior from solar_private.supplier_payment_requests r where r.request_id=supplier_payment_save.request_id;
 if found then
  if prior.actor_id=p.id and prior.arguments=args then return prior.response;end if;
  raise exception 'Request conflict' using errcode='40001';
 end if;
 select * into s from public.suppliers where id=supplier_id;
 if s.id is null then raise exception 'Supplier unavailable';end if;
 select * into t from public.transactions where id=payment_id for update;
 if found then
  if t.kind<>'supplier_payment' or (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id) is distinct from true then raise exception 'Not permitted' using errcode='42501';end if;
  if expected_token is distinct from md5(to_jsonb(t)::text) then raise exception 'Payment changed; refresh and retry' using errcode='40001';end if;
  before_json:=to_jsonb(t);payer:=coalesce(t.cashbox_user_id,t.created_by);old_amount:=case when t.cash then t.total else 0 end;
 else
  if expected_token is not null then raise exception 'Payment changed; refresh and retry' using errcode='40001';end if;
  payer:=p.id;
 end if;
 if payer is null then raise exception 'Payment owner unavailable';end if;
 if amount>old_amount and solar_private.cash_balance(payer)<amount-old_amount then raise exception 'Insufficient cash' using errcode='P0002';end if;
 if t.id is null then
  insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes)
  values(payment_id,'supplier_payment','supplier',s.id,s.name,amount,true,'cash',p.id,payer,coalesce(note,''));
 else
  update public.transactions set party_type='supplier',party_id=s.id,party_name=s.name,total=amount,cash=true,payment_mode='cash',notes=coalesce(note,'') where id=payment_id;
 end if;
 result:=solar_private.supplier_payment_get(payment_id);
 insert into solar_private.supplier_payment_requests(request_id,actor_id,arguments,before_row,response) values(request_id,p.id,args,before_json,result);
 return result;
end $$;
