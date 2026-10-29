'use client';
import {useEffect,useRef,useState} from 'react';
import {createPdfDocument,downloadPreparedPdf,sharePreparedPdf} from './pdf-share.mjs';
import {previewPdf} from './pdf-preview.mjs';

export {default as ReportIcon} from './app-icons';
import ReportIcon from './app-icons';
export default function ReportActions({html='',filename='تقرير',enabled=false,disabledNotice='اختر البيانات لعرض التقرير وتصديره.'}){
 const [prepared,setPrepared]=useState(null),[failed,setFailed]=useState(false),[notice,setNotice]=useState(''),[sharing,setSharing]=useState(false),[retry,setRetry]=useState(0);const lock=useRef(false);
 useEffect(()=>{let live=true;setPrepared(null);setFailed(false);setNotice('');if(!enabled||!html)return()=>{live=false};
  const timer=setTimeout(()=>createPdfDocument(html).then(result=>{if(live)setPrepared({html,result});}).catch(()=>{if(live)setFailed(true);}),350);
  return()=>{live=false;clearTimeout(timer);};
 },[html,enabled,retry]);
 const ready=enabled&&prepared?.html===html&&!failed,result=ready?prepared.result:null;
 async function share(){if(!result||lock.current)return;lock.current=true;setSharing(true);setNotice('');try{const action=await sharePreparedPdf(filename,result.blob);if(action==='downloaded')setNotice('تم حفظ PDF؛ المشاركة المباشرة غير متاحة في هذا المتصفح. شاركه من التنزيلات.');else if(action==='shared')setNotice('تمت مشاركة ملف PDF.');}catch{setNotice('تعذرت المشاركة. حاول مجدداً أو احفظ PDF.');}finally{lock.current=false;setSharing(false);}}
 return <div className="reportExport"><div className="reportExportButtons"><button type="button" className="reportButton preview" disabled={!enabled||!html||sharing} onClick={()=>previewPdf(html,filename,result)}><ReportIcon name="preview"/>معاينة</button><button type="button" className="reportButton download" disabled={!ready||sharing} onClick={()=>{downloadPreparedPdf(filename,result.blob);setNotice('تم إرسال ملف PDF إلى التنزيلات.');}}><ReportIcon name="download"/>حفظ PDF</button><button type="button" className="reportButton share" disabled={!ready||sharing} onClick={share}><ReportIcon name="share"/>{sharing?'جاري المشاركة…':'مشاركة'}</button></div><div className="reportExportStatus" role="status">{notice||(!enabled?disabledNotice:failed?'تعذر تجهيز المستند.':ready?'المستند جاهز · '+result.pages.length+' صفحة PDF':'جاري تجهيز المستند…')}{failed&&<button type="button" className="reportRetry" onClick={()=>setRetry(n=>n+1)}>إعادة التجهيز</button>}</div></div>;
}
