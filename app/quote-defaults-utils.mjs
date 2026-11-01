export const QUOTE_EXPENSE_FIELDS=[['crane','كرين',40000],['worker','عامل',25000],['programmer','مبرمج',40000],['delivery','توصيل',25000],['electrical','كهربائيات',200000],['commission','عمولة المندوب',75000]];
export const QUOTE_PANEL_EXPENSE=45000;
export const quoteExpenseValue=(form,key)=>form.expenses?.[key]??(key==='commission'?'0':undefined);
export function quoteDefaultValues(form){return {perPanel:String(form.perPanel??''),expenses:Object.fromEntries(QUOTE_EXPENSE_FIELDS.map(([key])=>[key,String(quoteExpenseValue(form,key)??'')]))};}
export function applyQuoteDefaults(form,defaults){return {...form,schema:Math.max(5,Number(form.schema)||0),...quoteDefaultValues(defaults),expenseDefaultsRevision:defaults.revision??null};}
export function quoteDefaultsError(values){
 for(const [key,label]of[['perPanel','مصاريف كل لوح'],...QUOTE_EXPENSE_FIELDS]){
  const value=key==='perPanel'?values.perPanel:values.expenses?.[key],s=String(value??'');
  if(!/^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$/.test(s)||!Number.isFinite(Number(s))||Number(s)>1e10)return 'أدخل '+label+' بصورة صحيحة، بدون سالب وبحد أقصى منزلتين عشريتين.';
 }
 return '';
}
const prefix='solar-quote-default-attempt-v1:';
export function quoteDefaultsAttempt(storage,userId){
 const key=prefix+userId;
 return {
  read(){try{const x=JSON.parse(storage?.getItem(key)||'null');return x&&typeof x.id==='string'&&x.payload&&typeof x.payload==='object'?x:null}catch{return null}},
  write(x){storage?.setItem(key,JSON.stringify(x));},
  clear(){storage?.removeItem(key);}
 };
}
