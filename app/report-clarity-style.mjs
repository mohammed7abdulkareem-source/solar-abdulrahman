// Report-only typography. Invoice, receipt and quotation layouts keep their own styles.
export function isReportDocument(title,body=''){
 if(/class="(?:quoteDocument|salesDocument|customerReceiptDocument)/.test(body))return false;
 return /class="(?:invoiceReport|partyReport|cashStatementDocument|materialLedgerReport)\b/.test(body)||/كشف|تقرير|أرصدة|مدين|مبيعات الفترة|المنظومات غير المغلقة|حركة المواد|حركة مادة|تفاصيل أرباح|تفاصيل حركة أرباح|قاصة الدولار/.test(title);
}
export const reportClarityStyle=`
.sheet.reportSheet{color:#172f40;font-size:12px;line-height:1.7}
.reportSheet>.head{border-bottom:3px solid #087f74;padding-bottom:12px;margin-bottom:14px;gap:20px}
.reportSheet .brand p,.reportSheet .doc small{color:#435667;font-size:11px}
.reportSheet .doc{max-width:78mm}.reportSheet .doc h2{color:#163c4a;font-size:19px;font-weight:700}
.reportSheet .meta{gap:7px 14px;margin:12px 0}
.reportSheet .meta>div{background:#f4f8fa;border:1px solid #cedbe2;border-radius:5px;padding:8px 10px;color:#203d50;overflow-wrap:anywhere}
.reportSheet table{border:1px solid #9cafbb!important}
.reportSheet th{background:#e9f2f5!important;color:#163c4a!important;font-weight:700!important;line-height:1.6;border:1px solid #b4c6d0!important}
.reportSheet td{border:1px solid #c5d2da!important;color:#172f40!important;font-weight:500!important;line-height:1.6;font-variant-numeric:tabular-nums}
.reportSheet td b,.reportSheet td strong{color:inherit!important;font-weight:700!important}
.reportSheet td small{color:#425766!important;font-weight:400!important}
.reportSheet tr:nth-child(even)>td{background:#f5f8fa}
.reportSheet .notes{border:1px solid #c5d6dc;background:#f6fafb;color:#2e4b5b;min-height:0;line-height:1.8}
.reportSheet .documentCounts{color:#244a48;background:#eff7f3;border:1px solid #bfd5ca}
.reportSheet>.total{border:1px solid #79ac9c;background:#e8f5ee;color:#095c4d;padding:12px 14px;gap:14px;break-inside:avoid}
.reportSheet>.total b{color:#095c4d;font-size:18px;font-variant-numeric:tabular-nums}
.reportSheet>.foot{color:#425766;border-top:1px solid #bdcdd5;font-size:10px}
.reportSectionTitle{font-size:14px;font-weight:700;color:#183e4f;border-right:3px solid #0b8b79;padding-right:9px;margin:16px 0 8px;break-after:avoid}
.reportSummary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin:10px 0;break-inside:avoid}
.reportMetric{padding:10px;border:1px solid #b8cdd5;border-radius:5px;background:#f4f8fa;min-width:0;line-height:1.8}
.reportMetric>span{display:block;color:#3b5664;font-size:11px}.reportMetric>strong{display:block;color:#143e4c;font-size:15px;font-weight:700;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.reportCurrentBalance{padding:12px 14px;border:1px solid #88b8a9;border-right:4px solid #087f74;border-radius:5px;background:#eff8f4;break-inside:avoid}
.reportCurrentBalance>strong{font-size:17px;color:#0a604f}.reportCurrentBalance p{margin:6px 0 0;color:#34554e;font-size:11px}
.reportSheet .reportEmpty{text-align:center;color:#425766;padding:16px}
.reportSheet .reportNumber{direction:ltr;unicode-bidi:isolate;font-variant-numeric:tabular-nums;white-space:nowrap}
.reportSheet td .reportNumberLong{font-size:clamp(9px,.75em,10px)}
@media print{.reportSheet th,.reportSheet td{font-size:10px}.reportSheet .reportMetric>strong{font-size:14px}}
`;
