import {canOpenPage,isAdministrator,isEngineer,isWarehouse} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

export function searchCategories(profile){
 if(!profile?.active)return ['all'];
 const financial=!isEngineer(profile)&&!isWarehouse(profile),admin=isAdministrator(profile);
 return ['all',
  ...(financial&&canOpenPage(profile,'customers')?['customers']:[]),
  ...(!isEngineer(profile)&&(isWarehouse(profile)||admin||['stock','stockMovement','warehouse','sale','system','purchase'].some(id=>canOpenPage(profile,id)))?['products']:[]),
  ...(financial&&canOpenPage(profile,'suppliers')?['suppliers']:[])];
}
export function searchSections(sections,profile,query){
 const words=normalizeSearch(query).split(/\s+/).filter(Boolean);
 if(!words.length)return [];
 return sections.flatMap(([,rows])=>rows).filter(([id,label])=>canOpenPage(profile,id)&&words.every(w=>normalizeSearch(label).includes(w)));
}
export function balanceCaption(balance,supplier=false){
 const n=Number(balance||0);
 return n===0?'الحساب مسدد':supplier?(n>0?'مستحق للمورد':'رصيدنا عند المورد'):(n>0?'مطلوب من الزبون':'رصيد للزبون');
}
