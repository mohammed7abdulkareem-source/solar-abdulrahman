// Printed and shared copies use these same styles in the PDF renderer.
export const supplierVoucherStyle = `
.supplierVoucherSheet{color:#142e35;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.supplierVoucherSheet>.head{padding-bottom:16px;margin-bottom:0;border-bottom:2px solid #147568}
.supplierVoucherSheet .brand h1{font-size:20px;color:#153c41;line-height:1.45}
.supplierVoucherSheet .brand p{color:#4c6467}
.supplierVoucherSheet .doc{max-width:none}
.supplierVoucherSheet .doc h2{font-size:22px;line-height:1.45;color:#173b3d}
.supplierVoucherSheet>.foot{margin-top:20px;padding-top:10px;border-color:#ccd9d7;color:#52676a}
.supplierVoucher{--sv-ink:#183b3c;--sv-muted:#475f61;--sv-line:#cbdad6;--sv-accent:#08685b;--sv-panel:#eaf5f1;--sv-band:#114e49;color:var(--sv-ink);font-size:14px;line-height:1.6;overflow-wrap:anywhere}
.supplierVoucher.isCharge{--sv-accent:#78511a;--sv-panel:#faf5e8;--sv-band:#60491f}
.supplierVoucher.isVoid{--sv-accent:#6e4847;--sv-panel:#f7f1f0;--sv-band:#584748}
.supplierVoucher h3,.supplierVoucher p{margin:0}
.supplierVoucher h3{font-size:15px;line-height:1.5;font-weight:700}
.supplierVoucher .svIdentity{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:18px 26px;align-items:center;padding:22px 0}
.supplierVoucher .svParty,.supplierVoucher .svFact{display:grid;align-content:start;gap:2px;min-width:0}
.supplierVoucher .svParty>span,.supplierVoucher .svFact>span,.supplierVoucher .svBalance>span{font-size:12px;color:var(--sv-muted);line-height:1.5}
.supplierVoucher .svParty>strong{font-size:25px;line-height:1.35;letter-spacing:-.3px}
.supplierVoucher .svFacts{display:flex;gap:9px 22px;flex-wrap:wrap;max-width:350px}
.supplierVoucher .svTime{display:block;color:var(--sv-muted);font-size:12px;font-weight:400}
.supplierVoucher .svFact strong{font-size:14px;line-height:1.55}
.supplierVoucher .svStatus{margin:14px 0 0;padding:7px 12px;border:1px solid #a98f75;border-inline-start:4px solid #936319;background:#faf6ed;color:#654a23;line-height:1.6;font-size:13px}
.supplierVoucher.isVoid .svStatus{border-color:#c8a6a4;border-inline-start-color:#9e4744;background:#fbf1ef;color:#7a3532}
.supplierVoucher .svPayment{display:flex;align-items:stretch;background:var(--sv-panel);border:1px solid var(--sv-band);border-radius:9px;overflow:hidden}
.supplierVoucher .svPaid,.supplierVoucher .svConversion{display:grid;align-content:center;min-width:0;padding:18px 22px;gap:3px;flex:1}
.supplierVoucher .svPaid{flex:1.28;background:var(--sv-band);color:white}
.supplierVoucher .svPaid>span,.supplierVoucher .svConversion>span{font-size:14px;line-height:1.5}
.supplierVoucher .svPaid>strong{font-size:32px;line-height:1.35}
.supplierVoucher .svConversion>strong{font-size:22px;line-height:1.45;color:var(--sv-accent)}
.supplierVoucher .svRate{font-size:12px;color:var(--sv-muted);line-height:1.6}
.supplierVoucher .svMoney{display:inline-flex;gap:.28em;align-items:baseline;flex-wrap:wrap;max-width:100%;font-variant-numeric:tabular-nums}
.supplierVoucher .svMoney bdi{direction:ltr;unicode-bidi:isolate;font-variant-numeric:tabular-nums;min-width:0}
.supplierVoucher .svMoney small{font-size:.62em;font-weight:600;white-space:nowrap;line-height:1.45}
.supplierVoucher .svBalances{margin-top:24px}
.supplierVoucher .svBalanceGrid{display:flex;align-items:stretch;margin-top:9px;border-top:1px solid var(--sv-line);border-bottom:1px solid var(--sv-line)}
.supplierVoucher .svBalance{display:grid;flex:1;align-content:center;gap:3px;padding:12px 16px;min-width:0}
.supplierVoucher .svBalance>strong{font-size:20px;line-height:1.45}
.supplierVoucher .svClosing{background:var(--sv-panel);border-inline-start:1px solid var(--sv-line);color:var(--sv-accent)}
.supplierVoucher .svClosing:first-child{border-inline-start:0}
.supplierVoucher .svClosing>strong{font-size:23px}
.supplierVoucher .svNotes{margin-top:18px;line-height:1.7}
.supplierVoucher .svNotes p{white-space:pre-wrap;overflow-wrap:anywhere;margin-top:4px}
.supplierVoucher .svExpenses{margin-top:14px;color:var(--sv-muted);font-size:13px}
.supplierVoucher .svContact{display:flex;align-items:start;flex-wrap:wrap;gap:8px 26px;border-top:1px solid var(--sv-line);margin-top:20px;padding-top:12px}
.supplierVoucher .svContact .svFact{min-width:130px}
.supplierVoucher .svContact .documentPhoneContact{flex-wrap:wrap;max-width:100%}
.supplierVoucher .svContact bdi{font-variant-numeric:tabular-nums}
.supplierVoucher .svIdentity,.supplierVoucher .svPayment,.supplierVoucher .svBalances,.supplierVoucher .svContact{break-inside:avoid}
@media screen and (max-width:600px){
 .supplierVoucherSheet>.head{gap:12px;padding-bottom:12px}
 .supplierVoucherSheet .brand h1,.supplierVoucherSheet .doc h2{font-size:16px}
 .supplierVoucher .svIdentity{grid-template-columns:minmax(0,1fr);gap:11px;padding:15px 0}
 .supplierVoucher .svParty>strong{font-size:22px}
 .supplierVoucher .svFacts{max-width:none}
 .supplierVoucher .svPaid,.supplierVoucher .svConversion{padding:12px}
 .supplierVoucher .svPaid>strong{font-size:24px}
 .supplierVoucher .svConversion>strong,.supplierVoucher .svClosing>strong{font-size:18px}
 .supplierVoucher .svBalance{padding:9px}
 .supplierVoucher .svBalance>strong{font-size:17px}
}
@media print and (monochrome){
 .supplierVoucher .svPaid{background:white;color:#111}
 .supplierVoucher .svConversion,.supplierVoucher .svClosing{border-inline-start:1px solid #555}
}
`;
