import test from 'node:test';
import assert from 'node:assert/strict';
import {needsCloudSnapshot} from '../app/startup-pages.mjs';
test('sections backed by scoped APIs open independently; financial editors wait for complete shared data',()=>{
 for(const page of ['home','salesHistory','paymentHistory','cash','installations','warehouse','capital'])assert.equal(needsCloudSnapshot(page),false,page);
 for(const page of ['sale','system','purchase','products','customers','profit','customerStatement'])assert.equal(needsCloudSnapshot(page),true,page);
});
