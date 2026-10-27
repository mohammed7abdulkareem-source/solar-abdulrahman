-- Titles are optional display data, independent of login identity and permissions.
alter table public.profiles add column honorific text not null default ''
 check(char_length(honorific)<=50 and honorific=btrim(honorific) and honorific !~ '[[:cntrl:]<>]');

create function solar_private.user_name(display_name text,username text,honorific text) returns text
language sql immutable set search_path='' as $$
 with value as(select coalesce(nullif(btrim(display_name),''),nullif(btrim(username),'')) name,
  btrim(regexp_replace(coalesce(honorific,''),'\s+',' ','g')) title)
 select case when title='' or name is null or name=title or starts_with(name,title||' ') then name else title||' '||name end from value
$$;
revoke all on function solar_private.user_name(text,text,text) from public,anon;
grant execute on function solar_private.user_name(text,text,text) to authenticated;

-- Only user-label expressions change. Existing monetary logic, scoping,
-- saved records, function configuration and grants are preserved.
do $$declare patch jsonb;definition text;begin
 for patch in select value from jsonb_array_elements($patches$[
  {
    "function": "solar_private.admin_announcement(text,text,text,text,uuid)",
    "old": "coalesce(actor.display_name,actor.username)",
    "new": "solar_private.user_name(actor.display_name,actor.username,actor.honorific)"
  },
  {
    "function": "solar_private.admin_announcement(text,text,text,text,uuid)",
    "old": "coalesce(actor.display_name,actor.username,'الإدارة')",
    "new": "coalesce(solar_private.user_name(actor.display_name,actor.username,actor.honorific),'الإدارة')"
  },
  {
    "function": "solar_private.capital_snapshot()",
    "old": "coalesce(u.display_name,u.username,'قاصة غير محددة')",
    "new": "coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'قاصة غير محددة')"
  },
  {
    "function": "solar_private.capital_snapshot()",
    "old": "coalesce(u.display_name,u.username,'غير محدد')",
    "new": "coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'غير محدد')"
  },
  {
    "function": "solar_private.cash_movement_detail(text)",
    "old": "coalesce(o.display_name,o.username,'قيد التسليم')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'قيد التسليم')"
  },
  {
    "function": "solar_private.cash_movement_detail(text)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.cash_receipt(uuid)",
    "old": "coalesce(p.display_name,p.username)",
    "new": "solar_private.user_name(p.display_name,p.username,p.honorific)"
  },
  {
    "function": "solar_private.cash_reconcile(text,uuid,jsonb)",
    "old": "coalesce(u.display_name,u.username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(u.display_name,u.username,u.honorific),'مستخدم')"
  },
  {
    "function": "solar_private.cash_reconcile(text,uuid,jsonb)",
    "old": "coalesce(actor.display_name,actor.username)",
    "new": "solar_private.user_name(actor.display_name,actor.username,actor.honorific)"
  },
  {
    "function": "solar_private.cash_save(uuid,jsonb)",
    "old": "coalesce(display_name,username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم')"
  },
  {
    "function": "solar_private.cash_statement(uuid,date,date,text)",
    "old": "coalesce(a.display_name,a.username,'غير محدد')",
    "new": "coalesce(solar_private.user_name(a.display_name,a.username,a.honorific),'غير محدد')"
  },
  {
    "function": "solar_private.cash_statement(uuid,date,date,text)",
    "old": "coalesce(sender.display_name,sender.username)",
    "new": "solar_private.user_name(sender.display_name,sender.username,sender.honorific)"
  },
  {
    "function": "solar_private.cash_statement(uuid,date,date,text)",
    "old": "coalesce(recipient.display_name,recipient.username)",
    "new": "solar_private.user_name(recipient.display_name,recipient.username,recipient.honorific)"
  },
  {
    "function": "solar_private.cash_statement(uuid,date,date,text)",
    "old": "coalesce(pf.display_name,pf.username,'قيد التسليم')",
    "new": "coalesce(solar_private.user_name(pf.display_name,pf.username,pf.honorific),'قيد التسليم')"
  },
  {
    "function": "solar_private.cash_statement(uuid,date,date,text)",
    "old": "coalesce(display_name,username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم')"
  },
  {
    "function": "solar_private.cash_transfer_overview()",
    "old": "coalesce(u.display_name,u.username)",
    "new": "solar_private.user_name(u.display_name,u.username,u.honorific)"
  },
  {
    "function": "solar_private.cash_workspace(jsonb)",
    "old": "coalesce(o.display_name,o.username,'قيد التسليم')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'قيد التسليم')"
  },
  {
    "function": "solar_private.cash_workspace(jsonb)",
    "old": "coalesce(display_name,username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم')"
  },
  {
    "function": "solar_private.cash_workspace(jsonb)",
    "old": "coalesce(o.display_name,o.username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'مستخدم')"
  },
  {
    "function": "solar_private.customer_documents(bigint,bigint,date,date,text,text)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.customer_get(bigint)",
    "old": "coalesce(x.display_name,x.username)",
    "new": "solar_private.user_name(x.display_name,x.username,x.honorific)"
  },
  {
    "function": "solar_private.customer_invoice_document(transactions)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.customer_payment_context(bigint)",
    "old": "coalesce(o.display_name,o.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.customer_payment_context(bigint)",
    "old": "coalesce(p.display_name,p.username,'المستلم')",
    "new": "coalesce(solar_private.user_name(p.display_name,p.username,p.honorific),'المستلم')"
  },
  {
    "function": "solar_private.customer_payment_manage(text,uuid,jsonb)",
    "old": "coalesce(o.display_name,o.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.customer_payment_manage(text,uuid,jsonb)",
    "old": "coalesce(o.display_name,o.username,'')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'')"
  },
  {
    "function": "solar_private.customer_statement(bigint)",
    "old": "coalesce(x.display_name,x.username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(x.display_name,x.username,x.honorific),'مستخدم')"
  },
  {
    "function": "solar_private.fx(text,uuid,jsonb)",
    "old": "coalesce(display_name,username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم')"
  },
  {
    "function": "solar_private.installation_jobs()",
    "old": "coalesce(x.display_name,x.username)",
    "new": "solar_private.user_name(x.display_name,x.username,x.honorific)"
  },
  {
    "function": "solar_private.installation_jobs()",
    "old": "coalesce(c.display_name,c.username)",
    "new": "solar_private.user_name(c.display_name,c.username,c.honorific)"
  },
  {
    "function": "solar_private.installation_schedule(date,date,uuid,bigint)",
    "old": "coalesce(e.display_name,e.username)",
    "new": "solar_private.user_name(e.display_name,e.username,e.honorific)"
  },
  {
    "function": "solar_private.installation_schedule(date,date,uuid,bigint)",
    "old": "coalesce(c.display_name,c.username)",
    "new": "solar_private.user_name(c.display_name,c.username,c.honorific)"
  },
  {
    "function": "solar_private.inventory_v350(text,uuid,jsonb)",
    "old": "coalesce(p.display_name,p.username)",
    "new": "solar_private.user_name(p.display_name,p.username,p.honorific)"
  },
  {
    "function": "solar_private.inventory_v350(text,uuid,jsonb)",
    "old": "coalesce(person.display_name,person.username)",
    "new": "solar_private.user_name(person.display_name,person.username,person.honorific)"
  },
  {
    "function": "solar_private.inventory(text,uuid,jsonb)",
    "old": "coalesce(person.display_name,person.username)",
    "new": "solar_private.user_name(person.display_name,person.username,person.honorific)"
  },
  {
    "function": "solar_private.party_balances_legacy_iqd(text,date)",
    "old": "coalesce(x.display_name,x.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(x.display_name,x.username,x.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.party_balances(text,date)",
    "old": "coalesce(x.display_name,x.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(x.display_name,x.username,x.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.payment_history(text,jsonb)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.pending_systems(uuid,date,date)",
    "old": "coalesce(o.display_name,o.username,'غير محدد')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير محدد')"
  },
  {
    "function": "solar_private.profit_detail(text,uuid)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.profit_transfer(text,uuid,jsonb)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.profit_transfer(text,uuid,jsonb)",
    "old": "coalesce(target.display_name,target.username)",
    "new": "solar_private.user_name(target.display_name,target.username,target.honorific)"
  },
  {
    "function": "solar_private.profit_workspace(text,uuid,jsonb)",
    "old": "coalesce(o.display_name,o.username)",
    "new": "solar_private.user_name(o.display_name,o.username,o.honorific)"
  },
  {
    "function": "solar_private.profit_workspace(text,uuid,jsonb)",
    "old": "coalesce(d.display_name,d.username)",
    "new": "solar_private.user_name(d.display_name,d.username,d.honorific)"
  },
  {
    "function": "solar_private.profit_workspace(text,uuid,jsonb)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.receipt_contact_json(jsonb,text)",
    "old": "coalesce(author.display_name,author.username,'')",
    "new": "coalesce(solar_private.user_name(author.display_name,author.username,author.honorific),'')"
  },
  {
    "function": "solar_private.receipt_contacts()",
    "old": "coalesce(x.display_name,x.username)",
    "new": "solar_private.user_name(x.display_name,x.username,x.honorific)"
  },
  {
    "function": "solar_private.sales_history(text,text,date,date,text,integer)",
    "old": "coalesce(x.display_name,x.username)",
    "new": "solar_private.user_name(x.display_name,x.username,x.honorific)"
  },
  {
    "function": "solar_private.statement_customers()",
    "old": "coalesce(x.display_name,x.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(x.display_name,x.username,x.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.supplier_account(bigint,bigint)",
    "old": "coalesce(x.display_name,x.username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(x.display_name,x.username,x.honorific),'مستخدم')"
  },
  {
    "function": "solar_private.supplier_payment_manage(text,uuid,jsonb)",
    "old": "coalesce(o.display_name,o.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.supplier_payment_manage(text,uuid,jsonb)",
    "old": "coalesce(display_name,username,'مستخدم')",
    "new": "coalesce(solar_private.user_name(display_name,username,honorific),'مستخدم')"
  },
  {
    "function": "solar_private.supplier_payment_manage(text,uuid,jsonb)",
    "old": "coalesce(actor.display_name,actor.username)",
    "new": "solar_private.user_name(actor.display_name,actor.username,actor.honorific)"
  },
  {
    "function": "solar_private.system_payment_context(bigint)",
    "old": "coalesce(o.display_name,o.username,'غير مخصص')",
    "new": "coalesce(solar_private.user_name(o.display_name,o.username,o.honorific),'غير مخصص')"
  },
  {
    "function": "solar_private.system_payment_context(bigint)",
    "old": "coalesce(p.display_name,p.username,'المستلم')",
    "new": "coalesce(solar_private.user_name(p.display_name,p.username,p.honorific),'المستلم')"
  },
  {
    "function": "solar_private.warehouse_orders_v364(text,text,integer)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.warranty_apply(bigint,jsonb)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.warranty_verify(uuid)",
    "old": "coalesce(display_name,username)",
    "new": "solar_private.user_name(display_name,username,honorific)"
  },
  {
    "function": "solar_private.staff_directory()",
    "old": "'display_name',x.display_name,'username'",
    "new": "'display_name',x.display_name,'honorific',x.honorific,'username'"
  },
  {
    "function": "solar_private.cash_statement(uuid,date,date,text)",
    "old": "group by o.id,c.c,pf.display_name,pf.username",
    "new": "group by o.id,c.c,pf.display_name,pf.username,pf.honorific"
  }
]$patches$::jsonb) loop
  definition:=pg_get_functiondef((patch->>'function')::regprocedure);
  if strpos(definition,patch->>'old')=0 then raise exception 'User label projection contract missing: %',patch->>'function';end if;
  execute replace(definition,patch->>'old',patch->>'new');
 end loop;
end$$;
notify pgrst,'reload schema';
