'use client';
import {useMemo,useState} from 'react';
import InstallationCalendar from './installation-calendar';
import {bookingSelectionKey} from './installation-utils.mjs';
import {useWarehouseInventory,WarehouseField} from './warehouse-data';
import {InvoiceShell,InvoiceField,InvoiceCatalog,InvoiceItems,InvoiceSummary,InvoiceActions} from './invoice-workspace';
import PartySearch from './party-search';
import MoneyInput from './money-input';
import WarrantyEditor from './warranty-editor';
import {warrantyPolicy,warrantyError} from './warranty-utils.mjs';
import {invoiceError} from './review-utils.mjs';
import {salesDocument} from './sales-document.mjs';
import {money} from './supplier-utils.mjs';
export default function SystemInvoiceEditor({original,customers,staff,products:catalogProducts,onUpdate,onCancel,onSaved,a4}){
 const [items,setItems]=useState(original.items),[query,setQuery]=useState(''),[party,setParty]=useState(original.party),[installerId,setInstallerId]=useState(original.installerId||''),[address,setAddress]=useState(original.customerAddress),[date,setDate]=useState(original.installDate),[time,setTime]=useState(original.installTime.slice(0,5)),[total,setTotal]=useState(String(original.total)),[notes,setNotes]=useState(original.notes||''),[warranty,setWarranty]=useState(original.warranty),[booking,setBooking]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const catalogVersion=useMemo(()=>JSON.stringify(catalogProducts||[]),[catalogProducts]);
 const inventory=useWarehouseInventory({versionKey:catalogVersion,initialWarehouseId:original.warehouseId});
 const products=inventory.products.map(p=>({...p,qty:Number(p.qty)+(original.items||[]).filter(i=>i.id===p.id).reduce((n,i)=>n+i.qty,0)}));
 const expenses=Number(original.expenses||0)+original.installationExpenses,cost=items.reduce((n,i)=>n+Number(i.qty||0)*Number(i.cost||0),0),installer=staff.find(s=>s.id===installerId);
 const changes={...original,items,party,installerId,customerAddress:address,customerPhone:customers.some(c=>c.name===party)?(customers.find(c=>c.name===party).phone||''):(party===original.party?original.customerPhone:''),installDate:date,installTime:time,total:Number(total),notes,warranty:warrantyPolicy(warranty,items),mode:original.cash?'cash':'credit'};
 const d=salesDocument({...changes,draft:true,party_name:party,created_at:original.date,customer_address:address,customer_phone:changes.customerPhone,installerName:installer?.display_name||installer?.username,items:items.map(i=>({...i,product_name:i.name,brand_name:i.brand}))});
 async function save(){
  if(busy)return;setError('');
  const invalid=!inventory.ready?'انتظر تحميل المخزن':!party?'اختر الزبون':!installerId?'اختر مهندس التنصيب':!address.trim()?'اكتب عنوان التنصيب':!!date!==!!time?'حدد يوم وساعة الموعد معًا':!Number.isFinite(Number(total))||Number(total)<=0?'اكتب سعر المنظومة':invoiceError(items.map(i=>({...i,price:0})),products,'system')||warrantyError(warranty,items);
  if(invalid){setError(invalid);return;}if(date&&(booking?.key!==bookingSelectionKey(date,installerId,time,original.id)||!booking.valid)){setError(booking?.conflict?'الموعد محجوز؛ اختر وقتًا آخر.':'انتظر تحميل الحجوزات أو أعد تحديث الجدول.');return;}setBusy(true);try{if(await onUpdate(original,changes))onSaved();}catch(e){setError(e.message||'تعذر حفظ التعديل.');}finally{setBusy(false);}
 }
 return <InvoiceShell kind="system" title="تعديل فاتورة بيع منظومة" className="systemWorkspace" currency="IQD" saving={busy} editing={{number:original.receiptNo,date:original.date}}><WarehouseField inventory={inventory} disabled label="مخزن تجهيز المنظومة"/>
  <div className="deskMeta"><InvoiceField label="الزبون"><PartySearch rows={customers} value={party} onChange={setParty}/></InvoiceField><InvoiceField label="مهندس التنصيب"><select aria-label="مهندس تعديل الفاتورة" value={installerId} onChange={e=>setInstallerId(e.target.value)}><option value="">اختر المهندس</option>{staff.filter(s=>s.user_type==='installer').map(s=><option key={s.id} value={s.id}>{s.display_name||s.username}</option>)}</select></InvoiceField><InvoiceField label="عنوان التنصيب"><input aria-label="عنوان تعديل الفاتورة" value={address} onChange={e=>setAddress(e.target.value)}/></InvoiceField></div>
  <div className="deskDates"><InvoiceField label="موعد التنصيب · اختياري"><input aria-label="تاريخ تعديل التنصيب" type="date" value={date} onChange={e=>setDate(e.target.value)}/></InvoiceField><InvoiceField label="الساعة"><input aria-label="ساعة تعديل التنصيب" type="time" value={time} onChange={e=>setTime(e.target.value)}/></InvoiceField></div>
  <InstallationCalendar date={date} selectedInstallerId={installerId} selectedTime={time} excludeInvoiceId={original.id} onAvailability={setBooking} onEngineerChange={setInstallerId} onPick={v=>{setInstallerId(v.installerId);setDate(v.date);setTime(v.time);}}/>
  <div className="deskBody"><InvoiceCatalog availableOnly products={products} items={items} query={query} onQuery={setQuery} onAdd={p=>setItems(current=>current.some(i=>i.id===p.id)?current:[{...p,qty:''},...current])}/><InvoiceItems kind="system" products={products} items={items} onEdit={(id,key,value)=>setItems(current=>current.map(i=>i.id===id?{...i,[key]:value}:i))} onRemove={id=>setItems(current=>current.filter(i=>i.id!==id))}/></div>
  <div className="deskFooterFields"><InvoiceField label="سعر بيع المنظومة · د.ع"><MoneyInput aria-label="تعديل سعر بيع المنظومة" value={total} onChange={setTotal}/></InvoiceField><InvoiceField label="ملاحظات الفاتورة"><textarea aria-label="ملاحظات تعديل المنظومة" value={notes} maxLength={4000} onChange={e=>setNotes(e.target.value)}/></InvoiceField></div>
  <p className="systemExpenseNotice">مصاريف التنصيب المحفوظة: {money(expenses)} د.ع. تعديلها من ملف التنصيب. تغيير المواد يعيد مراجعة التجهيز والغلق.</p>
  <WarrantyEditor value={warranty} items={items} onChange={setWarranty}/><InvoiceSummary total={total} entries={[["كلفة المواد",money(cost)+' د.ع'],["المصاريف المحفوظة",money(expenses)+' د.ع']]}/>{error&&<p className="workflowError" role="alert">{error}</p>}<InvoiceActions saving={busy} onSave={save} saveLabel="حفظ التعديل" onCancel={onCancel} documentHtml={a4(d.title,d.body,d.total,'مسودة تعديل غير محفوظة')} documentName={'تعديل-منظومة-'+original.receiptNo}/>
 </InvoiceShell>;
}
