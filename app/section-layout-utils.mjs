export const defaultSectionLayout={mode:'groups',mobileColumns:3,desktopColumns:6,order:[],revision:0};
export function orderedSections(rows,order=[]){const byId=new Map(rows.map(r=>[r[0],r]));return [...new Set([...order,...rows.map(r=>r[0])])].filter(id=>byId.has(id)).map(id=>byId.get(id));}
export function moveSection(order,from,to){const rows=[...order],a=rows.indexOf(from),b=rows.indexOf(to);if(a<0||b<0||a===b)return rows;rows.splice(a,1);rows.splice(b,0,from);return rows;}
