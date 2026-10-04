import test from 'node:test';
import assert from 'node:assert/strict';
import {makePdfObjects} from '../app/pdf-share.mjs';

const sample=()=>({width:2,height:1,bytes:new Uint8Array([255,216,1,2,255,217])});
test('PDF sharing builds a valid PDF file with an embedded image per page',async()=>{
 const blob=makePdfObjects([sample()]);
 assert.equal(blob.type,'application/pdf');
 const bytes=new Uint8Array(await blob.arrayBuffer()),pdf=new TextDecoder().decode(bytes);
 assert.ok(pdf.startsWith('%PDF-1.4'));assert.ok(pdf.trimEnd().endsWith('%%EOF'));
 assert.match(pdf,/\/Count 1/);assert.match(pdf,/\/Subtype \/Image/);assert.match(pdf,/\/Filter \/DCTDecode/);assert.match(pdf,/endstream\nendobj/);
 const offset=Number(pdf.match(/startxref\n(\d+)/)?.[1]);assert.equal(pdf.slice(offset,offset+4),'xref');
 for(const match of pdf.matchAll(/(\d{10}) 00000 n/g)){const position=Number(match[1]);assert.match(pdf.slice(position),/^\d+ 0 obj/);}
});
test('PDF page count grows with long statements',async()=>{
 const blob=makePdfObjects([sample(),sample()]);
 const pdf=new TextDecoder().decode(await blob.arrayBuffer());
 assert.match(pdf,/\/Count 2/);assert.match(pdf,/\/Kids \[3 0 R 6 0 R\]/);
});
