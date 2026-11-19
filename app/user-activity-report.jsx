'use client';
import {useMemo} from 'react';
import ReportActions from './report-actions';
import {userActivityDocument} from './user-activity-document.mjs';

export default function UserActivityReport({data,a4}){
 const report=useMemo(()=>{
  const doc=userActivityDocument(data);
  return doc?{filename:doc.filename,html:a4(doc.title,doc.body,'',doc.subtitle)}:null;
 },[data,a4]);
 if(!report)return null;
 return <section className="activityCard" aria-label="تقرير نشاط المستخدم">
  <h3>تقرير نشاط المستخدم</h3>
  <ReportActions enabled html={report.html} filename={report.filename}/>
 </section>;
}
