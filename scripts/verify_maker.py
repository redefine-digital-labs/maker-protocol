#!/usr/bin/env python3
"""Reproduce manufacturing build and unchanged Maker/Pack regressions offline."""
from pathlib import Path
import hashlib,json,os,platform,re,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
SUI_SHA='1d7baa7c7314113671415acfa20279b1eedb6ae6d04f286988a00da285e769c3'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,msg):
 if not ok:raise ValueError(msg)
def inventory(root):
 return {str(p.relative_to(root)):sha(p) for folder in ('move/soulidity_maker_manufacturing','move/soulidity_maker_terms','move/soulidity_maker_publication','.deps/maker-ae467539') for p in (root/folder).rglob('*') if p.is_file()}
def main():
 raw=os.environ.get('SUI_BINARY');require(raw,'SUI_BINARY is required');sui=Path(raw).absolute();require(sui.is_file() and not sui.is_symlink() and sha(sui)==SUI_SHA,'pinned Sui v1.80.1 is required')
 pins=json.loads((ROOT/'maker-source-pins.json').read_text());require(inventory(ROOT)==pins['inputs'],'source/dependency digest drift')
 output=ROOT/'output/maker-manufacturing';output.mkdir(parents=True,exist_ok=True);run=Path(tempfile.mkdtemp(prefix='verification-',dir=output));source=run/'source';source.mkdir()
 for folder in ('move/soulidity_maker_manufacturing','move/soulidity_maker_terms','move/soulidity_maker_publication','.deps/maker-ae467539'):
  for p in (ROOT/folder).rglob('*'):require(not p.is_symlink() and (not p.is_file() or p.stat().st_nlink==1),'source alias refused')
  shutil.copytree(ROOT/folder,source/folder)
 for p in source.rglob('*'):
  if p.is_file():p.chmod(0o644)
 closure=[]
 for p in source.rglob('Move.toml'):
  text=p.read_text();require(not re.search(r'git\s*=',text),'remote dependency refused');closure.append(re.search(r'name\s*=\s*"([^"]+)"',text)[1])
  for rel in re.findall(r'local\s*=\s*"([^"]+)"',text):
   q=(p.parent/rel).resolve();require(not Path(rel).is_absolute() and q.is_relative_to(source) and (q/'Move.toml').is_file(),'external dependency refused')
 for p in source.rglob('Move.lock'):
  text=p.read_text();require(not re.search(r'git\s*=',text),'remote lock refused')
  for rel in re.findall(r'local\s*=\s*"([^"]+)"',text):
   q=(p.parent/rel).resolve();require(not Path(rel).is_absolute() and q.is_relative_to(source) and (q/'Move.toml').is_file(),'external lock refused')
 require(sorted(closure)==pins['all_package_names'],'unexpected source closure')
 home=run/'home';home.mkdir()
 config=home/'.sui/sui_config';config.mkdir(parents=True);keyfile=config/'empty.keystore';keyfile.write_text('[]\n');keyfile.chmod(0o600)
 (config/'client.yaml').write_text('keystore:\n  File: '+str(keyfile)+'\nenvs:\n  - alias: testnet\n    rpc: http://127.0.0.1:9\nactive_env: testnet\nactive_address: null\n')
 env=dict(os.environ,HOME=str(home),MOVE_HOME=str(home/'.move'),XDG_CONFIG_HOME=str(home/'.config'),TMPDIR=str(run))
 if platform.system()=='Darwin':prefix=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath '+json.dumps(str(run))+') (literal "/dev/null"))']
 elif platform.system()=='Linux':prefix=['unshare','--net','--']
 else:raise ValueError('enforced offline sandbox is unavailable')
 def execute(name,argv):
  r=subprocess.run(prefix+argv,cwd=source,env=env,capture_output=True,timeout=600);log=run/(name+'.log');log.write_bytes(r.stdout+r.stderr);return {'argv':prefix+argv,'exit_code':r.returncode,'log':str(log.relative_to(ROOT)),'log_sha256':sha(log)},r.stdout+r.stderr
 net,raw=execute('network-denial',[sys.executable,'-c','import socket;socket.create_connection(("127.0.0.1",9),timeout=1)']);require(net['exit_code']!=0 and (b'Operation not permitted' in raw or b'Network is unreachable' in raw),'network refusal not demonstrated')
 version,raw=execute('version',[str(sui),'--version']);require(version['exit_code']==0 and b'1.80.1-671ba71e69c7' in raw,'wrong Sui version')
 gates={};ok=True
 for name in ('production','maker49','pack57','focused9'):
  root=source/'move/soulidity_maker_manufacturing' if name in ('production','maker49') else source/'.deps/maker-ae467539/regression/move/soulidity_v1'
  argv=[str(sui),'move','build' if name=='production' else 'test','--path',str(root),'--install-dir',str(run/name)]
  if name=='pack57':argv+=['soulidity_v1::pack_soul_tests','--statistics']
  if name=='focused9':argv+=['soulidity_v1::maker_validation_atomic_tests','--statistics']
  if name=='maker49':argv+=['--statistics']
  row,raw=execute(name,argv);identities={i.decode():s.decode() for s,i in re.findall(rb'\[\s*(PASS|FAIL|TIMEOUT)\s*\]\s+(\S+)',raw)};row['identities']=identities;row['summary']=[s.decode() for s in re.findall(rb'Test result[^\n]*',raw)]
  ok=ok and row['exit_code']==0
  if name!='production':ok=ok and identities==pins['test_identities'][name]
  gates[name]=row
 artifacts={str(p.relative_to(run/'production/build/SoulidityMakerManufacturing/bytecode_modules')):sha(p) for p in (run/'production/build/SoulidityMakerManufacturing/bytecode_modules').rglob('*.mv')}
 ok=ok and artifacts==pins['production_artifacts'] and inventory(ROOT)==pins['inputs']
 after=inventory(source);stable={k:v for k,v in after.items() if not k.endswith('Move.lock')}=={k:v for k,v in pins['inputs'].items() if not k.endswith('Move.lock')};ok=ok and stable
 result={'result':'PASS' if ok else 'FAIL','gates':gates,'production_artifacts':artifacts,'pins_sha256':sha(ROOT/'maker-source-pins.json'),'tool_sha256':sha(sui),'empty_home':str(home.relative_to(ROOT)),'network_denial_probe':net,'source_and_manifest_stable':stable,'lock_mutations':[k for k,h in after.items() if pins['inputs'].get(k)!=h],'original_inputs_unchanged':inventory(ROOT)==pins['inputs'],'budget_overrides':[],'admission_source_activation':False,'provider_source_ownership_copied':False,'keyless_runtime':{'empty_keystore':keyfile.read_text().strip()=='[]','active_address':None,'generated_recovery_phrase':False},'chain_transactions':0,'release_or_audit_complete':False}
 require(keyfile.read_text().strip()=='[]','empty keystore changed')
 for log in run.glob('*.log'):require(not any(w in log.read_text(errors='replace').lower() for w in ['secret recovery phrase','generated new keypair']),'unexpected key generation; private log excluded')
 (run/'result.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps({'result':result['result'],'gates':{n:r['summary'] for n,r in gates.items()},'evidence':str((run/'result.json').relative_to(ROOT))}));return 0 if ok else 1
if __name__=='__main__':
 try:raise SystemExit(main())
 except (ValueError,OSError,KeyError,subprocess.TimeoutExpired) as e:print('Maker verification refused: '+str(e),file=sys.stderr);raise SystemExit(1)
