// Quantities are not money: a saved nonzero fraction must never display as 0.
// Format the decimal representation directly, retaining numeric-string precision.
export function materialQuantity(value){
 if(value==null||String(value).trim()==='')return '—';
 const text=String(value).trim(),match=/^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(text);
 if(!match)return '—';
 const exponent=Number(match[4]||0);
 if(!Number.isFinite(exponent)||Math.abs(exponent)>100)return text;
 const digits=match[2]+(match[3]||''),point=match[2].length+exponent;
 let integer=point<=0?'0':point>=digits.length?digits+'0'.repeat(point-digits.length):digits.slice(0,point);
 let fraction=point<=0?'0'.repeat(-point)+digits:point>=digits.length?'':digits.slice(point);
 integer=integer.replace(/^0+(?=\d)/,'');fraction=fraction.replace(/0+$/,'');
 const sign=match[1]==='-'&&(integer!=='0'||fraction)?'−':'';
 return sign+integer.replace(/\B(?=(\d{3})+(?!\d))/g,',')+(fraction?'.'+fraction:'');
}

export function materialItemTotal(items){
 const numbers=items.map(({qty})=>materialQuantity(qty).replaceAll(',','').replace('−','-'));
 if(numbers.some(value=>!/^-?\d+(?:\.\d+)?$/.test(value)))return '—';
 const parts=numbers.map(value=>value.split('.'));
 const scale=parts.reduce((largest,[,fraction=''])=>Math.max(largest,fraction.length),0);
 const sum=parts.reduce((total,[whole,fraction=''])=>total+BigInt(whole+fraction.padEnd(scale,'0')),0n);
 const digits=(sum<0n?-sum:sum).toString().padStart(scale+1,'0');
 const value=scale?digits.slice(0,-scale)+'.'+digits.slice(-scale):digits;
 return materialQuantity((sum<0n?'-':'')+value);
}
