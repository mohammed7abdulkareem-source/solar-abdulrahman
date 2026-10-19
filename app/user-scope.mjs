// Page permissions grant capabilities within the user's records, never all users.
export function ownUserPermissions(value={}){
 const {all,installationsAll,salesDeleteAll,...permissions}=value;
 return {...permissions,ownCustomers:true,ownSales:true,ownPayments:true,ownProfit:true,
  installations:value.installations===true||installationsAll===true,
  salesDeleteOwn:value.salesDeleteOwn===true||salesDeleteAll===true,
  installationsAll:false,salesDeleteAll:false};
}
