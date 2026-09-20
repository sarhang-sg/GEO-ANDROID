// One compiler extension for R16 locality ranking/spatial intent. It adds
// indexes to the existing catalog; it never rebuilds static search or map data.
import {evaluateTs,loadOracle} from './r16.mjs';
import {cpSync,existsSync,readFileSync,writeFileSync,renameSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
export function appendSearchServiceIndex(db,web){
 const oracle=loadOracle(web);
 const language=evaluateTs(web,'src/lib/map-language.ts',['localizeNameValue']);
 const format=evaluateTs(web,'src/lib/geo-format.ts',['languageValue','placeRank'],language);
 const {SearchService}=evaluateTs(web,'src/lib/search-service.ts',['SearchService'],{...oracle,...format});
 db.exec(`CREATE TABLE locality_search(language TEXT NOT NULL,feature_id INTEGER NOT NULL REFERENCES feature(id),profile TEXT NOT NULL,names TEXT NOT NULL,rank INTEGER NOT NULL,population_bonus REAL NOT NULL,quick INTEGER NOT NULL,PRIMARY KEY(language,feature_id)) WITHOUT ROWID;
 CREATE TABLE locality_posting(language TEXT NOT NULL,type TEXT NOT NULL,key TEXT NOT NULL,feature_id INTEGER NOT NULL REFERENCES feature(id),PRIMARY KEY(language,type,key,feature_id)) WITHOUT ROWID;`);
 const insert=db.prepare('INSERT INTO locality_search VALUES (?,?,?,?,?,?,?)'),post=db.prepare('INSERT INTO locality_posting VALUES (?,?,?,?)');
 const rows=db.prepare("SELECT f.*,l.properties AS localized FROM feature f JOIN feature_language l ON l.feature_id=f.id AND l.language=? WHERE f.dataset='locality' ORDER BY f.id");
 let count=0;
 for(const lang of ['ku','ar','en'])for(const row of rows.iterate(lang)){
  const p=JSON.parse(row.properties),l=JSON.parse(row.localized);
  for(const language of ['ku','ar','en'])for(const field of ['name','admin_governorate','admin_district','admin_subdistrict','category'])delete p[`${field}_${language}`];
  delete p.name_ku_status;p.name=l.name;p[`name_${lang}`]=l.name;p.name_verified=l.name_verified===1;
  for(const field of ['admin_governorate','admin_district','admin_subdistrict','category'])p[`${field}_${lang}`]=l[field];
  if(lang==='ku')p.name_ku_status=l.name_status;
  const f={type:'Feature',id:row.source_id,geometry:JSON.parse(row.geometry),properties:p};
  const e=SearchService.prototype.createEntry.call(null,f,lang),n=Number.parseInt(String(p.population??'0'),10);
  const quick=['city','town','suburb','hamlet'].includes(String(p.place??'').toLowerCase())||(Number.isFinite(n)&&n>0);
  insert.run(lang,row.id,JSON.stringify(e.profile),JSON.stringify(e.normalizedNames),e.rank,e.populationBonus,quick?1:0);
  const prefixes=new Set();
  for(const t of e.tokens){post.run(lang,'token',t,row.id);prefixes.add(t.slice(0,2));if(t.length>=3)prefixes.add(t.slice(0,3));}
  for(const t of e.profile.phoneticKeys)if(t.length>=2)prefixes.add('~'+t.slice(0,2));
  for(const key of prefixes)post.run(lang,'prefix',key,row.id);
  count++;
 }
 db.prepare('INSERT INTO metadata VALUES (?,?)').run('searchServiceSchema','1');
 return count;
}
// Preserve the R16 viewport partition and ordering as catalog membership.
export function appendViewportShardIndex(db,web){
 const raw=readFileSync(join(web,'public/data/kri/kri-viewport-poi-shards-manifest.json'),'utf8'),manifest=JSON.parse(raw);
 const sha=b=>createHash('sha256').update(b).digest('hex');
 db.exec(`CREATE TABLE poi_shard(dataset TEXT NOT NULL,key TEXT NOT NULL,PRIMARY KEY(dataset,key)) WITHOUT ROWID;
 CREATE TABLE poi_shard_feature(dataset TEXT NOT NULL,key TEXT NOT NULL,ordinal INTEGER NOT NULL,feature_id INTEGER NOT NULL REFERENCES feature(id),PRIMARY KEY(dataset,key,ordinal),FOREIGN KEY(dataset,key) REFERENCES poi_shard(dataset,key)) WITHOUT ROWID;`);
 const leafInsert=db.prepare('INSERT INTO poi_shard VALUES (?,?)'),member=db.prepare('INSERT INTO poi_shard_feature VALUES (?,?,?,?)');
 const find=db.prepare('SELECT id FROM feature WHERE dataset=? AND source_id=?');
 for(const [dataset,part] of Object.entries(manifest.datasets))for(const leaf of part.leaves){
  if(!['base','natural'].includes(dataset)||!leaf.file.startsWith('data/kri/viewport-poi-shards/')||leaf.file.split('/').includes('..'))throw Error('Invalid POI shard input.');
  const bytes=readFileSync(join(web,'public',leaf.file));
  if(bytes.length!==leaf.bytes||sha(bytes)!==leaf.sha256)throw Error(`POI shard integrity: ${leaf.file}`);
  const features=JSON.parse(bytes).features;if(features.length!==leaf.records)throw Error(`POI shard count: ${leaf.file}`);
  leafInsert.run(dataset,leaf.key);
  features.forEach((f,ordinal)=>{const rows=find.all(dataset,String(f.properties?.id??f.id));if(rows.length!==1)throw Error(`Canonical POI identity: ${dataset}/${f.properties?.id??f.id}`);member.run(dataset,leaf.key,ordinal,rows[0].id);});
 }
 db.prepare('INSERT INTO metadata VALUES (?,?)').run('viewportPoiManifest',raw);
}
export function extendSearchServicePack(source,output,web){
 if(existsSync(output)||existsSync(output+'.building'))throw Error('Extension output must be new.');
 const sha=b=>createHash('sha256').update(b).digest('hex');
 const manifest=JSON.parse(readFileSync(join(source,'manifest.json'),'utf8'));
 const original=readFileSync(join(source,'catalog.sqlite')),catalog=manifest.files.find(f=>f.path==='catalog.sqlite');
 if(!catalog||catalog.bytes!==original.length||catalog.sha256!==sha(original))throw Error('Catalog does not match its declared manifest.');
 const stage=output+'.building';cpSync(source,stage,{recursive:true,errorOnExist:true,force:false});
 const db=new DatabaseSync(join(stage,'catalog.sqlite'));db.exec('PRAGMA foreign_keys=ON; BEGIN IMMEDIATE');
 let count;
 try{count=db.prepare("SELECT value FROM metadata WHERE key='searchServiceSchema'").get()?db.prepare('SELECT count(*) AS n FROM locality_search').get().n:appendSearchServiceIndex(db,web);if(!db.prepare("SELECT value FROM metadata WHERE key='viewportPoiManifest'").get())appendViewportShardIndex(db,web);const expected=db.prepare("SELECT records*3 AS n FROM dataset WHERE id='locality'").get().n;if(count!==expected)throw Error(`Locality index count ${count}/${expected}`);db.exec('COMMIT');}
 catch(error){db.exec('ROLLBACK');throw error;}finally{db.close();}
 const data=readFileSync(join(stage,'catalog.sqlite'));catalog.bytes=data.length;catalog.sha256=sha(data);
 manifest.contentHash=sha(manifest.files.map(f=>`${f.path}\0${f.bytes}\0${f.sha256}\n`).join(''));
 manifest.packId=`${manifest.versions.offlinePackVersion}-${manifest.contentHash.slice(0,16)}`;manifest.searchServiceSchema=1;
 for(const path of ['src/lib/search-service.ts','src/lib/geo-format.ts','src/lib/map-language.ts']){const bytes=readFileSync(join(web,path));manifest.inputs[path]={bytes:bytes.length,sha256:sha(bytes)};}
 manifest.compiler.sources['search-service-index.mjs']=sha(readFileSync(new URL('./search-service-index.mjs',import.meta.url)));
 writeFileSync(join(stage,'manifest.json'),JSON.stringify(manifest)+'\n');renameSync(stage,output);
 return {packId:manifest.packId,catalogBytes:catalog.bytes,searchServiceRows:count};
}
