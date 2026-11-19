'use client';
import {Fragment,useEffect,useMemo,useRef,useState} from 'react';
import {inventoryCall} from './warehouse-data';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import MaterialMovementPicker from './material-movement-picker';
import {salesAuthorizationKey} from './sales-read-scope.mjs';
import {filterMaterialRows,materialMovementDocument,materialPrice,movementTime,materialReportPeriod,materialReportMatchesSelection,materialMovementPresentation,materialVisibleTotals,materialSignedQuantity,materialLastVisibleBalances,materialQuantity as quantity} from './material-movement-utils.mjs';
import {escapeHtml} from './document-format.mjs';

const empty={productId:'',warehouseId:'',from:'',to:'',withPrices:false};
export default function MaterialMovementLedger({inventory,profile,a4}){
 const [draft,setDraft]=useState(empty),[applied,setApplied]=useState(empty),[search,setSearch]=useState(''),[loaded,setLoaded]=useState(null),[error,setError]=useState(null),[refresh,setRefresh]=useState(0),[direction,setDirection]=useState('all'),[query,setQuery]=useState(''),[page,setPage]=useState(0),[expandedRow,setExpandedRow]=useState(null);
 const formRef=useRef(null),summaryRef=useRef(null),focusTransition=useRef(false);
 const authorizationKey=salesAuthorizationKey(profile),key=JSON.stringify([authorizationKey,applied]),data=applied.productId&&draft.productId&&loaded?.key===key&&loaded.refresh===refresh?loaded.data:null,failed=error?.key===key&&error.refresh===refresh?error.message:'',loading=!!applied.productId&&!data&&!failed;
 const canPrice=profile&&!['warehouse','installer'].includes(profile.user_type)&&(profile.is_admin||['sale','system','purchase','salesHistory'].some(k=>profile.permissions?.[k]===true));
 useEffect(()=>{let live=true;setError(null);if(!applied.productId)return()=>{live=false;};const filters={...applied,withPrices:!!canPrice&&applied.withPrices};inventoryCall('material_report',{...filters,productId:Number(filters.productId),warehouseId:filters.warehouseId?Number(filters.warehouseId):null}).then(result=>{if(!live)return;if(!materialReportMatchesSelection(result,filters))throw new Error('تغيّر نطاق الكشف. أعد اختيار المادة وتحديث حركتها.');setLoaded({key,refresh,data:result});}).catch(err=>{if(live)setError({key,refresh,message:err.message||'تعذر تحميل حركة المادة. أعد المحاولة.'});});return()=>{live=false;};},[key,applied,refresh,canPrice]);
 const rows=useMemo(()=>filterMaterialRows(data?.rows||[],direction,query),[data,direction,query]),pages=Math.max(1,Math.ceil(rows.length/30)),currentPage=Math.min(page,pages-1),visible=rows.slice(currentPage*30,currentPage*30+30);
 const totals=materialVisibleTotals(rows),lastBalances=materialLastVisibleBalances(rows);
 const html=useMemo(()=>data?a4('كشف حركة مادة',materialMovementDocument(data,rows,{direction,query}),'الرصيد المتاح حاليًا: '+quantity(data.currentQty),escapeHtml(data.product.name)):'',[data,rows,direction,query,a4]);
 const invalid=!!(draft.from&&draft.to&&draft.from>draft.to);
 const showingReport=!!applied.productId;
 const product=data?.product||inventory.products.find(item=>String(item.id)===applied.productId);
 const warehouseName=applied.warehouseId?inventory.warehouses.find(item=>String(item.id)===applied.warehouseId)?.name:'جميع المخازن المسموحة';
 useEffect(()=>{
  if(!focusTransition.current)return;
  focusTransition.current=false;
  (showingReport?summaryRef:formRef).current?.focus();
 },[showingReport]);
 function clearSelection(value=''){setSearch(value);setDraft(filters=>({...filters,productId:''}));setApplied(filters=>({...filters,productId:''}));setLoaded(null);setError(null);setQuery('');setPage(0);setExpandedRow(null);}
 function apply(filters){
  if(invalid||!filters.productId||!inventory.ready)return;
  focusTransition.current=true;
  setApplied({...filters,withPrices:!!canPrice&&filters.withPrices});setRefresh(n=>n+1);
  setPage(0);setExpandedRow(null);setQuery('');setDirection('all');
 }
 function choose(product){
  if(!inventory.ready)return;
  const filters={...draft,productId:String(product.id)};
  setDraft(filters);setSearch('');apply(filters);
 }
 function editCriteria(){focusTransition.current=true;setApplied(empty);setLoaded(null);setError(null);}
 function change(k,v){setDraft(x=>({...x,[k]:v}));}
 return <section className="mlWorkspace mlCompactWorkspace" aria-label="كشف حركة مادة مفصل">
  {!showingReport?<form className="mlFilters movementReportCriteria" aria-label="معايير كشف المادة" ref={formRef} tabIndex={-1} onSubmit={e=>{e.preventDefault();apply(draft);}}>
   <MaterialMovementPicker products={inventory.products} selectedId={draft.productId} query={search} onQuery={clearSelection} onSelect={choose} onClear={()=>clearSelection()} loading={inventory.loading}/>
   <div className="mlFilterGrid"><label>المخزن<select aria-label="مخزن كشف المادة" value={draft.warehouseId} onChange={e=>change('warehouseId',e.target.value)}><option value="">جميع المخازن المسموحة</option>{inventory.warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><label>من تاريخ<input aria-label="بداية حركة المادة" type="date" value={draft.from} max={draft.to||undefined} onChange={e=>change('from',e.target.value)}/></label><label>إلى تاريخ<input aria-label="نهاية حركة المادة" type="date" value={draft.to} min={draft.from||undefined} onChange={e=>change('to',e.target.value)}/></label></div>
   <div className="mlFilterFooter">{canPrice?<label className="mlPriceSwitch"><input type="checkbox" checked={draft.withPrices} onChange={e=>change('withPrices',e.target.checked)}/>عرض الأسعار المثبتة بالمستند</label>:<span className="mlHint">كشف كميات بدون أسعار · حسب صلاحياتك</span>}<button type="submit" className="mlPrimary" disabled={!draft.productId||invalid||!inventory.ready}><AppIcon name="search" size={17}/>عرض حركة المادة</button></div>
   {invalid&&<p role="alert" className="mlError">اختر فترة صحيحة.</p>}{inventory.error&&<p role="alert" className="mlError">{inventory.error}</p>}
  </form>:<div className="movementReportResults mlReportResults">
   <header className="mlCompactProduct movementReportSummary" ref={summaryRef} tabIndex={-1}>
    <div className="mlSelectedSummary"><h2 dir="auto">{product?.name||'المادة المحددة'}</h2><p dir="auto">{[product?.brand,product?.category,product?.code&&'كود '+product.code].filter(Boolean).join(' · ')}</p>
     <small>{[warehouseName,materialReportPeriod(applied.from,applied.to),applied.withPrices&&canPrice?'بالأسعار · IQD':'بدون أسعار'].filter(Boolean).join(' · ')}</small></div>
    {data&&<div className="mlCurrentMetric"><small>المتاح حاليًا</small><strong data-testid="material-current-qty"><bdi>{quantity(data.currentQty)}</bdi></strong></div>}
    <button type="button" className="movementReportEdit" onClick={editCriteria}><AppIcon name="edit" size={16}/>تعديل معايير الكشف</button>
   </header>
   {failed?<div className="mlError" role="alert">{failed}<button type="button" onClick={()=>setRefresh(n=>n+1)}>إعادة المحاولة</button></div>:loading?<div role="status" className="mlEmpty">جاري تحميل حركة المادة…</div>:data&&<>
   <section className="mlTableSection" aria-label="حركات المادة">
    <div className="mlResultTools"><div className="mlDirection" role="group" aria-label="اتجاه حركة المادة">{[['all','الكل'],['in','دخول'],['out','خروج']].map(([k,v])=><button type="button" key={k} aria-pressed={direction===k} onClick={()=>{setDirection(k);setPage(0);setExpandedRow(null);}}>{v}</button>)}</div><input aria-label="بحث تفاصيل حركة المادة" value={query} onChange={e=>{setQuery(e.target.value);setPage(0);setExpandedRow(null);}} placeholder="وصل، عميل، مورد أو بيان…"/></div>
    <div className="mlTableCaption"><span><b>{quantity(rows.length)}</b> حركة{rows.length!==data.rows.length&&<> من {quantity(data.rows.length)}</>}</span><span>+ دخول <i>·</i> − خروج</span><small className="mlScrollHint">اسحب الجدول لعرض بقية الأعمدة</small></div>
    <div className="mlCompactTableScroll" role="region" aria-label="جدول حركة المادة" tabIndex={0}>
     <table className={'mlCompactTable'+(data.withPrices?' withPrices':'')} data-testid="material-movement-table">
      <caption>حركة {data.product.name} · الرصيد بعد كل حركة يخص المخزن المذكور في صفها</caption>
      <colgroup><col className="mlColDate"/><col className="mlColType"/><col className="mlColQuantity"/>{data.withPrices&&<col className="mlColPrice"/>}<col className="mlColParty"/><col className="mlColReceipt"/><col className="mlColBalance"/></colgroup>
      <thead><tr><th scope="col">التاريخ</th><th scope="col">نوع الحركة</th><th scope="col">الكمية</th>{data.withPrices&&<th scope="col">سعر الوحدة</th>}<th scope="col">المورّد / العميل</th><th scope="col">رقم الوصل</th><th scope="col" className="mlBalanceColumn">الرصيد بعد الحركة</th></tr></thead>
      <tbody>{visible.map(r=>{const presentation=materialMovementPresentation(r),signed=materialSignedQuantity(r),price=data.withPrices?materialPrice(r):null,expanded=expandedRow===r.id,time=movementTime(r.date),detailsId='material-movement-detail-'+encodeURIComponent(String(r.id));return <Fragment key={r.id}>
       <tr className={'mlCompactRow '+signed.direction+(presentation.isReservation?' reservation':'')} data-movement-id={r.id}>
        <td className="mlCellDate"><time>{time.split(',')[0]}</time><small>{time.split(',').slice(1).join(',').trim()}</small></td>
        <td className="mlCellType"><button type="button" className="mlRowDetailButton" aria-label={'تفاصيل الحركة '+(r.receiptNo??r.id)} aria-expanded={expanded} aria-controls={detailsId} onClick={()=>setExpandedRow(expanded?null:r.id)}><span>{presentation.label}</span><AppIcon name="chevron" size={13}/></button></td>
        <td className={'mlSignedQuantity '+signed.direction} data-testid="material-row-quantity"><bdi>{signed.text}</bdi></td>
        {price&&<td className="mlCellPrice" data-testid="material-row-price"><bdi>{price.unit}</bdi></td>}
        <td className="mlCellParty"><span dir="auto">{r.party||'غير مسجل'}</span><small><AppIcon name="warehouse" size={11}/>{r.warehouseName}</small></td>
        <td className="mlCellReceipt"><bdi>{r.receiptNo??'—'}</bdi></td>
        <td className="mlBalanceColumn mlCellBalance" data-testid="material-row-balance" data-balance={r.balance}><bdi>{quantity(r.balance)}</bdi></td>
       </tr>
       {expanded&&<tr className="mlExpandedRow" data-movement-detail={r.id} id={detailsId}><td colSpan={data.withPrices?7:6}><div className="mlExpandedContent">
        <div><span>{presentation.partyLabel}</span><b dir="auto">{r.party||'غير مسجل'}</b></div><div><span>المخزن</span><b>{r.warehouseName}</b></div><div><span>المستخدم</span><b>{r.createdByName||'غير مسجل'}</b></div>
        {presentation.preparationApplicable&&<><div><span>{presentation.preparerLabel}</span><b>{r.preparedByName||'لم يُسجّل تجهيز'}</b></div><div><span>حالة التجهيز</span><b>{presentation.preparationLabel}</b></div>{r.preparedAt&&<div><span>وقت التجهيز</span><b>{movementTime(r.preparedAt)}</b></div>}</>}
        {r.executedByName&&r.executedByName!==r.createdByName&&<div><span>منفّذ الحركة</span><b>{r.executedByName}</b></div>}{price&&<div><span>{price.label}</span><b>مبلغ الفقرة: {price.total}</b></div>}
        {presentation.stockNote&&<p className="mlExpandedStockNote">{presentation.stockNote}</p>}{r.note&&<p><b>البيان: </b>{r.note}</p>}
       </div></td></tr>}
      </Fragment>;})}{!visible.length&&<tr><td className="mlTableEmpty" colSpan={data.withPrices?7:6}>لا توجد حركة مطابقة ضمن الفترة والبحث.</td></tr>}</tbody>
      <tfoot><tr><th scope="row" colSpan={2}>إجمالي كل نتائج الكشف</th><td className="mlTableTotals"><span className="in"><bdi>{totals.in?'+':''}{quantity(totals.in)}</bdi></span><span className="out"><bdi>{totals.out?'−':''}{quantity(totals.out)}</bdi></span></td><td colSpan={data.withPrices?3:2}>الدخول والخروج · جميع الصفحات</td><td className="mlBalanceColumn mlBalanceFootnote">لكل مخزن رصيده</td></tr></tfoot>
     </table>
    </div>
    {lastBalances.length>0&&<div className="mlLastBalances" data-testid="material-last-balances"><span>الرصيد بعد آخر حركة في نتائج الكشف <small>· جميع الصفحات</small></span><div>{lastBalances.map(w=><span key={w.warehouseId??w.warehouseName} data-last-warehouse={w.warehouseId??w.warehouseName} data-testid="material-last-balance" data-warehouse-id={w.warehouseId??undefined} data-balance={w.balance}><small>{w.warehouseName}</small><bdi>{quantity(w.balance)}</bdi></span>)}</div></div>}
    <p className="mlTableNote">الرصيد بعد الحركة هو المتاح في مخزنها. افتح نوع الحركة لعرض تفاصيلها.</p>
    {pages>1&&<nav className="mlPagination" aria-label="صفحات كشف المادة"><button disabled={!currentPage} onClick={()=>{setPage(n=>n-1);setExpandedRow(null);}}>السابق</button><span>{currentPage+1} / {pages}</span><button disabled={currentPage+1>=pages} onClick={()=>{setPage(n=>n+1);setExpandedRow(null);}}>التالي</button></nav>}
   </section>
   <ReportActions showPrint enabled={!!data} html={html} filename={'حركة-مادة-'+data.product.code+(data.withPrices?'-بالأسعار':'-بدون-أسعار')}/>
   <details className="mlSupplement"><summary><AppIcon name="warehouse" size={17}/><span>ملخص المخازن وتوضيح الأرصدة</span><small>{quantity(data.warehouses.length)} مخزن</small></summary><div className="mlSupplementBody">
    <p className="mlHint">الأرصدة أدناه تخص أول وآخر حركة ظاهرة لكل مخزن؛ المتاح حاليًا مستقل عن الفترة. البحث والاتجاه يغيّران الصفوف المعروضة دون إعادة احتساب أرصدتها.</p>
    <div className="mlWarehouseGrid">{data.warehouses.map(w=><article key={w.id}><h3><AppIcon name="package" size={17}/>{w.name}</h3><div><span>الرصيد قبل أول حركة<b>{w.beforeFirst==null?'—':quantity(w.beforeFirst)}</b></span><span className="mlPeriodIn">الدخول خلال الفترة<b>{quantity(w.inQty)}</b></span><span className="mlPeriodOut">الخروج خلال الفترة<b>{quantity(w.outQty)}</b></span><span>الرصيد بعد آخر حركة<b>{w.afterLast==null?'—':quantity(w.afterLast)}</b></span><span className="mlCurrentStock">المتاح حاليًا<b>{quantity(w.currentQty)}</b></span></div></article>)}</div>
    {data.scope==='own'&&<p className="mlHint">تظهر وصولاتك المسموحة فقط؛ الرصيد المخزني يحتسب كامل حركات المخزن حتى لو كانت لمستخدم آخر.</p>}
    {(totals.reservedOut>0||totals.reservationReleased>0)&&<p className="mlReservationSummary">الحجز ضمن الخروج الظاهر: <bdi>{quantity(totals.reservedOut)}</bdi> · إلغاء الحجز ضمن الدخول: <bdi>{quantity(totals.reservationReleased)}</bdi>. هذه تغييرات في المتاح، وقد تسبق التسليم الفعلي.</p>}
    <p className="mlHint">{data.withPrices?'الأسعار بالدينار كما ثُبّتت في المستند. سعر مادة المنظومة لا يُخمّن من السعر الإجمالي.':'الكشف الحالي بدون أسعار.'} ملف PDF يشمل جميع نتائج البحث. حجز النقل يقلل المتاح من المصدر؛ الدخول للوجهة يُسجّل بعد اعتماد التجهيز.</p>
   </div></details>
  </>}</div>}
 </section>;
}
