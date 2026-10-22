// Keep the committed invoice separate from the editor, which resets for the next sale.
export function savedSaleInvoice(draft,receipt){
 return {...draft,...receipt,draft:false,party_name:draft.party,created_at:receipt.invoiceAccount?.asOf||receipt.date||draft.date,
  items:draft.items.map(i=>({...i,product_name:i.name,brand_name:i.brand}))};
}
