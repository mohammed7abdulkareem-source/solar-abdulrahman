'use client';
import {useEffect,useMemo,useRef,useState} from 'react';
import {supabase} from './supabase';
import {downloadPdf,sharePdf} from './pdf-share.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {BATTERY_CAPACITIES,batteryCapacity,FIXED_EXPENSES,newQuote,calculateQuote,productSnapshot,quoteDocument,money,normalizeNumber} from './tahseel-utils.mjs';
import {quoteStore,limitedQuoteStore} from './tahseel-store.mjs';

const fullStore=quoteStore(supabase),limitedStore=limitedQuoteStore(supabase);
function NumberField({label,value,onChange,suffix='د.ع'}){
  return <label className="quoteField"><span>{label}</span><div className="quoteInput"><input aria-label={label} inputMode="decimal" value={value} onChange={e=>onChange(normalizeNumber(e.target.value))}/><small>{suffix}</small></div></label>;
}
function MaterialPicker({label,products,value,onChange,qty,fullAccess=true}){
  const [query,setQuery]=useState('');
  const shown=products.filter(p=>normalizeSearch([p.name,p.code,p.brand].join(' ')).includes(normalizeSearch(query))||String(p.id)===String(value?.id));
  return <div className="quoteMaterial"><div className="quoteMaterialHeading"><b>{label}</b><span>{qty} {label==='الانفيرتر'?'جهاز':'قطعة'}</span></div><input aria-label={'بحث '+label} placeholder={'بحث '+label+' بالاسم أو البراند'} value={query} onChange={e=>setQuery(e.target.value)}/><select aria-label={label} value={value?.id||''} onChange={e=>{const p=products.find(x=>String(x.id)===e.target.value);onChange(p?(fullAccess?productSnapshot(p):{id:p.id,name:p.name,brand:p.brand||''}):null)}}><option value="">اختر المادة</option>{value&&!products.some(p=>String(p.id)===String(value.id))&&<option value={value.id}>{value.name} — محفوظة بالمسودة</option>}{shown.map(p=><option key={p.id} value={p.id}>{p.name}{p.brand?' • '+p.brand:''}</option>)}</select>{value&&fullAccess&&<><NumberField label={'كلفة الوحدة — '+label} value={value.cost} onChange={cost=>onChange({...value,cost})}/><small>إجمالي الكلفة: {Number(value.cost)>0?money(Number(value.cost)*qty)+' د.ع':'أدخل كلفة الوحدة'}</small></>}</div>;
}

