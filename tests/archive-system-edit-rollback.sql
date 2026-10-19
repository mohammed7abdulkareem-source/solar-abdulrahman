\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003585','مالك المنظومة',false,'admin_staff','{"system":true}'),
('00000000-0000-0000-0000-000000003586','إدارة التعديل',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003587','المهندس التجريبي',false,'installer','{}'),
('00000000-0000-0000-0000-000000003588','مستخدم مستقل',false,'admin_staff','{"system":true}');
insert into products(id,code,name,qty,cost) values(-358100,'SYS-EDIT','بطارية تعديل',20,100000);
insert into customers(id,name,customer_type,owner_id) values(-358100,'زبون تعديل منظومة','system','00000000-0000-0000-0000-000000003585');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003585',true);
select set_config('test.system.result',public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"زبون تعديل منظومة","sourceCurrency":"IQD","total":2500000,"installerId":"00000000-0000-0000-0000-000000003587","customerAddress":"العنوان الأصلي","items":[{"id":-358100,"qty":2,"price":0}]}')::text,true);
update transactions set warehouse_status='ready',warehouse_prepared_at=now(),installation_status='closed',installation_completed_at=now(),installation_closed_at=now(),installation_expenses=75000,profit=total-cost-75000 where id=(current_setting('test.system.result')::jsonb->>'id')::bigint;
set local role authenticated;
do $$declare t public.transactions;r jsonb;p jsonb;request uuid:=gen_random_uuid();begin
 select * into t from transactions where id=(current_setting('test.system.result')::jsonb->>'id')::bigint;
 p:=jsonb_build_object('kind','system','mode','credit','invoiceId',t.id,'warehouseId',t.warehouse_id,'expectedRevision',t.pricing_revision,'expectedInstallationRevision',t.installation_revision,'party','زبون تعديل منظومة','sourceCurrency','IQD','expenses',0,'total',3000000,'installerId',t.installer_id,'customerAddress','العنوان الجديد','items','[{"id":-358100,"qty":2,"price":0}]'::jsonb);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003588',true);
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'cross-user edit accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003586',true);
 begin perform public.solar_invoice_save(gen_random_uuid(),p||'{"expectedInstallationRevision":-1}');raise exception 'stale installation revision accepted';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),p||'{"expenses":100}');raise exception 'installation expenses changed outside workflow';exception when raise_exception then if sqlerrm='installation expenses changed outside workflow' then raise;end if;end;
 r:=public.solar_invoice_save(request,p);
 if public.solar_invoice_save(request,p)<>r then raise exception 'system edit retry changed response';end if;
 perform set_config('test.system.edit',r::text,true);
end$$;
reset role;
do $$declare t public.transactions;begin
 select * into t from transactions where id=(current_setting('test.system.result')::jsonb->>'id')::bigint;
 if t.total<>3000000 or t.cost<>200000 or t.installation_expenses<>75000 or t.profit<>2725000 then raise exception 'system financial edit lost costs %',to_jsonb(t);end if;
 if t.warehouse_status<>'ready' or t.installation_status<>'closed' or t.customer_address<>'العنوان الجديد' then raise exception 'unchanged materials reset workflow status %, warehouse %, address %',t.installation_status,t.warehouse_status,t.customer_address;end if;
 if t.created_by<>'00000000-0000-0000-0000-000000003585' or t.cashbox_user_id<>t.created_by or t.receipt_no<>(current_setting('test.system.result')::jsonb->>'receiptNo')::bigint then raise exception 'original ownership or receipt changed';end if;
 if(select qty from products where id=-358100)<>18 then raise exception 'price edit changed stock';end if;
 if(select count(*) from solar_private.receipt_change_audit where transaction_id=t.id and action='invoice_edit')<>1 then raise exception 'edit audit duplicate';end if;
end$$;
set local role authenticated;
do $$declare t public.transactions;p jsonb;begin
 select * into t from transactions where id=(current_setting('test.system.result')::jsonb->>'id')::bigint;
 p:=jsonb_build_object('kind','system','mode','credit','invoiceId',t.id,'warehouseId',t.warehouse_id,'expectedRevision',t.pricing_revision,'expectedInstallationRevision',t.installation_revision,'party',t.party_name,'sourceCurrency','IQD','expenses',0,'total',3000000,'installerId',t.installer_id,'customerAddress',t.customer_address,'items','[{"id":-358100,"qty":3,"price":0}]'::jsonb);
 perform public.solar_invoice_save(gen_random_uuid(),p);
end$$;
reset role;
do $$declare t public.transactions;begin
 select * into t from transactions where id=(current_setting('test.system.result')::jsonb->>'id')::bigint;
 if t.cost<>300000 or t.installation_expenses<>75000 or t.warehouse_status<>'pending' or t.installation_status<>'completed' or t.installation_closed_at is not null then raise exception 'material edit did not reopen review %',to_jsonb(t);end if;
 if(select qty from products where id=-358100)<>17 then raise exception 'quantity change did not post once';end if;
 raise notice 'PASS authorized system invoice editing, stale guards, original cost/expense/contact/receipt preservation, idempotent audited price edit, quantity adjustment and warehouse/closing review';
end$$;
rollback;
