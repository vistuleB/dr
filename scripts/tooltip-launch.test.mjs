import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import vm from 'node:vm';
import {parseTooltipCommand, launchTooltip} from './tooltip-launch.mjs';
const root=path.resolve('/tmp/dr-tooltip-tests');
const image=parseTooltipCommand('open 235A/public/figures/my picture.svg',root,'235A');
test('spaces and shell metacharacters remain one argument, never shell code',async()=>{
 assert.equal(image.target,path.join(root,'235A/public/figures/my picture.svg'));
 const result=await launchTooltip(image,{platform:'darwin',execute:(file,args,options,done)=>{
  assert.equal(file,'open');assert.deepEqual(args,[image.target]);assert.equal(options.shell,undefined);done(null);
 }});
 assert.equal(result.success,true);
 const special=parseTooltipCommand('open 235A/public/figures/a;echo hi.svg',root,'235A');
 assert.ok(special.target.endsWith('a;echo hi.svg'));
});
test('invalid commands, traversal and disallowed extensions are rejected',()=>{
 for(const cmd of ['open 235B/public/a.svg','open 235A/public/../../a.svg','open 235A/public/a.exe','open 235A/public/a.svg\nwhoami','code --goto 235A/public/a.wly:1:2',null]) assert.equal(parseTooltipCommand(cmd,root,'235A'),null);
});
test('source paths with spaces preserve line and column',()=>{
 const c=parseTooltipCommand('code --goto 235A/wly/my chapter.wly:12:3',root,'235A');assert.deepEqual(c.args,['12','3']);assert.equal(c.kind,'source');
});
test('response waits for launcher callback and reports failure',async()=>{
 let callback;let settled=false;
 const promise=launchTooltip(image,{platform:'darwin',execute:(_f,_a,_o,cb)=>{callback=cb;}}).then(x=>{settled=true;return x;});
 await Promise.resolve();assert.equal(settled,false);
 callback(new Error('No application available'));
 const result=await promise;assert.equal(result.status,500);assert.match(result.error,/No application/);
});
test('unsupported platforms do not execute macOS commands',async()=>{
 for(const platform of ['win32','linux']) {
  const result=await launchTooltip(image,{platform,execute:()=>assert.fail('must not execute')}); assert.equal(result.status,501);assert.match(result.error,new RegExp(platform));
 }
});
test('missing code and Windows source launcher have actionable messages',async()=>{
 const c=parseTooltipCommand('code --goto 235A/wly/a.wly:1:2',root,'235A');
 const result=await launchTooltip(c,{platform:'darwin',execute:(_f,_a,_o,cb)=>cb(Object.assign(new Error('missing'),{code:'ENOENT'}))});
 assert.match(result.error,/Command Palette/);
 assert.equal((await launchTooltip(c,{platform:'win32',execute:()=>assert.fail()})).status,501);
});
test('browser reports server and network errors, successful launch stays quiet',async()=>{
 const source=fs.readFileSync(new URL('../shared/app.js',import.meta.url),'utf8');
 const snippet=source.slice(source.indexOf('const sendCmdTo3003 ='),source.indexOf('\nconst authorModeInit'));
 for(const mode of ['success','server','network']) {
  const alerts=[];const context={AUTHOR_TOKEN_KEY:'token',localStorage:{getItem:()=>null},window:{location:{protocol:'http:'},alert:m=>alerts.push(m)},fetch:async()=>{
   if(mode==='network')throw Error('Connection refused');
   return {ok:mode==='success',status:500,json:async()=>({success:mode==='success',error:'Launch failed'})};
  }};
  await vm.runInNewContext(snippet+'\nsendCmdTo3003("open test.svg");',context);
  assert.equal(alerts.length,mode==='success'?0:1);
  if(mode==='server')assert.match(alerts[0],/Launch failed/);
  if(mode==='network')assert.match(alerts[0],/Connection refused/);
 }
});