export default function TahseelWorkspace({products,userId,a4,openA4,onDirtyChange,fullAccess=false}){
  const store=fullAccess?fullStore:limitedStore;
  const fresh=()=>newQuote(fullAccess?5:15);
  const [form,setForm]=useState(fresh),[current,setCurrent]=useState(null),[baseline,setBaseline]=useState(()=>JSON.stringify(fresh()));
  const [drafts,setDrafts]=useState([]),[query,setQuery]=useState(''),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState(''),[listError,setListError]=useState(''),[internal,setInternal]=useState(false);
  const pendingId=useRef(null),lock=useRef(false);
  const dirty=JSON.stringify(form)!==baseline;
  const [remote,setRemote]=useState(null),[priceError,setPriceError]=useState('');
  const fingerprint=JSON.stringify(form);
  const local=useMemo(()=>calculateQuote(form),[form]);
  const currentPrice=remote?.fingerprint===fingerprint?remote.result:null;
  const result=fullAccess?local:currentPrice||{...local,price:0,errors:[priceError||'جاري احتساب سعر البيع…']};
  useEffect(()=>{
    if(fullAccess)return;
    let live=true;setPriceError('');
    const timer=setTimeout(()=>limitedStore.preview(form).then(result=>{if(live)setRemote({fingerprint,result})}).catch(e=>{if(live)setPriceError(e.message)}),250);
    return()=>{live=false;clearTimeout(timer)};
  },[fingerprint,fullAccess]);
  const panels=products.filter(p=>/ألواح|الواح|panel/i.test(p.category||''));
  const batteries=products.filter(p=>/بطاري|batter/i.test(p.category||''));
  const inverters=products.filter(p=>/انفيرتر|إنفيرتر|inverter|all in one/i.test(p.category||''));
  const set=(key,value)=>{setForm(f=>({...f,[key]:value}));setMessage('');setError('')};
  useEffect(()=>{onDirtyChange?.(dirty);return()=>onDirtyChange?.(false)},[dirty,onDirtyChange]);
  useEffect(()=>{if(!dirty)return;const guard=e=>{e.preventDefault();e.returnValue=''};window.addEventListener('beforeunload',guard);return()=>window.removeEventListener('beforeunload',guard)},[dirty]);
  useEffect(()=>{let live=true;store.list(userId).then(rows=>{if(live)setDrafts(rows)}).catch(e=>{if(live)setListError(e.message)}).finally(()=>{if(live)setLoading(false)});return()=>{live=false}},[userId]);
  async function refresh(){setLoading(true);setListError('');try{setDrafts(await store.list(userId))}catch(e){setListError(e.message)}finally{setLoading(false)}}
  async function run(fn){if(lock.current)return;lock.current=true;setBusy(true);setMessage('');setError('');try{await fn()}catch(e){setError(e.message||'تعذر تنفيذ العملية. حاول مجدداً.')}finally{lock.current=false;setBusy(false)}}
  const canDiscard=()=>!dirty||confirm('عند المتابعة ستفقد التعديلات غير المحفوظة. متابعة؟');
  function reset(){if(!canDiscard())return;const f=fresh();setForm(f);setBaseline(JSON.stringify(f));setCurrent(null);pendingId.current=null;setError('');setMessage('')}
  function open(row){if(!canDiscard())return;setForm(structuredClone(row.payload));setBaseline(JSON.stringify(row.payload));setCurrent(row);pendingId.current=null;setMessage(fullAccess?'تم فتح المسودة بأسعارها المحفوظة.':'تم فتح المسودة؛ يُحتسب السعر بالكلف الحالية ونسبة 15%.');setError('');window.scrollTo({top:0,behavior:'smooth'})}
  async function save(){await run(async()=>{
    pendingId.current ||= crypto.randomUUID();
    const row=await store.save({id:current?.id||pendingId.current,revision:current?.revision,userId,payload:form});
    setCurrent(row);setBaseline(JSON.stringify(form));setDrafts(v=>[row,...v.filter(x=>x.id!==row.id)]);setMessage('تم حفظ المسودة في حسابك.');
  })}
  async function remove(row){if(!confirm('حذف مسودة '+(row.payload.customer||'منظومة '+row.payload.day+' × '+row.payload.night)+'؟'))return;await run(async()=>{
    await store.remove(row,userId);setDrafts(v=>v.filter(x=>x.id!==row.id));if(current?.id===row.id){const f=fresh();setForm(f);setBaseline(JSON.stringify(f));setCurrent(null);pendingId.current=null}setMessage('تم حذف المسودة.');
  })}
  const html=()=>a4(fullAccess&&internal?'التحصيل — تفاصيل الكلفة':'عرض سعر منظومة',quoteDocument(form,fullAccess&&internal,fullAccess?null:result),money(result.price)+' د.ع',new Date(current?.created_at||Date.now()).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'}));
  const filename='عرض-منظومة-'+(form.customer||form.day+'-'+form.night)+(fullAccess&&internal?'-كلفة':'');
  function preview(){setError('');try{openA4(html())}catch(e){setError(e.message)}}
  const shownDrafts=drafts.filter(row=>normalizeSearch([row.payload.customer,row.payload.phone,row.payload.day+'×'+row.payload.night].join(' ')).includes(normalizeSearch(query)));
  return <section className="quoteWorkspace">
    <div className="quoteBanner"><span className="quoteSun">☀</span><div><h2>التحصيل</h2><p>احسب المنظومة، واعرف السعر قبل ما تجاوب الزبون.</p></div><button onClick={reset} disabled={busy}>حساب جديد</button></div>
    <div className="card quoteCard quoteDocumentTools">{fullAccess&&<label className="quoteField">نسخة المستند<select value={internal?'internal':'customer'} onChange={e=>setInternal(e.target.value==='internal')} disabled={busy}><option value="customer">عرض سعر للزبون — السعر النهائي والمواد</option><option value="internal">نسخة داخلية — الكلفة والمصاريف ونسبة الربح</option></select></label>}<div className="quoteActions"><button disabled={busy||!!result.errors.length} onClick={preview}>معاينة</button><button disabled={busy||!!result.errors.length} onClick={()=>run(()=>downloadPdf(filename,html()))}>حفظ PDF</button><button disabled={busy||!!result.errors.length} onClick={()=>run(async()=>{const r=await sharePdf(filename,html());if(r==='downloaded')setMessage('تم تنزيل PDF. يمكنك مشاركته من ملفات الجهاز.');})}>مشاركة</button><button className="quoteSave" disabled={busy} onClick={save}>{busy?'جاري التنفيذ…':current?'حفظ التعديلات':'حفظ كمسودة'}</button></div><small className="quoteHint">{dirty?'توجد تعديلات غير محفوظة.':current?'المسودة محفوظة.':'الحساب الجديد جاهز للتعديل.'} المسودات لا تغيّر المخزون أو القاصة.</small></div>
    <fieldset disabled={busy} className="quoteForm">
      <div className="card quoteCard"><h3><span>١</span> طلب الزبون</h3><div className="quotePair"><label className="quoteField">اسم الزبون (اختياري)<input value={form.customer} maxLength={160} onChange={e=>set('customer',e.target.value)} placeholder="اسم الزبون"/></label><label className="quoteField">رقم الهاتف (اختياري)<input inputMode="tel" value={form.phone} maxLength={40} onChange={e=>set('phone',e.target.value)} placeholder="رقم الهاتف"/></label></div><div className="quotePair"><NumberField label="أمبير نهاري" value={form.day} onChange={v=>set('day',v)} suffix="أمبير"/><NumberField label="أمبير ليلي" value={form.night} onChange={v=>set('night',v)} suffix="أمبير"/></div><label className="quoteField quoteCapacity">سعة البطارية<select aria-label="سعة البطارية" value={batteryCapacity(form)} onChange={e=>{setForm(f=>({...f,batteryCapacity:e.target.value,battery:null}));setMessage('');setError('')}}><option value="">اختر سعة البطارية</option>{BATTERY_CAPACITIES.map(capacity=><option key={capacity} value={capacity}>{capacity} كيلوواط</option>)}</select></label><div className="quoteCounts"><div><small>ألواح 600 واط</small><strong>{result.panelQty}</strong><span>اللوح = 2.15 أمبير</span></div><div><small>{result.batteryCapacity?`بطاريات ${result.batteryCapacity} كيلو`:"عدد البطاريات"}</small><strong>{result.batteryCapacity||form.night==='0'?result.batteryQty:'—'}</strong><span>{result.batteryCapacity?`البطارية = ${result.batteryCapacity} أمبير ليلي`:"اختر سعة البطارية"}</span></div></div><p className="quoteHint">الحساب حسب قاعدة المحل، مع تقريب عدد القطع للأعلى. عدد البطاريات = الأمبير الليلي ÷ سعة البطارية المختارة. اختر أدناه ألواح 600 واط وبطارية تطابق السعة.</p></div>
      <div className="card quoteCard"><h3><span>٢</span> {fullAccess?'المواد وكلفتها':'اختيار المواد'}</h3><MaterialPicker fullAccess={fullAccess} label="الانفيرتر" products={inverters} value={form.inverter} onChange={v=>set('inverter',v)} qty={1}/><p className="quoteHint">الانفيرتر باختيارك؛ حسب قاعدتك، 6kW للمنظومة الأقل من 24 أمبير.</p>{result.panelQty>0&&<MaterialPicker fullAccess={fullAccess} label="لوح 600 واط" products={panels} value={form.panel} onChange={v=>set('panel',v)} qty={result.panelQty}/>} {result.batteryQty>0&&<MaterialPicker fullAccess={fullAccess} label={'بطارية '+result.batteryCapacity+' كيلو'} products={batteries} value={form.battery} onChange={v=>set('battery',v)} qty={result.batteryQty}/>}{fullAccess&&<p className="quoteHint">تظهر كلفة المادة الحالية عند اختيارها. يمكنك تعديل كلفة العرض، وتبقى أسعار المسودة محفوظة.</p>}</div>
      {fullAccess&&<div className="card quoteCard"><h3><span>٣</span> المصاريف</h3><div className="quotePair"><NumberField label="مصاريف كل لوح" value={form.perPanel} onChange={v=>set('perPanel',v)}/><div className="quotePanelExpense"><small>{result.panelQty} ألواح × {money(Number(form.perPanel)||0)}</small><b>{money(result.expenses[0].total)} د.ع</b></div>{FIXED_EXPENSES.map(([key,label])=><NumberField key={key} label={label} value={form.expenses[key]} onChange={v=>set('expenses',{...form.expenses,[key]:v})}/>)}</div><label className="quoteField">ملاحظات العرض<textarea value={form.notes} onChange={e=>set('notes',e.target.value)} maxLength={2000} placeholder="اختياري"/></label><NumberField label="نسبة الربح" suffix="%" value={form.markupPercent??'5'} onChange={v=>set('markupPercent',v)}/><div className="quoteRatePresets">{[5,10,15].map(rate=><button type="button" key={rate} onClick={()=>set('markupPercent',String(rate))}>{rate}%</button>)}</div></div>}
    </fieldset>
    <div className="quoteSummary card"><h3>حساب سعر المنظومة</h3>{fullAccess&&<><div><span>كلفة المواد</span><b>{money(result.materialsTotal)} د.ع</b></div><div><span>مجموع المصاريف</span><b>{money(result.expensesTotal)} د.ع</b></div><div><span>الكلفة الكلية</span><b>{money(result.cost)} د.ع</b></div><div><span>إضافة {result.markupPercent}% على الكلفة</span><b>{money(result.markup)} د.ع</b></div></>}<div className="quotePrice" aria-live="polite"><span>{result.errors.length?(fullAccess?'أكمل المواد والكلف لإظهار السعر':'اختر المواد لإظهار سعر البيع'):'سعر المنظومة للزبون'}</span><strong>{result.errors.length?'—':money(result.price)+' د.ع'}</strong></div>{result.errors.length>0&&<ul className="quoteMissing">{result.errors.map(e=><li key={e}>{e}</li>)}</ul>}</div>

    {message&&<p role="status" className="workflowSuccess">{message}</p>}{error&&<p role="alert" className="workflowError">{error}</p>}
    <div className="card quoteCard"><div className="quoteDraftHeading"><h3>مسوداتي <small>({drafts.length})</small></h3><button onClick={refresh} disabled={loading||busy}>تحديث</button></div><input aria-label="بحث المسودات" placeholder="بحث باسم الزبون أو الهاتف أو مقاس المنظومة" value={query} onChange={e=>setQuery(e.target.value)}/>{listError&&<p role="alert" className="workflowError">{listError}</p>}{loading?<p>جاري تحميل المسودات…</p>:!shownDrafts.length?<p className="quoteHint">لا توجد مسودات ضمن البحث.</p>:shownDrafts.map(row=>{const q=fullAccess?calculateQuote(row.payload):row.result||{errors:['غير مكتمل']};return <article key={row.id} className="quoteDraft"><div><b>{row.payload.customer||'زبون غير محدد'}</b><small>{row.payload.day} نهاري × {row.payload.night} ليلي • {new Date(row.updated_at).toLocaleDateString('ar-IQ')}</small><strong>{q.errors.length?'مسودة غير مكتملة':money(q.price)+' د.ع'}</strong></div><div><button onClick={()=>open(row)} disabled={busy}>فتح</button><button className="dangerMini" onClick={()=>remove(row)} disabled={busy}>حذف</button></div></article>})}</div>
  </section>;
}
