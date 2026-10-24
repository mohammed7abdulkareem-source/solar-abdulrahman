// Refresh labels by material ID without changing any saved commercial values.
export function refreshMaterialBrands(items,products=[]){
 const brands=new Map(products.map(p=>[String(p.id),p.brand??p.brands?.name??'']));
 return items.map(item=>{
  const id=Object.hasOwn(item,'product_id')?item.product_id:Object.hasOwn(item,'productId')?item.productId:item.id;
  if(id==null||!brands.has(String(id)))return item;
  const brand=brands.get(String(id));
  return {...item,...(Object.hasOwn(item,'brand_name')?{brand_name:brand}:{}),...(!Object.hasOwn(item,'brand_name')||Object.hasOwn(item,'brand')?{brand}:{} )};
 });
}
