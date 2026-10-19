'use client';
import AppIcon from './app-icons';
import {sections} from './section-directory.mjs';
import {orderedSections} from './section-layout-utils.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

const groups=[
 {id:'sales',title:'المبيعات والعملاء',description:'عمليات البيع وإدارة العملاء',icon:'receipt',color:'green',fixedOrder:true,ids:['sale','system','salesHistory','customerCreate','customerPayment','systemPayment','customerDebts','customerStatement','customers']},
 {id:'purchases',title:'المشتريات والموردون',description:'المشتريات وحسابات الموردين',icon:'truck',color:'blue',ids:['purchase','suppliers','supplierPayment','supplierStatement','supplierBalances']},
 {id:'inventory',title:'المخزون والمواد',description:'المواد والمخازن والحركة والتنصيبات',icon:'warehouse',color:'orange',ids:['products','stock','stockMovement','warehouse','installations','brands']},
 {id:'finance',title:'المالية والحسابات',description:'الصندوق والقاصات والتقارير المالية',icon:'coins',color:'violet',ids:['cash','capital','cashTransfers','profit','exchangeRate']},
 {id:'reports',title:'التقارير والإدارة',description:'التحصيل والضمان',icon:'chart',color:'rose',ids:['tahseel','warranty']},
 {id:'settings',title:'الإعدادات والنظام',description:'المستخدمون والتحديثات',icon:'settings',color:'slate',ids:['users','updates']}
];
const all=sections.flatMap(([,rows])=>rows),labels=new Map(all);
export default function GroupedSectionDirectory({profile,order=[],query='',onNavigate}){
 const filtered=groups.map(group=>({...group,rows:orderedSections(group.ids.map(id=>[id,labels.get(id)]).filter(([id])=>canOpenPage(profile,id)),group.fixedOrder?[]:order)
  .filter(([,label])=>normalizeSearch(label).includes(normalizeSearch(query)))})).filter(g=>g.rows.length);
 return <nav className="groupedSectionDirectory" aria-label="أقسام البرنامج حسب المجموعات">{filtered.map(group=><details open className={'sectionCategory '+group.color} key={group.id} style={{'--category-mobile-columns':group.rows.length<=3?group.rows.length:group.rows.length<=6||group.rows.length%3===0?3:4}}>
  <summary><div className="sectionCategoryTitle"><span className="sectionCategoryArrow"><AppIcon name="chevron" size={15}/></span><div><h2>{group.title}</h2><p>{group.description}</p></div></div><span className="sectionCategoryCount">{group.rows.length===1?'قسم واحد':group.rows.length===2?'قسمان':group.rows.length+' أقسام'}</span><span className="sectionCategoryIcon"><AppIcon name={group.icon} size={24}/></span></summary>
  <div className="sectionCategoryLinks">{group.rows.map(([id,label])=><a key={id} href={'/?section='+id} onClick={e=>{e.preventDefault();onNavigate(id);}}><AppIcon name={id} size={23}/><span>{label}</span></a>)}</div>
 </details>)}{!filtered.length&&<p className="uiEmpty">لا يوجد قسم بهذا الاسم.</p>}</nav>;
}
