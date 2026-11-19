import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4116_warehouse_queue_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3230';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3231';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4116/warehouse-queue-browser';
const {createHarness,ids,db,sql,fingerprint}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4116_warehouse_queue_browser');
const search='queue'+randomUUID().replaceAll('-','');
sql(`insert into solar_private.stock_transfers(id,from_id,to_id,from_name,to_name,actor_id,actor_name,status,items)
 select gen_random_uuid(),source.id,dest.id,source.name,dest.name,'${ids.admin}','${search}',states.status,
 '[{"name":"Warehouse panel","qty":3,"code":"T"}]'::jsonb
 from solar_private.warehouses source cross join solar_private.warehouses dest
 cross join (values('pending'),('posted'),('cancelled'),('reversed')) states(status)
 where source.is_primary and dest.code='SAYADA';`);
const h=await createHarness('warehouse-queue');
try{
 const before=fingerprint();
 const {page}=await h.open('admin','/?section=warehouse');
 const sections=page.getByRole('navigation',{name:'نوع تجهيز المخزن'});
 await sections.getByRole('button',{name:'فواتير البيع'}).click();
 const invoice=page.locator('.warehouseOrder').first();
 await invoice.waitFor();
 await h.layout(page,'warehouse-invoice-list',sections);
 await invoice.locator('summary').click();
 await invoice.locator('.warehouseRowBody').waitFor();
 await sections.getByRole('button',{name:/طلبات نقل المخازن/}).click();
 const queue=page.locator('.warehouseTransferQueue');
 await queue.getByLabel('بحث طلبات النقل').fill(search);
 await queue.getByRole('button',{name:'بحث / تحديث'}).click();
 const filters=queue.getByRole('navigation',{name:'حالات تجهيز النقل'});
 const resolved=filters.getByRole('button',{name:/محسومة/});
 await resolved.locator('bdi').filter({hasText:/^3$/}).waitFor();
 assert.equal(await filters.getByRole('button',{name:/بانتظار التجهيز/}).locator('bdi').innerText(),'1');
 assert.equal(await filters.getByRole('button',{name:/كل الطلبات/}).locator('bdi').innerText(),'4');
 await resolved.click();
 await queue.locator('[data-transfer-state="cancelled"]').waitFor();
 const outcomes=await queue.locator('[data-transfer-state]').evaluateAll(rows=>rows.map(row=>row.dataset.transferState).sort());
 assert.deepEqual(outcomes,['cancelled','posted','reversed']);
 await h.layout(page,'warehouse-resolved-list',filters);
 const cancelled=queue.locator('[data-transfer-state="cancelled"]');
 await cancelled.locator('summary').click();
 await cancelled.locator('.warehouseRowBody').waitFor();
 assert.equal(await cancelled.getByRole('button',{name:'تأكيد تجهيز النقل'}).count(),0);
 await filters.getByRole('button',{name:/كل الطلبات/}).click();
 await queue.locator('[data-transfer-state="pending"]').waitFor();
 assert.equal(await queue.locator('[data-transfer-state]').count(),4);
 assert.equal(fingerprint(),before);
 h.checks.resolvedEqualsPostedCancelledAndReversed=true;
 await h.finish();
 console.log('PASS compact invoice and transfer queues, open vs resolved, accessible details and source status counters');
}catch(error){
 await h.fail(error);
 throw error;
}finally{
 await h.close();
}
