begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003780','مدير الكشف',true,'admin_staff','07701234567','{}'),
('00000000-0000-0000-0000-000000003781','قاصة أحمد',false,'admin_staff','07701234567','{"cash":true,"cashDeposit":true}'),
('00000000-0000-0000-0000-000000003782','قاصة سفيان',false,'admin_staff','07701234567','{"cash":true}'),
('00000000-0000-0000-0000-000000003783','مهندس',true,'installer','07701234567','{"cash":true}'),
('00000000-0000-0000-0000-000000003784','مستخدم بلا صلاحية',false,'admin_staff','07701234567','{}'),
('00000000-0000-0000-0000-000000003785','قاصة غير نشطة',false,'admin_staff','07701234567','{"cash":true}');
update profiles set active=false where id='00000000-0000-0000-0000-000000003785';
insert into transactions(id,kind,total,created_by)values(-378001,'system',0,'00000000-0000-0000-0000-000000003781');
insert into solar_cash_entries(id,owner_id,actor_id,delta,entry_type,notes,created_at,job_id)values
('00000000-0000-0000-0000-000000003780','00000000-0000-0000-0000-000000003781','00000000-0000-0000-0000-000000003780',1000000,'transfer_in','رصيد سابق','2026-09-30T20:59:59Z',null),
('00000000-0000-0000-0000-000000003781','00000000-0000-0000-0000-000000003781','00000000-0000-0000-0000-000000003780',-2000000,'installation_payout','ملاحظات المصروف الأصلي','2026-09-30T21:00Z',-378001),
('00000000-0000-0000-0000-000000003782','00000000-0000-0000-0000-000000003781','00000000-0000-0000-0000-000000003780',1500000,'transfer_in','قبض نهاية الفترة','2026-10-31T20:59:59Z',null),
('00000000-0000-0000-0000-000000003783','00000000-0000-0000-0000-000000003781','00000000-0000-0000-0000-000000003780',999,'transfer_in','خارج الفترة','2026-10-31T21:00Z',null),
('00000000-0000-0000-0000-000000003784','00000000-0000-0000-0000-000000003782','00000000-0000-0000-0000-000000003780',7000000,'transfer_in','قاصة ثانية','2026-10-15T10:00Z',null),
('00000000-0000-0000-0000-000000003785','00000000-0000-0000-0000-000000003785','00000000-0000-0000-0000-000000003780',123,'transfer_in','حركة غير نشط','2026-10-15T10:00Z',null);
insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,entry_type,note,created_at) overriding system value values
(-3781,'00000000-0000-0000-0000-000000003781','USD',100,150000,1500,'capital_deposit','رصيد الدولار','2026-09-30T20:59:59Z'),
(-3782,'00000000-0000-0000-0000-000000003781','USD',-120,-180000,1500,'capital_withdraw','صرف دولار','2026-10-20T10:00Z');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003780',true);
set local role authenticated;
do $$declare d jsonb;g jsonb;begin
 d:=public.solar_cash_statement('00000000-0000-0000-0000-000000003781','2026-10-01','2026-10-31','IQD');g:=d->'ledgers'->0;
 assert (d->>'count')::int=2,d::text;
 assert jsonb_array_length(d->'ledgers')=1;
 assert (g->>'opening')::numeric=1000000 and (g->>'incoming')::numeric=1500000 and (g->>'outgoing')::numeric=2000000 and (g->>'closing')::numeric=500000,g::text;
 assert (g->'rows'->0->>'balance')::numeric=-1000000;
 assert (g->'rows'->1->>'balance')::numeric=500000;
 assert g->'rows'->0->>'note'='ملاحظات المصروف الأصلي';
 assert g->'rows'->0->>'actor_name'='مدير الكشف';
 d:=public.solar_cash_statement(null,'2026-10-01','2026-10-31','all');
 assert exists(select 1 from jsonb_array_elements(d->'ledgers') x where x->>'ownerName'='قاصة سفيان' and x->>'currency'='IQD' and (x->>'closing')::numeric=7000000);
 assert exists(select 1 from jsonb_array_elements(d->'ledgers') x where x->>'ownerName'='قاصة غير نشطة' and (x->>'closing')::numeric=123);
 assert exists(select 1 from jsonb_array_elements(d->'ledgers') x where x->>'ownerName'='قاصة أحمد' and x->>'currency'='USD' and (x->>'closing')::numeric=-20);
 begin perform public.solar_cash_statement(null,'2026-10-31','2026-10-01','all');raise exception 'Invalid dates accepted';exception when sqlstate '22023' then null;end;
end$$;
reset role;
-- Changing a movement, including before the selected period, must recalculate
-- all subsequent balances. Removing it must remove its effect exactly once.
update solar_cash_entries set delta=2000000 where id='00000000-0000-0000-0000-000000003780';
update solar_cash_entries set delta=-500000,notes='ملاحظات معدلة' where id='00000000-0000-0000-0000-000000003781';
delete from solar_cash_entries where id='00000000-0000-0000-0000-000000003782';
set local role authenticated;
do $$declare d jsonb;g jsonb;begin
 d:=public.solar_cash_statement('00000000-0000-0000-0000-000000003781','2026-10-01','2026-10-31','IQD');g:=d->'ledgers'->0;
 assert (d->>'count')::int=1;
 assert (g->>'opening')::numeric=2000000 and (g->>'outgoing')::numeric=500000 and (g->>'closing')::numeric=1500000,g::text;
 assert g->'rows'->0->>'note'='ملاحظات معدلة';
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003781',true);
do $$declare d jsonb;begin
 d:=public.solar_cash_statement(null,'2026-10-01','2026-10-31','all');
 assert jsonb_array_length(d->'ledgers')=2;
 assert not exists(select 1 from jsonb_array_elements(d->'ledgers') x where x->>'ownerId'<>'00000000-0000-0000-0000-000000003781');
 begin perform public.solar_cash_statement('00000000-0000-0000-0000-000000003782','2026-10-01','2026-10-31','all');raise exception 'Cross-owner access';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003783',true);
do $$begin begin perform public.solar_cash_statement(null,'2026-10-01','2026-10-31','all');raise exception 'Installer access';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003784',true);
do $$begin begin perform public.solar_cash_statement(null,'2026-10-01','2026-10-31','all');raise exception 'Unprivileged access';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003785',true);
do $$begin begin perform public.solar_cash_statement(null,'2026-10-01','2026-10-31','all');raise exception 'Inactive access';exception when insufficient_privilege then null;end;end$$;
reset role;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,notes,created_at)
select '00000000-0000-0000-0000-000000003781','00000000-0000-0000-0000-000000003780',1,'transfer_in','حركة كبيرة '||n,'2026-10-20T10:00Z'::timestamptz from generate_series(1,5100)n;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003781',true);
set local role authenticated;
do $$declare d jsonb;g jsonb;begin
 d:=public.solar_cash_statement(null,'2026-10-01','2026-10-31','IQD');g:=d->'ledgers'->0;
 assert (d->>'count')::int=5101 and jsonb_array_length(g->'rows')=5101;
 assert (g->>'closing')::numeric=1505100;
 assert not has_function_privilege('anon','public.solar_cash_statement(uuid,date,date,text)','execute');
end$$;
rollback;
