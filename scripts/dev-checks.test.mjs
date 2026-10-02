import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {checkCourse, sharedAssets} from './dev-checks.mjs';
function fixture(t) {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'dr-check-'));
 t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 fs.mkdirSync(path.join(root,'shared'));
 fs.mkdirSync(path.join(root,'235A/public'),{recursive:true});
 fs.writeFileSync(path.join(root,'235A/public/index.html'),'<html/>');
 for (const asset of sharedAssets) {
  fs.writeFileSync(path.join(root,'shared',asset),'/* asset */');
  fs.writeFileSync(path.join(root,'235A/public',asset),'/* asset */');
 }
 return root;
}
test('valid copied assets and genuine links pass',t=>{
 const root=fixture(t); checkCourse(root,'235A');
 const p=path.join(root,'235A/public/app.css'); fs.unlinkSync(p); fs.symlinkSync('../../shared/app.css',p); checkCourse(root,'235A');
});
test('missing HTML gives render command',t=>{
 const root=fixture(t); fs.unlinkSync(path.join(root,'235A/public/index.html'));
 assert.throws(()=>checkCourse(root,'235A'),/gleam run -- --which "235A" --local/);
});
test('missing, broken and flattened shared links give remedies',t=>{
 const root=fixture(t);
 fs.unlinkSync(path.join(root,'235A/public/app.css'));
 const p=path.join(root,'235A/public/app.js'); fs.unlinkSync(p); fs.symlinkSync('../../shared/missing.js',p);
 fs.writeFileSync(path.join(root,'235A/public/local.css'),'../../shared/local.css\n');
 assert.throws(()=>checkCourse(root,'235A'),e=> /broken shared asset/.test(e.message)&&/text file/.test(e.message)&&/Developer Mode/.test(e.message));
});
