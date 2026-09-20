import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,copyFileSync,existsSync,readdirSync,renameSync,rmSync} from 'node:fs';
import {resolve,join,dirname,relative} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {evaluateTs,loadOracle,loadStyle} from './r16.mjs';
import {appendSearchServiceIndex,appendViewportShardIndex,extendSearchServicePack} from './search-service-index.mjs';

const here=dirname(fileURLToPath(import.meta.url)),args=process.argv.slice(2),option=k=>args[args.indexOf(k)+1];
if(!args.includes('--web-root')||!args.includes('--output'))throw Error('Required: --web-root PATH --output NEW_DIRECTORY');
const web=resolve(option('--web-root')),output=resolve(option('--output')),publishing=output+'.building';
if(output===web||output.startsWith(web+'/')||existsSync(output)||existsSync(publishing))throw Error('Output must be new and outside the frozen Web sources.');
if(args.includes('--extend-from')){console.log(JSON.stringify(extendSearchServicePack(resolve(option('--extend-from')),output,web)));process.exit(0);}
// Keep an actively written SQLite database outside the synced workspace.
// Publish closed, declared files only, never build-time transport artifacts.
const stage=mkdtempSync(join(tmpdir(),'nav-kurd-core-'));
const sha=b=>createHash('sha256').update(b).digest('hex'),inputs=new Map(),owned=new Set(['catalog.sqlite']);
function read(path){const b=readFileSync(join(web,path));inputs.set(path,{bytes:b.length,sha256:sha(b)});return b;}
const json=path=>JSON.parse(read(path));
function save(path,data){mkdirSync(dirname(join(stage,path)),{recursive:true});writeFileSync(join(stage,path),typeof data==='string'?data:JSON.stringify(data)+'\n');owned.add(path);}
function copy(path,target){const b=read(path);mkdirSync(dirname(join(stage,target)),{recursive:true});writeFileSync(join(stage,target),b);owned.add(target);}
function walk(root){return readdirSync(root,{withFileTypes:true}).sort((a,b)=>a.name<b.name?-1:1).flatMap(e=>e.isDirectory()?walk(join(root,e.name)):[join(root,e.name)]);}
const release=json('release.config.json');
if(release.releaseId!=='2026-09-06-nav-kurd-v9.1.0')throw Error('Expected verified R16 input.');
for(const name of ['atlas-taxonomy','static-search','compact-search-payload','search.worker','poi-source','poi-taxonomy-classification','map-style','i18n','tutorial-controller','app-shell','dialog-close-icon'])read(name==='search.worker'?'src/workers/search.worker.ts':`src/lib/${name}.ts`);
const oracle=loadOracle(web),db=new DatabaseSync(join(stage,'catalog.sqlite'));
db.exec(readFileSync(join(here,'schema.sql'),'utf8'));db.exec('BEGIN');
const metadata=db.prepare('INSERT INTO metadata VALUES (?,?)');
for(const [k,v] of Object.entries(release))metadata.run(k,JSON.stringify(v));
metadata.run('searchConfig',JSON.stringify({digits:oracle.SEARCH_DIGITS,letters:oracle.SEARCH_PHONETIC_LETTERS,stopwords:[...oracle.SEARCH_STOPWORDS],intents:oracle.NORMALIZED_INTENT_GROUPS,coreIntents:oracle.NORMALIZED_CORE_INTENT_GROUPS,taxonomyIds:[...oracle.TAXONOMY_INTENT_IDS]}));
save('content/taxonomy.json',oracle.ATLAS_TAXONOMY);
const locality=json('public/data/kri/kri-localities-language-manifest.json');
const datasets=[['base','kri-pois-render.geojson',33055],['natural','kri-natural-features.geojson',5210],['locality',locality.geometry_file,12125],['major',locality.major_file,226],['cluster',locality.cluster_file,473],['security','kri-security-features.geojson',35],['reviewed','kri-reviewed-poi-corrections.geojson',1],['road_labels','kri-road-labels.geojson',1805],['governorate','kri-governorates.geojson',7],['district','kri-districts.geojson',36],['region_labels','kri-labels.geojson',9],['boundary','kri-boundary.geojson',1],['boundary_line','kri-boundary-line.geojson',1],['mask','kri-outside-mask.geojson',1]];
const insertFeature=db.prepare('INSERT INTO feature VALUES (?,?,?,?,?,?,?,?,?)'),insertBounds=db.prepare('INSERT INTO feature_bounds VALUES (?,?,?,?,?)');
const sourceIds=new Map(),localityIds=new Map();let featureId=0;
function bounds(coordinates,out=[Infinity,-Infinity,Infinity,-Infinity]){
 if(typeof coordinates[0]==='number'){const [x,y]=coordinates;if(!Number.isFinite(x)||!Number.isFinite(y))throw Error('Invalid coordinates');out[0]=Math.min(out[0],x);out[1]=Math.max(out[1],x);out[2]=Math.min(out[2],y);out[3]=Math.max(out[3],y);}
 else for(const child of coordinates)bounds(child,out);return out;
}
for(const [id,file,count] of datasets){
 const path=`public/data/kri/${file}`,data=json(path);if(data.features.length!==count)throw Error(`Dataset count mismatch: ${id}`);
 db.prepare('INSERT INTO dataset VALUES (?,?,?)').run(id,path,count);
 data.features.forEach((f,ordinal)=>{
  const source=String(f.properties.id??f.id??`${release.mapDataVersion}:${ordinal}`),fid=++featureId,b=bounds(f.geometry.coordinates);
  if(!b.every(Number.isFinite))throw Error(`Empty geometry: ${id}/${source}`);
  insertFeature.run(fid,id,source,JSON.stringify(f.geometry),JSON.stringify(f.properties),...b);insertBounds.run(fid,...b);
  if(!sourceIds.has(source))sourceIds.set(source,[]);sourceIds.get(source).push(fid);if(id==='locality')localityIds.set(source,fid);
 });
 if(['security','reviewed','governorate','district','boundary','boundary_line','mask'].includes(id))copy(path,`layers/${file}`);
 console.log(`features ${id}: ${count}`);
}
const fields=['id','name','name_verified','admin_governorate','admin_district','admin_subdistrict','category','name_status'],insertLanguage=db.prepare('INSERT INTO feature_language VALUES (?,?,?)');
for(const lang of ['ku','ar','en']){
 const p=json(`public/data/kri/${locality.files[lang].properties_file}`);if(p.items.length!==12125)throw Error('Locality language count mismatch');
 const seen=new Set();for(const row of p.items){const id=localityIds.get(row[0]);if(!id||seen.has(id))throw Error('Locality identity mismatch');seen.add(id);insertLanguage.run(id,lang,JSON.stringify(Object.fromEntries(fields.map((key,i)=>[key,row[i]]))));}
}
appendSearchServiceIndex(db,web);
appendViewportShardIndex(db,web);
let sid=0;const lexemes=new Map(),words=[];
const insertSearch=db.prepare('INSERT INTO search_row VALUES ('+Array(18).fill('?').join(',')+')'),insertPosting=db.prepare('INSERT INTO posting VALUES (?,?,?,?)'),insertLexeme=db.prepare('INSERT INTO lexeme VALUES (?,?,?)'),insertGram=db.prepare('INSERT INTO lexeme_gram VALUES (?,?)'),insertLexemePosting=db.prepare('INSERT INTO lexeme_posting VALUES (?,?,?)'),insertCrosswalk=db.prepare('INSERT INTO search_feature VALUES (?,?)');
for(const lang of ['ku','ar','en']){
 const items=oracle.decodeSearchPayload(json(`public/data/kri/kri-search-runtime-${lang}.json`),lang),rich=json(`data-src/generated/search/kri-search-index-${lang}.json`).items;
 if(items.length!==69329||rich.length!==items.length)throw Error('Search count mismatch');
 const index=await oracle.prepare(items,lang);if(index.entries.length!==items.length)throw Error('Unexpected blank names');
 for(let ordinal=0;ordinal<items.length;ordinal++){
  const {item,profile:p}=index.entries[ordinal],r=rich[ordinal];
  if(item.n!==r.n||item.k!==r.k||item.c!==r.c||Math.abs(item.x-r.x)>0.000006||Math.abs(item.y-r.y)>0.000006)throw Error(`Unverified search crosswalk ${lang}/${ordinal}`);
  const id=++sid,source=r.s?`${item.k}:${r.s}`:`unmatched:${release.mapDataVersion}:${lang}:${ordinal}`;
  insertSearch.run(id,lang,ordinal,source,item.n,item.q,item.k,item.c,item.x,item.y,p.primary,p.all,p.primaryName,p.allNames,p.intent,JSON.stringify(p.phoneticKeys),`${item.x}:${item.y}:${p.primaryName}`,JSON.stringify(r));
  if(r.s)for(const feature of sourceIds.get(r.s)??[])insertCrosswalk.run(id,feature);
  const prefixes=new Set();
  for(const word of new Set(p.all.split(' ').filter(Boolean))){
   if(word.length>=2)prefixes.add(word.slice(0,2));if(word.length>=3)prefixes.add(word.slice(0,3));
   let wid=lexemes.get(word);if(!wid){wid=words.length+1;words.push(word);lexemes.set(word,wid);insertLexeme.run(wid,word,word.length);
    const grams=new Set();for(let length=1;length<=3;length++)for(let offset=0;offset+length<=word.length;offset++)grams.add(word.slice(offset,offset+length));for(const gram of grams)insertGram.run(gram,wid);
   }insertLexemePosting.run(lang,wid,id);
  }
  for(const key of p.phoneticKeys)if(key.length>=2)prefixes.add('~'+key.slice(0,2));
  for(const key of prefixes)insertPosting.run(lang,'prefix',key,id);for(const key of p.intent.split(' ').filter(Boolean))insertPosting.run(lang,'intent',key,id);
 }console.log(`search ${lang}: ${items.length}`);
}
function distance(a,b){let row=Array.from({length:b.length+1},(_,i)=>i);for(let i=1;i<=a.length;i++){const next=[i];for(let j=1;j<=b.length;j++)next.push(Math.min(row[j]+1,next[j-1]+1,row[j-1]+(a[i-1]===b[j-1]?0:1)));row=next;}return row[b.length];}
const edges=new Map(),insertEdge=db.prepare('INSERT INTO bk_edge VALUES (?,?,?)');
for(let child=2;child<=words.length;child++){let parent=1;while(true){const d=distance(words[parent-1],words[child-1]),key=`${parent}:${d}`,next=edges.get(key);if(next){parent=next;continue;}edges.set(key,child);insertEdge.run(parent,d,child);break;}}
db.exec('COMMIT; ANALYZE; VACUUM;');
if(db.prepare('PRAGMA integrity_check').get().integrity_check!=='ok'||db.prepare('PRAGMA foreign_key_check').all().length)throw Error('SQLite integrity failure');
const sqliteVersion=db.prepare('SELECT sqlite_version() AS version').get().version;db.close();
for(const file of release.offlineMapFiles){const b=read(`public/${file.path}`);if(b.length!==file.bytes||sha(b)!==file.sha256)throw Error('PMTiles differs from release manifest');copy(`public/${file.path}`,`maps/${file.fileName}`);}
const assetMap={};
for(const dir of ['assets','fonts','legal','icons','screenshots'])for(const f of walk(join(web,'public',dir))){const rel=relative(join(web,'public'),f).split('\\').join('/');copy('public/'+rel,'resources/'+rel);assetMap['/'+rel]='resources/'+rel;}
for(const f of readdirSync(join(web,'public')))if(/\.(png|svg|webp|jpe?g|ico)$/i.test(f)){copy('public/'+f,'resources/'+f);assetMap['/'+f]='resources/'+f;}
save('content/asset-map.json',assetMap);save('content/ui.json',evaluateTs(web,'src/lib/i18n.ts',['UI']).UI);save('content/tutorial.json',evaluateTs(web,'src/lib/tutorial-controller.ts',['COPY']).COPY);
const appUrl=p=>`navkurd-core:///resources/${p.replace(/^\//,'')}`,close=evaluateTs(web,'src/lib/dialog-close-icon.ts',['dialogCloseIcon'],{appUrl}),shell={innerHTML:''};
evaluateTs(web,'src/lib/app-shell.ts',['renderAppShell'],{...close,appUrl}).renderAppShell(shell,appUrl('icons/nav-kurd-logo.png'),release.appVersion,release.mapEdition);
save('content/approved-shell-markup.json',{purpose:'R16 content/design reference; not an executable Android UI',html:shell.innerHTML});
const buildStyle=loadStyle(web);
for(const mode of ['street','night'])save(`styles/${mode}.json`,buildStyle({mode,pmtilesUrl:'navkurd-core:///maps/kri-base.pmtiles',roadsPmtilesUrl:'navkurd-core:///maps/kri-roads.pmtiles',satelliteEnabled:false,satelliteSource:{enabled:false},basemapVisible:true,administrativeVisible:true,placesVisible:true,lowPowerProfile:true,deferBasePoiData:true,deferNaturalPoiData:true}));
for(const f of walk(stage))if(!owned.has(relative(stage,f)))throw Error(`Undeclared output: ${f}`);
const files=[...owned].sort().map(path=>{const b=readFileSync(join(stage,path));return {path,bytes:b.length,sha256:sha(b)};});
const contentHash=sha(files.map(f=>`${f.path}\0${f.bytes}\0${f.sha256}\n`).join(''));
const manifest={schema:1,minimumReader:1,searchSchema:1,packId:`${release.offlinePackVersion}-${contentHash.slice(0,16)}`,contentHash,versions:release,languages:['ku','ar','en'],bounds:[41.285802647,33.305386992,46.348729776,37.377264006],nativeZoom:[5,12],displayMaxZoom:18,records:{features:featureId,searchRows:sid,lexemes:words.length},files,inputs:Object.fromEntries([...inputs].sort()),compiler:{node:process.version,sqlite:sqliteVersion,sources:Object.fromEntries(['build_core.mjs','r16.mjs','schema.sql'].map(f=>[f,sha(readFileSync(join(here,f)))]))}};
save('manifest.json',manifest);mkdirSync(publishing,{recursive:true});
for(const file of [...owned].sort()){const target=join(publishing,file);mkdirSync(dirname(target),{recursive:true});copyFileSync(join(stage,file),target);}
renameSync(publishing,output);rmSync(stage,{recursive:true});
console.log(JSON.stringify({packId:manifest.packId,records:manifest.records,files:files.length,bytes:files.reduce((n,f)=>n+f.bytes,0)}));
