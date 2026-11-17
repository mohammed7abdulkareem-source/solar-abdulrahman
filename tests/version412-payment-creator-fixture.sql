-- Additional local regression for foreign-created payments assigned to own cash.
\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'solar_seller_scope_browser' then raise exception 'Use isolated seller scope browser DB only';end if;end$$;
insert into profiles(id,username,display_name,is_admin,user_type,active,phone,permissions)values
('00000000-0000-0000-0000-000000412111','v412_payment_owner','صاحب قاصة تسديدات V412',false,'admin_staff',true,'07700412111','{"cash":true,"customers":true,"customerStatement":true,"customerPayment":true,"systemPayment":true,"supplierPayment":true,"supplierStatement":true,"salesHistory":true}');
insert into customers(id,name,customer_type,owner_id)values
(-412109,'عميل تسديد خصوصية V412','wholesale','00000000-0000-0000-0000-000000412111'),
(-412110,'عميل منظومة خصوصية V412','system','00000000-0000-0000-0000-000000412111');
insert into suppliers(id,name,account_currency)values(-412109,'مورد تسديد خصوصية V412','IQD');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes)values
(-412109,'customer_payment',-412109,'عميل تسديد خصوصية V412',333333,true,'payment','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412111','FOREIGN_PAYMENT_PRIVATE_V412_CUSTOMER'),
(-412110,'system_payment',-412110,'عميل منظومة خصوصية V412',333334,true,'payment','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412111','FOREIGN_PAYMENT_PRIVATE_V412_SYSTEM'),
(-412111,'supplier_payment',-412109,'مورد تسديد خصوصية V412',333335,true,'payment','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412111','FOREIGN_PAYMENT_PRIVATE_V412_SUPPLIER'),
(-412112,'customer_payment',-412109,'عميل تسديد خصوصية V412',11111,true,'payment','00000000-0000-0000-0000-000000412111','00000000-0000-0000-0000-000000412111','OWN_PAYMENT_V412_CUSTOMER'),
(-412113,'supplier_payment',-412109,'مورد تسديد خصوصية V412',11112,true,'payment','00000000-0000-0000-0000-000000412111','00000000-0000-0000-0000-000000412111','OWN_PAYMENT_V412_SUPPLIER');
commit;
