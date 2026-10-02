export function changedRows(previous, next) {
  const old = new Map(previous.map(row => [row.id, row]));
  const ids = new Set(next.map(row => row.id));
  return { changed: next.filter(row => JSON.stringify(old.get(row.id)) !== JSON.stringify(row)), removed: previous.filter(row => !ids.has(row.id)).map(row => row.id) };
}
export function invoiceError(items, products, kind) {
  if (!items.length) return 'أضف مادة واحدة على الأقل';
  for (const item of items) {
    if (!Number.isFinite(Number(item.qty)) || Number(item.qty) <= 0) return 'أدخل كمية صحيحة أكبر من صفر';
    if (item.price === '' || !Number.isFinite(Number(item.price)) || Number(item.price) < 0) return 'أدخل سعراً صحيحاً لكل مادة';
    const product = products.find(p => p.id === item.id);
    if (!product) return 'إحدى المواد لم تعد موجودة؛ أعد تحميل الفاتورة';
    if (kind !== 'purchase' && Number(item.qty) > Number(product.qty)) return 'الكمية المتوفرة لا تكفي للمادة: ' + product.name;
  }
  return '';
}
export function installationCost(job, amount = job.installationExpenses) {
  return Number(job.cost || 0) + Number(job.expenses || 0) + Number(amount || 0);
}
