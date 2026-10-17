'use client';
import {useEffect,useRef,useState} from 'react';
import {createPdfDocument,downloadPreparedPdf,sharePreparedPdf} from './pdf-share.mjs';
import {previewPdf} from './pdf-preview.mjs';

export function ReportIcon({name,...props}){
 const paths={preview:<><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></>,download:<><path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/></>,share:<><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 10.5 6.8-4m-6.8 7 6.8 4"/></>,users:<><circle cx="9" cy="8" r="4"/><path d="M2 21v-2a7 7 0 0 1 14 0v2M17 4a4 4 0 0 1 0 8m2 9v-2a7 7 0 0 0-3-6"/></>,search:<><circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/></>,refresh:<><path d="M20 7v5h-5M4 17v-5h5M6 5a8 8 0 0 1 14 7M4 12a8 8 0 0 0 14 7"/></>,document:<><path d="M14 2H4v20h16V8L14 2Z"/><path d="M14 2v6h6M8 12h8m-8 4h8"/></>,wallet:<><path d="M3 7h18v14H3zM3 7V3h15v4m-2 5h5v5h-5z"/></>};
 return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}>{paths[name]||paths.document}</svg>;
}
export default function ReportActions({html='',filename='تقرير',enabled=false}){
 const [prepared,setPrepared]=useState(null),[failed,setFailed]=useState(false),[notice,setNotice]=useState(''),[sharing,setSharing]=useState(false),[retry,setRetry]=useState(0);const lock=useRef(false);
 useEffect(()=>{let live=true;setPrepared(null);setFailed(false);setNotice('');if(!enabled||!html)return()=>{live=false};
  const timer=setTimeout(()=>createPdfDocument(html).then(result=>{if(live)setPrepared({html,result});}).catch(()=>{if(live)setFailed(true);}),350);
  return()=>{live=false;clearTimeout(timer);};
 },[html,enabled,retry]);
 const ready=enabled&&prepared?.html===html&&!failed,result=ready?prepared.result:null;
 async function share(){if(!result||lock.current)return;lock.current=true;setSharing(true);setNotice('');try{const action=await sharePreparedPdf(filename,result.blob);if(action==='downloaded')setNotice('تم حفظ PDF؛ المشاركة المباشرة غير متاحة في هذا المتصفح. شاركه من التنزيلات.');else if(action==='shared')setNotice('تمت مشاركة ملف PDF.');}catch{setNotice('تعذرت المشاركة. حاول مجدداً أو احفظ PDF.');}finally{lock.current=false;setSharing(false);}}
 return <div className="reportExport"><div className="reportExportButtons"><button type="button" className="reportButton preview" disabled={!ready||sharing} onClick={()=>previewPdf(html,filename,result)}><ReportIcon name="preview"/>معاينة</button><button type="button" className="reportButton download" disabled={!ready||sharing} onClick={()=>{downloadPreparedPdf(filename,result.blob);setNotice('تم إرسال ملف PDF إلى التنزيلات.');}}><ReportIcon name="download"/>حفظ PDF</button><button type="button" className="reportButton share" disabled={!ready||sharing} onClick={share}><ReportIcon name="share"/>{sharing?'جاري المشاركة…':'مشاركة'}</button></div><div className="reportExportStatus" role="status">{notice||(!enabled?'اختر البيانات لعرض التقرير وتصديره.':failed?'تعذر تجهيز المستند.':ready?'المستند جاهز · '+result.pages.length+' صفحة PDF':'جاري تجهيز المستند…')}{failed&&<button type="button" className="reportRetry" onClick={()=>setRetry(n=>n+1)}>إعادة التجهيز</button>}</div></div>;
}
