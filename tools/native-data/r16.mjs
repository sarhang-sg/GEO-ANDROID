// Build/test oracle only. The Android runtime does not load this JavaScript.
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';
export function evaluateTs(root, relative, names, scope = {}, trailer = '') {
  let source=stripTypeScriptTypes(readFileSync(join(root,relative),'utf8'),{mode:'strip'});
  source=source.replace(/^import\s[\s\S]*?;\s*$/gm,'').replaceAll('import.meta.env.BASE_URL',JSON.stringify('navkurd-core:///resources/')).replace(/^export\s+/gm,'');
  return runInNewContext(`(()=>{${source}\n${trailer}\nreturn {${names.join(',')}};})()`,{setTimeout,URL,console,...scope},{filename:relative});
}
export function loadOracle(root){
  const taxonomy=evaluateTs(root,'src/lib/atlas-taxonomy.ts',['ATLAS_TAXONOMY']);
  const search=evaluateTs(root,'src/lib/static-search.ts',['normalizeStaticSearch','phoneticSearchGroups','prepareStaticSearchQuery','scoreStaticSearchProfile','searchIntentIdsForCategory','SEARCH_DIGITS','SEARCH_PHONETIC_LETTERS','SEARCH_STOPWORDS','NORMALIZED_INTENT_GROUPS','NORMALIZED_CORE_INTENT_GROUPS','TAXONOMY_INTENT_IDS'],taxonomy);
  const decoder=evaluateTs(root,'src/lib/compact-search-payload.ts',['decodeSearchPayload']);
  const worker=evaluateTs(root,'src/workers/search.worker.ts',['prepare','candidateIds','referenceSearch'],{...search,...decoder,self:{addEventListener(){}}},'async function referenceSearch(index,q,limit,lang){index.resultCache.clear();return search(index,q,limit,lang,++latestSearchId);}');
  return {...taxonomy,...search,...decoder,...worker};
}
export function loadStyle(root){
  const classification=evaluateTs(root,'src/lib/poi-taxonomy-classification.ts',['POI_EXCLUDED_SOURCE_IDS']);
  const names=[...readFileSync(join(root,'src/lib/poi-source.ts'),'utf8').matchAll(/export const (\w+)/g)].map(m=>m[1]);
  const poi=evaluateTs(root,'src/lib/poi-source.ts',names,classification);
  return evaluateTs(root,'src/lib/map-style.ts',['buildKriMapStyle'],{...poi,dataAssetUrl:path=>`navkurd-core:///layers/${path.split('/').at(-1)}`}).buildKriMapStyle;
}
