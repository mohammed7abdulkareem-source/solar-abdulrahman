'use client';
import AppIcon from './app-icons';
import PhoneActions from './phone-actions';
import {installationIndex,installationStages} from './installation-utils.mjs';
import './installation-handoff.css';

const timeFormat=new Intl.DateTimeFormat('ar-IQ',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'});
export function installationReviewer(job){
 return job.reviewerIsAdminTeam?'الإدارة':job.responsibleName||job.creatorName||'الإدارة';
}
export function installationStageLabel(job){
 if(job.installationStatus==='in_progress'&&job.installationReview?.status==='returned')return 'تصحيح التقرير';
 if(job.installationStatus==='completed'&&!job.installationReport?.submittedAt)return 'مراجعة الملف';
 return installationStages[installationIndex(job.installationStatus)][1];
}
function nextStep(job,engineer,reviewer){
 const review=job.installationReview;
 if(job.installationStatus==='closed')return review?.status==='approved'&&review.actorName?'اعتمد '+review.actorName+' ملف التنصيب وأغلقه.':'تم إغلاق ملف التنصيب.';
 if(job.warehouseStatus!=='ready')return 'بانتظار تجهيز مواد الوصل من المخزن.';
 if(review?.status==='reopened'&&job.installationStatus==='completed')return 'أُعيد فتح الملف. يراجع '+reviewer+' المصاريف والغلق.';
 if(job.installationStatus==='completed')return job.installationReport?.submittedAt?'التقرير بانتظار مراجعة '+reviewer+'.':'الملف بانتظار مراجعة '+reviewer+'.';
 if(!job.installerId)return 'يتابع '+reviewer+' ملف التنصيب.';
 if(review?.status==='returned')return 'يصحّح '+engineer+' التقرير ويعيد إرساله إلى '+reviewer+'.';
 return job.installationStatus==='in_progress'?'يُكمل '+engineer+' التنصيب ويرسل التقرير إلى '+reviewer+'.':'يبدأ '+engineer+' التنصيب.';
}

export default function InstallationHandoff({job,field=false}){
 const engineer=job.installerName||'مهندس التنصيب';
 const manager=job.responsibleName||job.creatorName||'غير مسند';
 const reviewer=installationReviewer(job),review=job.installationReview;
 const managerPhone=job.responsibleId?job.responsiblePhone:job.creatorPhone;
 const returned=review?.status==='returned'&&job.installationStatus==='in_progress';
 const index=installationIndex(job.installationStatus);
 const officeOnly=!job.installerId||(index>=2&&!job.installationReport?.submittedAt&&!job.installationStartedAt);
 const stages=officeOnly?[['pending','تجهيز المخزن'],['completed','مراجعة الملف'],['closed','ملف مغلق']]:installationStages;
 return <section className="installationHandoff" aria-label="متابعة الوصل بين المهندس والمسؤول" data-handoff-state={returned?'returned':job.installationStatus}>
  <dl className="installationParties">
   <div><dt><AppIcon name="tools" size={15}/>مهندس التنصيب</dt><dd>{job.installerName||'غير مسند'}</dd></div>
   <div><dt><AppIcon name="user" size={15}/>المستخدم المسؤول</dt><dd>{manager}</dd></div>
  </dl>
  <div className="installationNextStep"><span>الخطوة الحالية</span><strong>{nextStep(job,engineer,reviewer)}</strong>
   {review?.at&&<small><time dateTime={review.at}>{timeFormat.format(new Date(review.at))}</time>
    {returned&&review.actorName&&' · أعاده '+review.actorName}</small>}
   {returned&&review.notes&&<p><b>سبب الإعادة</b> {review.notes}</p>}
  </div>
  <ol className="workflowSteps" aria-label="مراحل التنصيب">{stages.map(([stage,label],i)=>
   <li key={stage} className={installationIndex(stage)<=index?'reached':''} aria-current={stage===job.installationStatus?'step':undefined}>
    <span>{installationIndex(stage)<index||job.installationStatus==='closed'?'✓':i+1}</span><small>{returned&&stage==='in_progress'?'تصحيح التقرير':label}</small>
   </li>)}</ol>
  {managerPhone&&<div className="installationHandoffContact jobResponsible"><span>التواصل مع المسؤول</span>
   <PhoneActions phone={managerPhone} label={'بالمسؤول '+manager}/></div>}
  {!field&&job.installerPhone&&<div className="installationHandoffContact"><span>التواصل مع المهندس</span>
   <PhoneActions phone={job.installerPhone} label={'بالمهندس '+engineer}/></div>}
 </section>;
}
