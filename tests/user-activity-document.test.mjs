import test from 'node:test';
import assert from 'node:assert/strict';
import {userActivityDocument} from '../app/user-activity-document.mjs';
import {a4} from '../app/document-template.mjs';

const sample={
 user:{id:'staff-id',name:'زيد <اسم>',userType:'warehouse'},from:'2026-10-30',to:'2026-11-01',
 sales:{count:2,totalIQD:650,wholesaleIQD:320,systemIQD:330,wholesaleCount:1,systemCount:1},
 profit:{earnedIQD:-102.5,remainingIQD:592.2},debts:{dueIQD:800,creditIQD:30},
 cash:{IQD:911,USD:5.25},operations:{warehouse:{prepared:4,edited:0,reopened:1,transfersPrepared:2}},
 performance:{granularity:'day',eligibleSalesIQD:300,companyProfitIQD:-35.5,marginPercent:-11.83,
  approvedShareIQD:103,approvedShareCount:2,approvedShareBaseIQD:500,approvedSharePercent:20.6,
  series:[{start:'2026-10-30',end:'2026-10-30',salesIQD:320,companyProfitIQD:40,invoiceCount:1},
   {start:'2026-10-31',end:'2026-10-31',salesIQD:0,companyProfitIQD:0,invoiceCount:0},
   {start:'2026-11-01',end:'2026-11-01',salesIQD:330,companyProfitIQD:-75.5,invoiceCount:1}]}
};
test('the selected employee, applied period and signed company and personal bases survive in the printed report',()=>{
 const {title,subtitle,body,filename}=userActivityDocument(sample);
 assert.equal(title,'تقرير نشاط المستخدم');
 assert.match(subtitle,/زيد &lt;اسم&gt;.*المخزن.*2026-10-30.*2026-11-01/);
 assert.match(filename,/2026-10-30-2026-11-01$/);
 const html=a4(title,body,'',subtitle);
 assert.doesNotMatch(html,/<اسم>/);
 for(const value of ['-35.5','-11.83','-102.5','592.2','103','20.6','500','325','5.25'])assert.ok(body.includes('>'+value+'</bdi>'),value);
 assert.match(body,/نشاط المخزن خلال الفترة/);assert.doesNotMatch(body,/نشاط التنصيب/);
 assert.match(body,/حصة المستخدم المعتمدة بالتسويات/);assert.match(body,/قبل توزيع الأرباح/);
 assert.match(body,/تسويات حصة المستخدم خلال الفترة/);assert.match(body,/صافي نتيجة المستخدم خلال الفترة/);
});
test('plots use real chronological amounts and keep negative profits below zero, with tabular amounts and dates',()=>{
 const {body}=userActivityDocument(sample);
 const figure=key=>body.split('<figure data-activity-chart="'+key+'">')[1].split('</figure>')[0];
 const values=figure('companyProfitIQD').match(/<polyline points="([^"]+)"/)[1].split(' ').map(point=>point.split(',').map(Number));
 const baseline=Number(figure('companyProfitIQD').match(/ y1="([^"]+)"/)[1]);
 assert.equal(values.length,3);
 assert.ok(values[0][0]<values[1][0]&&values[1][0]<values[2][0]);
 assert.ok(values[0][1]<baseline);assert.equal(values[1][1],baseline);assert.ok(values[2][1]>baseline);
 assert.notEqual(figure('salesIQD').match(/<polyline points="([^"]+)"/)[1],figure('companyProfitIQD').match(/<polyline points="([^"]+)"/)[1]);
 assert.match(body,/<td><bdi>2026-11-01<\/bdi><\/td><td><bdi dir="ltr">1<\/bdi><\/td><td><bdi dir="ltr">330<\/bdi><\/td><td><bdi dir="ltr">-75.5<\/bdi>/);
});
test('empty, flat and unreported metrics stay distinct',()=>{
 assert.equal(userActivityDocument(null),null);
 assert.equal(userActivityDocument({...sample,performance:null}),null);
 const performance={...sample.performance,marginPercent:null,approvedSharePercent:null,series:[]};
 const {body,subtitle}=userActivityDocument({...sample,from:null,sales:{count:0,totalIQD:0},performance});
 assert.ok(subtitle.includes('البداية'));assert.doesNotMatch(body,/<figure /);
 assert.ok(body.includes('لا توجد بيانات زمنية للفترة المختارة'));assert.ok(body.includes('غير محتسب'));
 assert.ok(body.includes('غير متاح'));assert.doesNotMatch(body,/NaN|Infinity/);
 const series=[{start:'2026-11-01',end:'2026-11-01',salesIQD:0,companyProfitIQD:0,invoiceCount:0}];
 const flat=userActivityDocument({...sample,performance:{...performance,series}}).body;
 assert.equal(flat.match(/data-activity-chart=/g)?.length,2);assert.doesNotMatch(flat,/NaN|Infinity/);
});
