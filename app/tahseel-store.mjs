export function quoteStore(client) {
  return {
    async list(userId) {
      const rows=[];
      for(let offset=0;;offset+=1000){
        const {data,error}=await client.from('solar_quotes').select('*').eq('user_id',userId).order('updated_at',{ascending:false}).order('id').range(offset,offset+999);
        if(error)throw new Error('تعذر تحميل المسودات. تأكد من الاتصال وتفعيل تحديث التحصيل.');
        rows.push(...data);if(data.length<1000)return rows;
      }
    },
    async save({id,revision,userId,payload}) {
      const table=client.from('solar_quotes');
      const request=revision
        ?table.update({payload,revision:revision+1,updated_at:new Date().toISOString()}).eq('id',id).eq('user_id',userId).eq('revision',revision)
        :table.insert({id,user_id:userId,payload});
      const {data,error}=await request.select('*').single();
      if(error||!data)throw new Error(revision?'تعذر الحفظ؛ ربما عُدلت المسودة من جهاز آخر. حدّث المسودات وافتح النسخة الحالية.':'تعذر حفظ المسودة. حدّث القائمة للتحقق من الحفظ قبل المحاولة مرة أخرى.');
      return data;
    },
    async remove(row,userId) {
      const {data,error}=await client.from('solar_quotes').delete().eq('id',row.id).eq('user_id',userId).eq('revision',row.revision).select('id');
      if(error||data?.length!==1)throw new Error('لم تُحذف المسودة؛ حدّث القائمة وحاول مجدداً.');
    },
  };
}

export function limitedQuoteStore(client){
 const call=async(action,args={})=>{const {data,error}=await client.rpc('solar_limited_quote',{action,...args});if(error)throw new Error(error.message||'تعذر احتساب العرض. حاول مجدداً.');return data};
 return {
  preview:payload=>call('preview',{quote_payload:payload}),
  async list(){const rows=[];for(let offset=0;;offset+=100){const page=await call('list',{page_offset:offset});rows.push(...page);if(page.length<100)return rows}},
  save:({id,revision,payload})=>call('save',{quote_id:id,expected_revision:revision||null,quote_payload:payload}),
  remove:row=>call('delete',{quote_id:row.id,expected_revision:row.revision}),
 };
}
