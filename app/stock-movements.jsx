'use client';
import {useEffect,useRef,useState} from 'react';
import dynamic from 'next/dynamic';
import AppIcon from './app-icons';
import {useWarehouseInventory} from './warehouse-data';
import {salesAuthorizationKey} from './sales-read-scope.mjs';
import MovementCriteriaReport from './movement-criteria-report';
import './movement-report-workspace.css';

const MaterialMovementLedger=dynamic(()=>import('./material-movement-ledger'));
const reports=[
 {id:'ledger',title:'حركة مادة محددة',icon:'package',description:'دخول المادة وخروجها والرصيد بعد كل حركة.'},
 {id:'customer',title:'مادة وعميل',icon:'customers',description:'مشتريات عميل واحد من مادة تختارها.'},
 {id:'materials',title:'جميع الحركات',icon:'exchange',description:'حركات المواد في المخازن حسب الفترة والمستند.'}
];

function SelectedReport({report,profile,a4}){
 const inventory=useWarehouseInventory({aggregate:true});
 if(report.id==='ledger')return <MaterialMovementLedger profile={profile} inventory={inventory} a4={a4}/>;
 return <MovementCriteriaReport mode={report.id} inventory={inventory} a4={a4}/>;
}
function MovementWorkspace({profile,a4}){
 const [report,setReport]=useState(null);
 const heading=useRef(null),previousMode=useRef(null);
 useEffect(()=>{
  if(report)heading.current?.focus();
  else if(previousMode.current)document.querySelector('[data-movement-mode="'+previousMode.current+'"]')?.focus();
 },[report]);
 function open(choice){previousMode.current=choice.id;setReport(choice);}

 return <section className="movementWorkspace movementReportWorkspace" data-active-movement-mode={report?.id||'chooser'}>
  <header className="workspaceHead movementReportHeader">
   <div><h1 ref={heading} tabIndex={-1}>{report?.title||'حركة المواد'}</h1>{!report&&<p>اختر الكشف الذي تريد عرضه.</p>}</div>
   {report&&<button type="button" className="movementReportBack" onClick={()=>setReport(null)}><AppIcon name="arrow" size={17}/>تغيير نوع الكشف</button>}
  </header>
  {report?<SelectedReport key={report.id} report={report} profile={profile} a4={a4}/>:<div className="movementReportChoices" aria-label="نوع كشف الحركة">
   {reports.map(choice=><button key={choice.id} type="button" className="movementReportChoice" aria-label={choice.title} data-movement-mode={choice.id} onClick={()=>open(choice)}>
    <span className="movementChoiceIcon"><AppIcon name={choice.icon} size={23}/></span>
    <span className="movementChoiceText"><strong>{choice.title}</strong><small>{choice.description}</small></span><AppIcon name="chevron" size={19}/>
   </button>)}
  </div>}
 </section>;
}
export default function StockMovements({profile,a4}){
 return <MovementWorkspace key={salesAuthorizationKey(profile)} profile={profile} a4={a4}/>;
}
