import test from 'node:test';
import assert from 'node:assert/strict';
import {canOpenPage} from '../app/access-utils.mjs';
import {accountPermissions,changeAccountPermission,resetAccountPermissions} from '../app/user-admin-permissions.mjs';

const office=permissions=>({id:'test-office',active:true,user_type:'admin_staff',is_admin:false,permissions});

test('opening the editor preserves effective quote, warranty and history access on legacy accounts',()=>{
  for(const original of [
    {system:true,tahseel:false,warranty:false,salesHistory:false},
    {sale:true,ownSales:true},
    {tahseel:true,ownSales:true,salesDeleteOwn:true},
    {tahseel:false,exchangeRateEdit:true},
  ]){
    const edited=accountPermissions(original);
    for(const page of ['tahseel','warranty','salesHistory','deletionRequests','exchangeRate','cash']){
      assert.equal(canOpenPage(office(edited),page),canOpenPage(office(original),page),page);
    }
  }
});

test('resetting a draft clears optional business permissions without mutating the saved profile',()=>{
  const original={sale:true,tahseel:true,warranty:true,cash:true,cashExpense:true,deletionRequests:true,customData:'keep'};
  const reset=resetAccountPermissions(accountPermissions(original));
  for(const page of ['sale','salesHistory','tahseel','warranty','cash','deletionRequests'])assert.equal(canOpenPage(office(reset),page),false,page);
  assert.equal(reset.ownSales,true);
  assert.equal(reset.customData,'keep');
  assert.equal(original.tahseel,true);
  assert.equal(original.deletionRequests,true);
});

test('the restricted quote account can be granted warranty separately from sales and finance',()=>{
  let flags=resetAccountPermissions({});
  flags=changeAccountPermission(flags,'tahseel',true);
  flags=changeAccountPermission(flags,'warranty',true);
  const profile=office(flags);
  for(const key of ['tahseel','warranty'])assert.ok(canOpenPage(profile,key));
  for(const key of ['sale','system','salesHistory','cash','deletionRequests'])assert.equal(canOpenPage(profile,key),false,key);
  assert.equal(flags.tahseelFull,false);
  const full=changeAccountPermission(flags,'tahseelDefaults',true);
  assert.equal(full.tahseelFull,true);
  assert.equal(changeAccountPermission(full,'tahseel',false).tahseelDefaults,false);
});

test('resetting module permissions preserves the configured material price basis and grants no access',()=>{
 const reduced=resetAccountPermissions(accountPermissions({profitUsesWholesalePrice:true,profit:true,sale:true}));
 assert.equal(reduced.profitUsesWholesalePrice,true);
 assert.equal(canOpenPage(office(reduced),'profit'),false);
 assert.equal(canOpenPage(office(reduced),'sale'),false);
 const actual=changeAccountPermission(reduced,'profitUsesWholesalePrice',false);
 assert.equal(actual.profitUsesWholesalePrice,false);
 assert.equal(canOpenPage(office(actual),'sale'),false);
});
