// Full manager UI against an isolated, migrated PostgREST database. Uses its
// own fixture because a company FX change reprices every affected product.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB||='solar_v4126_wholesale_admin_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3345';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3341';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v4126/admin-browser';
const {base,db,sql,rpc,createHarness}=await import('./version4-browser-support.mjs');
assert.match(db,/^solar_v4126_wholesale_admin(?:_final)?_browser$/);
const id=Date.now(),manager=randomUUID(),code='FLR-'+id,name='لوح الاختبار '+id;
const state=(who='admin')=>rpc(who,'solar_wholesale_pricing',{action:'state'});
const getRow=async(who)=>{const row=(await state(who)).products.find(p=>p.id===id);assert.ok(row);return row;};
async function rate(value){
 const current=await rpc('admin','solar_exchange_rate_get',{});
 if(Number(current.rate)!==value)await rpc('admin','solar_exchange_rate_set',{rate:value,expected_revision:current.revision});
}
await rate(1500);
sql("insert into public.products(id,code,name,qty,cost,cost_basis) values("+id+",'"+code+"','"+name+"',8,92000,'{\"currencyComponents\":{\"usd\":50,\"iqd\":17000}}');insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(1,"+id+",8) on conflict(warehouse_id,product_id)do update set qty=8;");
sql("insert into public.profiles(id,username,display_name,active,is_admin,user_type,phone,permissions) values('"+manager+"','mgr_"+id+"','مسؤول التسعير "+id+"',true,false,'admin_staff','07700100404','{\"sale\":true,\"stock\":true,\"wholesalePricingManage\":true,\"profitUsesWholesalePrice\":true}')");
const h=await createHarness('material-floor-management');
try{
 const {page}=await h.open('admin','/?section=wholesalePricing');
 await page.getByRole('region',{name:'إدارة أسعار المواد',exact:true}).waitFor();
 const table=page.locator('.wpCatalog'),row=table.locator('[data-price-product="'+id+'"]');
 await table.getByRole('textbox',{name:/البحث في أسعار/}).fill(code);
 const value=row.locator('.wpEffective .wpCost bdi'),input=row.getByRole('textbox',{name:'سعر المادة اليدوي — '+name}),checkbox=row.getByRole('checkbox',{name:'اعتماد سعر المادة اليدوي — '+name});
 assert.equal(await row.locator('.wpEffective').getAttribute('data-label'),'الحد الأدنى لسعر المادة');
 await value.getByText('92,000',{exact:true}).waitFor();
 await input.fill('125555');
 assert.equal(await checkbox.isChecked(),false);
 assert.equal(await value.textContent(),'92,000');
 await rate(1600);await page.evaluate(()=>window.dispatchEvent(new Event('solar-exchange-rate-updated')));
 await value.getByText('97,000',{exact:true}).waitFor();
 assert.equal((await input.inputValue()).replaceAll(',',''),'125555');
 assert.equal(await checkbox.isChecked(),false);
 // Simulate an inventory receipt updating just this fixture material's cost.
 sql("update public.products set cost_basis=jsonb_set(cost_basis,'{currencyComponents,iqd}','19000.002731') where id="+id);
 await page.evaluate(()=>window.dispatchEvent(new Event('solar-warehouse-changed')));
 await value.getByText('99,000.01',{exact:true}).waitFor();
 await table.getByRole('button',{name:'حفظ الأسعار',exact:true}).click();
 await page.getByRole('status').filter({hasText:/تم تحديث أسعار|تم حفظ أسعار/}).waitFor();
 let saved=await getRow();assert.equal(saved.enabled,false);assert.equal(saved.minPrice,125555);
 assert.equal(saved.floorSource,'cost');assert.equal(Number(saved.effectiveMinPrice),99000.002731);
 await checkbox.check();await value.getByText('125,555',{exact:true}).waitFor();
 await table.getByRole('button',{name:'حفظ الأسعار',exact:true}).click();
 await page.getByRole('status').filter({hasText:/تم تحديث أسعار|تم حفظ أسعار/}).waitFor();
 await rate(1700);await page.evaluate(()=>window.dispatchEvent(new Event('solar-exchange-rate-updated')));
 await row.locator('.wpCostNote').getByText('104,000',{exact:true}).waitFor();
 assert.equal(await value.textContent(),'125,555');
 saved=await getRow();assert.equal(saved.enabled,true);assert.equal(saved.floorSource,'configured');
 await checkbox.uncheck();await value.getByText('104,000.01',{exact:true}).waitFor();
 await table.getByRole('button',{name:'حفظ الأسعار',exact:true}).click();
 await page.getByRole('status').filter({hasText:/تم تحديث أسعار|تم حفظ أسعار/}).waitFor();
 saved=await getRow();assert.equal(saved.minPrice,125555);assert.equal(Number(saved.effectiveMinPrice),104000.002731);
 const currentScope=(await state()).scopeMode;
 await h.layout(page,'admin-material-automatic',row);
 const restricted=(await h.open(manager,'/?section=wholesalePricing')).page;
 const restrictedTable=restricted.locator('.wpCatalog'),privateRow=restrictedTable.locator('[data-price-product="'+id+'"]');
 await restrictedTable.getByRole('textbox',{name:/البحث في أسعار/}).fill(code);
 await privateRow.locator('.wpFloorSource').getByText('تلقائي حسب الكلفة',{exact:true}).waitFor();
 const hidden=await getRow(manager);assert.equal(hidden.effectiveMinPrice,null);assert.equal(hidden.cost,null);
 assert.equal(await privateRow.locator('.wpEffective .wpCost').count(),0);
 assert.ok(!(await privateRow.innerText()).includes('104,000'));
 assert.equal((await privateRow.locator('.wpPriceInput input').inputValue()).replaceAll(',',''),'125555');
 assert.equal(await restricted.locator('.wpBasisPanel').count(),0);
 await privateRow.getByRole('checkbox').check();
 assert.equal(await privateRow.locator('.wpEffective .wpCost bdi').textContent(),'125,555');
 assert.equal(await privateRow.locator('.wpCostNote').count(),0);
 await privateRow.getByRole('checkbox').uncheck();
 await h.layout(restricted,'restricted-manager-automatic',privateRow);
 assert.equal((await state()).scopeMode,currentScope);
 h.checks.materialPricing={fx:97000,afterStock:99000.002731,afterSecondFx:104000.002731,savedOverride:125555,hiddenAuto:true};
 await h.finish();console.log('Automatic and manual material pricing management passed on '+base);
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
