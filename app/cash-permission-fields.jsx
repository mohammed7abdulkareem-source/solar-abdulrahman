'use client';
import {cashPermissionOptions} from './cash-permissions.mjs';
export default function CashPermissionFields({value,onChange}){
 return <section className="cashPermissionFields"><h4>صلاحيات الصندوق</h4><div className="cashPermissionGrid">{cashPermissionOptions.map(([key,label])=><label key={key} className={'cashPermissionOption'+(value[key]?' selected':'')}><input type="checkbox" aria-label={label} checked={value[key]===true} onChange={e=>onChange({...value,[key]:e.target.checked,...(e.target.checked?{cash:true}:{})})}/><b>{label}</b></label>)}</div><p className="customerPermissionNote">كل إجراء له صلاحية مستقلة. أدوات الإدارة تعدّل قاصة المستخدم نفسه فقط؛ جميع القاصات تبقى للأدمن.</p></section>;
}
