/* Build placeholders are replaced in dist/sw.js by tools/build/build-offline-runtime.mjs. */
const RELEASE_ID = "10.4.4";
const UI_REVISION = "V10";
const CACHE_SCHEMA = "91";
const MAP_DATA_VERSION = "2026-07-22-nav-kurd-systematic-dedupe-2027";
const OFFLINE_PACK_VERSION = "2027.13";
const CACHE_PREFIX = "nav-kurd-";
const OWNED_CACHE_PREFIXES = [CACHE_PREFIX, "kri-map-", "geo-map-"];
const SHELL_CACHE = `${CACHE_PREFIX}shell-s${CACHE_SCHEMA}-${RELEASE_ID}-${UI_REVISION}`;
const RUNTIME_CACHE = `${CACHE_PREFIX}runtime-s${CACHE_SCHEMA}-${RELEASE_ID}-${UI_REVISION}`;
const DATA_CACHE = `${CACHE_PREFIX}data-s${CACHE_SCHEMA}-${MAP_DATA_VERSION}`;
const SATELLITE_CACHE = `${CACHE_PREFIX}satellite-s${CACHE_SCHEMA}`;
const SATELLITE_CACHE_LIMIT = 256;
const RUNTIME_CACHE_LIMIT = 320;
const CACHE_TRIM_WRITE_BATCH = 16;
const TRANSPARENT_TILE_BYTES = Uint8Array.from(atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+Avz7WQAAAABJRU5ErkJggg=="), (char) => char.charCodeAt(0));
const BASE = self.registration.scope;
const BACKGROUND_SYNC_TAG = "nav-kurd-runtime-sync";
const PERIODIC_SYNC_TAG = "nav-kurd-periodic-refresh";
const WIDGET_TAG = "nav-kurd-atlas";
const OFFLINE_FALLBACK_PATH = "offline.html";
const OFFLINE_READY_MARKER_PATH = "__nav-kurd-offline-pack-ready__.json";
const NETWORK_TIMEOUT_MS = 8_000;
const SHELL_FETCH_TIMEOUT_MS = 45_000;
const VERSIONED_DATA_TIMEOUT_MS = 45_000;
const INSTALL_FETCH_TIMEOUT_MS = SHELL_FETCH_TIMEOUT_MS;
const PRECACHE = [{"path":"assets/android-brand.jpg","required":false,"warm":true,"offlineRuntime":true,"bytes":224703},{"path":"assets/clipboard-mu55EQoE.js","required":true,"warm":true,"bytes":479},{"path":"assets/feedback-studio-hVLWgWD7.js","required":false,"warm":true,"bytes":15734},{"path":"assets/icons/atlas/groups-manifest.json","required":false,"warm":true,"offlineRuntime":true,"bytes":19604},{"path":"assets/icons/atlas/groups/border_route.json","required":false,"warm":false,"offlineRuntime":true,"bytes":22161},{"path":"assets/icons/atlas/groups/communications_technology.json","required":false,"warm":false,"offlineRuntime":true,"bytes":31300},{"path":"assets/icons/atlas/groups/culture_religion_media.json","required":false,"warm":false,"offlineRuntime":true,"bytes":39910},{"path":"assets/icons/atlas/groups/education_research.json","required":false,"warm":false,"offlineRuntime":true,"bytes":27856},{"path":"assets/icons/atlas/groups/emergency_security.json","required":false,"warm":false,"offlineRuntime":true,"bytes":31134},{"path":"assets/icons/atlas/groups/finance_professional.json","required":false,"warm":false,"offlineRuntime":true,"bytes":34467},{"path":"assets/icons/atlas/groups/food_hospitality.json","required":false,"warm":false,"offlineRuntime":true,"bytes":30668},{"path":"assets/icons/atlas/groups/government_public.json","required":false,"warm":false,"offlineRuntime":true,"bytes":49695},{"path":"assets/icons/atlas/groups/health.json","required":false,"warm":false,"offlineRuntime":true,"bytes":33280},{"path":"assets/icons/atlas/groups/industry_agriculture.json","required":false,"warm":false,"offlineRuntime":true,"bytes":36487},{"path":"assets/icons/atlas/groups/residential_buildings.json","required":false,"warm":false,"offlineRuntime":true,"bytes":22884},{"path":"assets/icons/atlas/groups/retail_commerce.json","required":false,"warm":false,"offlineRuntime":true,"bytes":64343},{"path":"assets/icons/atlas/groups/settlement_admin.json","required":false,"warm":false,"offlineRuntime":true,"bytes":28715},{"path":"assets/icons/atlas/groups/sports_leisure.json","required":false,"warm":false,"offlineRuntime":true,"bytes":63897},{"path":"assets/icons/atlas/groups/tourism_nature_heritage.json","required":false,"warm":false,"offlineRuntime":true,"bytes":60833},{"path":"assets/icons/atlas/groups/transport_logistics.json","required":false,"warm":false,"offlineRuntime":true,"bytes":50281},{"path":"assets/icons/atlas/groups/utilities_infrastructure.json","required":false,"warm":false,"offlineRuntime":true,"bytes":38013},{"path":"assets/icons/atlas/runtime-sprite/nav-kurd-poi-runtime-2x.png","required":false,"warm":false,"bytes":551503},{"path":"assets/icons/atlas/runtime-sprite/nav-kurd-poi-runtime-3x.png","required":false,"warm":false,"bytes":683756},{"path":"assets/icons/atlas/runtime-sprite/nav-kurd-poi-runtime.json","required":false,"warm":true,"bytes":34322},{"path":"assets/icons/nav-kurd/01.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":448109},{"path":"assets/icons/nav-kurd/02.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":472801},{"path":"assets/icons/nav-kurd/03.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":452237},{"path":"assets/icons/nav-kurd/04.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":532245},{"path":"assets/icons/nav-kurd/05.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":418025},{"path":"assets/icons/nav-kurd/06.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":510593},{"path":"assets/icons/nav-kurd/07.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":454465},{"path":"assets/icons/nav-kurd/08.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":612221},{"path":"assets/icons/nav-kurd/09.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":408793},{"path":"assets/icons/nav-kurd/10.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":363389},{"path":"assets/icons/nav-kurd/11.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":457453},{"path":"assets/icons/nav-kurd/12.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":567697},{"path":"assets/icons/nav-kurd/13.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":590629},{"path":"assets/icons/nav-kurd/14.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":612653},{"path":"assets/icons/nav-kurd/15.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":386041},{"path":"assets/icons/nav-kurd/a1.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":399},{"path":"assets/icons/nav-kurd/a2.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":602},{"path":"assets/icons/nav-kurd/delete.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":364289},{"path":"assets/icons/nav-kurd/manifest.json","required":false,"warm":true,"offlineRuntime":true,"bytes":4803},{"path":"assets/icons/nav-kurd/profile.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":288769},{"path":"assets/icons/nav-kurd/speed-time.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":582405},{"path":"assets/icons/nav-kurd/steps.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":727601},{"path":"assets/icons/social/instagram.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":299},{"path":"assets/index-CXBXsc-A.js","required":true,"warm":true,"bytes":4467},{"path":"assets/index-FPVYzJ29.css","required":true,"warm":true,"bytes":389997},{"path":"assets/local-provider-CFsuKCna.js","required":true,"warm":true,"bytes":2454},{"path":"assets/main-DJU-y2Z0.js","required":true,"warm":true,"bytes":515165},{"path":"assets/map-language-BU4zV4JD.js","required":true,"warm":true,"bytes":471386},{"path":"assets/maplibre-CKRTiAqP.css","required":true,"warm":true,"bytes":82869},{"path":"assets/maplibre-D6qQPCjC.js","required":true,"warm":true,"bytes":969621},{"path":"assets/maplibre-gl-worker-CMMvOBIS.js","required":true,"warm":true,"bytes":478668},{"path":"assets/mobile-dialog-layout-CoyeOvqB.js","required":false,"warm":true,"bytes":7247},{"path":"assets/native/clear.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":298},{"path":"assets/native/info.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":378},{"path":"assets/native/settings.svg","required":false,"warm":true,"offlineRuntime":true,"bytes":617},{"path":"assets/nav-kurd-logo.png","required":false,"warm":true,"offlineRuntime":true,"bytes":478173},{"path":"assets/navigation-history-store-BPEfklmo.js","required":true,"warm":true,"bytes":8919},{"path":"assets/owner-studio-copy-BT5E-yz5.js","required":false,"warm":true,"bytes":17822},{"path":"assets/owner-studio-CRAdRyhu.js","required":false,"warm":true,"bytes":55929},{"path":"assets/preload-helper-Dn9ownJW.js","required":true,"warm":true,"bytes":43030},{"path":"assets/promo/nav-kurd-v9-cover.jpg","required":false,"warm":true,"offlineRuntime":true,"bytes":198010},{"path":"assets/promo/nav-kurd-v9-screen-1.jpg","required":false,"warm":true,"offlineRuntime":true,"bytes":152593},{"path":"assets/promo/nav-kurd-v9-screen-2.jpg","required":false,"warm":true,"offlineRuntime":true,"bytes":137587},{"path":"assets/promo/nav-kurd-v9-screen-3.jpg","required":false,"warm":true,"offlineRuntime":true,"bytes":115102},{"path":"assets/release-BKeBTZdb.js","required":true,"warm":true,"bytes":1214},{"path":"assets/runtime-diagnostics-VDcgG8F-.js","required":true,"warm":true,"bytes":11117},{"path":"assets/search.worker-CxyOr_-c.js","required":false,"warm":true,"bytes":118514},{"path":"assets/support/copy-asmr.wav","required":false,"warm":true,"offlineRuntime":true,"bytes":81188},{"path":"assets/support/fastpay.webp","required":false,"warm":true,"offlineRuntime":true,"bytes":6964},{"path":"assets/support/fib.webp","required":false,"warm":true,"offlineRuntime":true,"bytes":4274},{"path":"assets/support/my-cv-preview.jpg","required":false,"warm":true,"offlineRuntime":true,"bytes":171279},{"path":"assets/support/superqi.webp","required":false,"warm":true,"offlineRuntime":true,"bytes":6272},{"path":"assets/user-contribution-studio-XDE_VKIB.js","required":false,"warm":true,"bytes":84619},{"path":"assets/weather/clear-day.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":553},{"path":"assets/weather/clear-night.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":444},{"path":"assets/weather/cloudy.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":399},{"path":"assets/weather/fog.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":548},{"path":"assets/weather/partly-cloudy-day.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":778},{"path":"assets/weather/partly-cloudy-night.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":470},{"path":"assets/weather/rain.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":645},{"path":"assets/weather/snow.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":633},{"path":"assets/weather/thunderstorm.svg","required":false,"warm":false,"offlineRuntime":true,"bytes":424},{"path":"data/kri/kri-boundary-line.geojson","required":false,"warm":true,"offlineRuntime":true,"bytes":73579},{"path":"data/kri/kri-boundary.geojson","required":false,"warm":true,"offlineRuntime":true,"bytes":73546},{"path":"data/kri/kri-districts.geojson","required":false,"warm":true,"offlineRuntime":true,"bytes":318663},{"path":"data/kri/kri-governorates.geojson","required":false,"warm":true,"offlineRuntime":true,"bytes":146379},{"path":"data/kri/kri-labels.geojson","required":false,"warm":true,"offlineRuntime":true,"bytes":10506},{"path":"data/kri/kri-localities-cluster-runtime.geojson","required":false,"warm":true,"offlineRuntime":true,"localityCluster":true,"bytes":127745},{"path":"data/kri/kri-localities-language-manifest.json","required":false,"warm":true,"offlineRuntime":true,"bytes":2189},{"path":"data/kri/kri-localities-major-runtime.geojson","required":false,"warm":true,"offlineRuntime":true,"localityMajor":true,"bytes":40306},{"path":"data/kri/kri-localities-properties-ar.json","required":false,"warm":false,"language":"ar","languageAsset":true,"offlineRuntime":true,"bytes":1301212},{"path":"data/kri/kri-localities-properties-en.json","required":false,"warm":false,"language":"en","languageAsset":true,"offlineRuntime":true,"bytes":1183417},{"path":"data/kri/kri-localities-properties-ku.json","required":false,"warm":false,"language":"ku","languageAsset":true,"offlineRuntime":true,"bytes":1206059},{"path":"data/kri/kri-localities-runtime-base.geojson","required":false,"warm":true,"offlineRuntime":true,"localityGeometry":true,"bytes":2186736},{"path":"data/kri/kri-outside-mask.geojson","required":false,"warm":true,"offlineRuntime":true,"bytes":71688},{"path":"data/kri/kri-reviewed-poi-corrections.geojson","required":false,"warm":false,"offlineRuntime":true,"bytes":2338},{"path":"data/kri/kri-road-labels.geojson","required":false,"warm":false,"offlineRuntime":true,"bytes":2588748},{"path":"data/kri/kri-search-runtime-ar.json","required":false,"warm":false,"language":"ar","languageAsset":"search","offlineRuntime":true,"bytes":5735568},{"path":"data/kri/kri-search-runtime-en.json","required":false,"warm":false,"language":"en","languageAsset":"search","offlineRuntime":true,"bytes":5661846},{"path":"data/kri/kri-search-runtime-ku.json","required":false,"warm":false,"language":"ku","languageAsset":"search","offlineRuntime":true,"bytes":6219438},{"path":"data/kri/kri-search-shards-manifest.json","required":false,"warm":true,"offlineRuntime":true,"bytes":1152},{"path":"data/kri/kri-security-features.geojson","required":false,"warm":false,"offlineRuntime":true,"bytes":66137},{"path":"data/kri/kri-viewport-poi-shards-manifest.json","required":false,"warm":true,"offlineRuntime":true,"bytes":317941},{"path":"data/kri/viewport-poi-shards/base/10/632/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":22951},{"path":"data/kri/viewport-poi-shards/base/10/632/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":20999},{"path":"data/kri/viewport-poi-shards/base/10/634/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":137325},{"path":"data/kri/viewport-poi-shards/base/10/634/401.json","required":false,"warm":false,"offlineRuntime":true,"bytes":17521},{"path":"data/kri/viewport-poi-shards/base/10/635/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":130096},{"path":"data/kri/viewport-poi-shards/base/10/635/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":229438},{"path":"data/kri/viewport-poi-shards/base/10/635/400.json","required":false,"warm":false,"offlineRuntime":true,"bytes":355298},{"path":"data/kri/viewport-poi-shards/base/10/635/401.json","required":false,"warm":false,"offlineRuntime":true,"bytes":195725},{"path":"data/kri/viewport-poi-shards/base/10/636/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":128058},{"path":"data/kri/viewport-poi-shards/base/10/636/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":304076},{"path":"data/kri/viewport-poi-shards/base/10/636/400.json","required":false,"warm":false,"offlineRuntime":true,"bytes":138548},{"path":"data/kri/viewport-poi-shards/base/10/636/401.json","required":false,"warm":false,"offlineRuntime":true,"bytes":280762},{"path":"data/kri/viewport-poi-shards/base/10/636/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":110125},{"path":"data/kri/viewport-poi-shards/base/10/636/403.json","required":false,"warm":false,"offlineRuntime":true,"bytes":64984},{"path":"data/kri/viewport-poi-shards/base/10/637/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":30608},{"path":"data/kri/viewport-poi-shards/base/10/637/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":104946},{"path":"data/kri/viewport-poi-shards/base/10/637/400.json","required":false,"warm":false,"offlineRuntime":true,"bytes":261816},{"path":"data/kri/viewport-poi-shards/base/10/637/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":126817},{"path":"data/kri/viewport-poi-shards/base/10/637/403.json","required":false,"warm":false,"offlineRuntime":true,"bytes":155472},{"path":"data/kri/viewport-poi-shards/base/10/638/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":75227},{"path":"data/kri/viewport-poi-shards/base/10/638/401.json","required":false,"warm":false,"offlineRuntime":true,"bytes":221315},{"path":"data/kri/viewport-poi-shards/base/10/638/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":120274},{"path":"data/kri/viewport-poi-shards/base/10/638/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":213090},{"path":"data/kri/viewport-poi-shards/base/10/639/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":34597},{"path":"data/kri/viewport-poi-shards/base/10/639/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":166533},{"path":"data/kri/viewport-poi-shards/base/10/639/400.json","required":false,"warm":false,"offlineRuntime":true,"bytes":115278},{"path":"data/kri/viewport-poi-shards/base/10/639/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":127543},{"path":"data/kri/viewport-poi-shards/base/10/639/403.json","required":false,"warm":false,"offlineRuntime":true,"bytes":280590},{"path":"data/kri/viewport-poi-shards/base/10/639/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":64950},{"path":"data/kri/viewport-poi-shards/base/10/639/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":31421},{"path":"data/kri/viewport-poi-shards/base/10/640/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":72797},{"path":"data/kri/viewport-poi-shards/base/10/640/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":78876},{"path":"data/kri/viewport-poi-shards/base/10/640/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":63526},{"path":"data/kri/viewport-poi-shards/base/10/640/407.json","required":false,"warm":false,"offlineRuntime":true,"bytes":56578},{"path":"data/kri/viewport-poi-shards/base/10/641/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":104487},{"path":"data/kri/viewport-poi-shards/base/10/641/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":307210},{"path":"data/kri/viewport-poi-shards/base/10/641/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":167661},{"path":"data/kri/viewport-poi-shards/base/10/641/406.json","required":false,"warm":false,"offlineRuntime":true,"bytes":76428},{"path":"data/kri/viewport-poi-shards/base/10/641/407.json","required":false,"warm":false,"offlineRuntime":true,"bytes":99838},{"path":"data/kri/viewport-poi-shards/base/10/642/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":350321},{"path":"data/kri/viewport-poi-shards/base/10/642/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":82622},{"path":"data/kri/viewport-poi-shards/base/10/643/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":42794},{"path":"data/kri/viewport-poi-shards/base/10/643/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":11528},{"path":"data/kri/viewport-poi-shards/base/11/1266/797.json","required":false,"warm":false,"offlineRuntime":true,"bytes":12922},{"path":"data/kri/viewport-poi-shards/base/11/1266/798.json","required":false,"warm":false,"offlineRuntime":true,"bytes":10962},{"path":"data/kri/viewport-poi-shards/base/11/1266/799.json","required":false,"warm":false,"offlineRuntime":true,"bytes":101329},{"path":"data/kri/viewport-poi-shards/base/11/1267/796.json","required":false,"warm":false,"offlineRuntime":true,"bytes":20654},{"path":"data/kri/viewport-poi-shards/base/11/1267/797.json","required":false,"warm":false,"offlineRuntime":true,"bytes":25654},{"path":"data/kri/viewport-poi-shards/base/11/1267/798.json","required":false,"warm":false,"offlineRuntime":true,"bytes":255662},{"path":"data/kri/viewport-poi-shards/base/11/1267/799.json","required":false,"warm":false,"offlineRuntime":true,"bytes":6860},{"path":"data/kri/viewport-poi-shards/base/11/1268/799.json","required":false,"warm":false,"offlineRuntime":true,"bytes":31665},{"path":"data/kri/viewport-poi-shards/base/11/1268/800.json","required":false,"warm":false,"offlineRuntime":true,"bytes":20664},{"path":"data/kri/viewport-poi-shards/base/11/1268/801.json","required":false,"warm":false,"offlineRuntime":true,"bytes":30017},{"path":"data/kri/viewport-poi-shards/base/11/1269/798.json","required":false,"warm":false,"offlineRuntime":true,"bytes":40802},{"path":"data/kri/viewport-poi-shards/base/11/1269/799.json","required":false,"warm":false,"offlineRuntime":true,"bytes":58565},{"path":"data/kri/viewport-poi-shards/base/11/1269/800.json","required":false,"warm":false,"offlineRuntime":true,"bytes":84006},{"path":"data/kri/viewport-poi-shards/base/11/1269/801.json","required":false,"warm":false,"offlineRuntime":true,"bytes":270776},{"path":"data/kri/viewport-poi-shards/base/11/1275/802.json","required":false,"warm":false,"offlineRuntime":true,"bytes":184071},{"path":"data/kri/viewport-poi-shards/base/11/1275/803.json","required":false,"warm":false,"offlineRuntime":true,"bytes":55108},{"path":"data/kri/viewport-poi-shards/base/11/1276/798.json","required":false,"warm":false,"offlineRuntime":true,"bytes":23030},{"path":"data/kri/viewport-poi-shards/base/11/1276/799.json","required":false,"warm":false,"offlineRuntime":true,"bytes":87518},{"path":"data/kri/viewport-poi-shards/base/11/1276/800.json","required":false,"warm":false,"offlineRuntime":true,"bytes":155441},{"path":"data/kri/viewport-poi-shards/base/11/1276/801.json","required":false,"warm":false,"offlineRuntime":true,"bytes":163393},{"path":"data/kri/viewport-poi-shards/base/11/1276/806.json","required":false,"warm":false,"offlineRuntime":true,"bytes":31968},{"path":"data/kri/viewport-poi-shards/base/11/1276/809.json","required":false,"warm":false,"offlineRuntime":true,"bytes":30773},{"path":"data/kri/viewport-poi-shards/base/11/1277/798.json","required":false,"warm":false,"offlineRuntime":true,"bytes":48224},{"path":"data/kri/viewport-poi-shards/base/11/1277/800.json","required":false,"warm":false,"offlineRuntime":true,"bytes":20268},{"path":"data/kri/viewport-poi-shards/base/11/1277/801.json","required":false,"warm":false,"offlineRuntime":true,"bytes":46805},{"path":"data/kri/viewport-poi-shards/base/11/1277/806.json","required":false,"warm":false,"offlineRuntime":true,"bytes":17923},{"path":"data/kri/viewport-poi-shards/base/11/1277/807.json","required":false,"warm":false,"offlineRuntime":true,"bytes":20444},{"path":"data/kri/viewport-poi-shards/base/11/1277/808.json","required":false,"warm":false,"offlineRuntime":true,"bytes":18475},{"path":"data/kri/viewport-poi-shards/base/11/1277/809.json","required":false,"warm":false,"offlineRuntime":true,"bytes":17166},{"path":"data/kri/viewport-poi-shards/base/11/1278/802.json","required":false,"warm":false,"offlineRuntime":true,"bytes":162913},{"path":"data/kri/viewport-poi-shards/base/11/1278/803.json","required":false,"warm":false,"offlineRuntime":true,"bytes":123641},{"path":"data/kri/viewport-poi-shards/base/11/1279/802.json","required":false,"warm":false,"offlineRuntime":true,"bytes":275364},{"path":"data/kri/viewport-poi-shards/base/11/1279/803.json","required":false,"warm":false,"offlineRuntime":true,"bytes":11280},{"path":"data/kri/viewport-poi-shards/base/11/1280/806.json","required":false,"warm":false,"offlineRuntime":true,"bytes":69638},{"path":"data/kri/viewport-poi-shards/base/11/1280/807.json","required":false,"warm":false,"offlineRuntime":true,"bytes":51866},{"path":"data/kri/viewport-poi-shards/base/11/1280/812.json","required":false,"warm":false,"offlineRuntime":true,"bytes":14644},{"path":"data/kri/viewport-poi-shards/base/11/1280/813.json","required":false,"warm":false,"offlineRuntime":true,"bytes":14229},{"path":"data/kri/viewport-poi-shards/base/11/1281/806.json","required":false,"warm":false,"offlineRuntime":true,"bytes":34856},{"path":"data/kri/viewport-poi-shards/base/11/1281/807.json","required":false,"warm":false,"offlineRuntime":true,"bytes":267026},{"path":"data/kri/viewport-poi-shards/base/11/1281/812.json","required":false,"warm":false,"offlineRuntime":true,"bytes":20841},{"path":"data/kri/viewport-poi-shards/base/11/1282/806.json","required":false,"warm":false,"offlineRuntime":true,"bytes":85127},{"path":"data/kri/viewport-poi-shards/base/11/1283/806.json","required":false,"warm":false,"offlineRuntime":true,"bytes":43845},{"path":"data/kri/viewport-poi-shards/base/11/1283/807.json","required":false,"warm":false,"offlineRuntime":true,"bytes":24367},{"path":"data/kri/viewport-poi-shards/base/12/2532/1592.json","required":false,"warm":false,"offlineRuntime":true,"bytes":17810},{"path":"data/kri/viewport-poi-shards/base/12/2532/1593.json","required":false,"warm":false,"offlineRuntime":true,"bytes":2045},{"path":"data/kri/viewport-poi-shards/base/12/2533/1593.json","required":false,"warm":false,"offlineRuntime":true,"bytes":11435},{"path":"data/kri/viewport-poi-shards/base/12/2536/1597.json","required":false,"warm":false,"offlineRuntime":true,"bytes":62067},{"path":"data/kri/viewport-poi-shards/base/12/2537/1597.json","required":false,"warm":false,"offlineRuntime":true,"bytes":9212},{"path":"data/kri/viewport-poi-shards/base/12/2548/1604.json","required":false,"warm":false,"offlineRuntime":true,"bytes":118849},{"path":"data/kri/viewport-poi-shards/base/12/2548/1607.json","required":false,"warm":false,"offlineRuntime":true,"bytes":25738},{"path":"data/kri/viewport-poi-shards/base/12/2549/1604.json","required":false,"warm":false,"offlineRuntime":true,"bytes":201034},{"path":"data/kri/viewport-poi-shards/base/12/2549/1607.json","required":false,"warm":false,"offlineRuntime":true,"bytes":9699},{"path":"data/kri/viewport-poi-shards/base/12/2552/1614.json","required":false,"warm":false,"offlineRuntime":true,"bytes":19639},{"path":"data/kri/viewport-poi-shards/base/12/2552/1615.json","required":false,"warm":false,"offlineRuntime":true,"bytes":289371},{"path":"data/kri/viewport-poi-shards/base/12/2552/1617.json","required":false,"warm":false,"offlineRuntime":true,"bytes":35048},{"path":"data/kri/viewport-poi-shards/base/12/2553/1614.json","required":false,"warm":false,"offlineRuntime":true,"bytes":5600},{"path":"data/kri/viewport-poi-shards/base/12/2553/1617.json","required":false,"warm":false,"offlineRuntime":true,"bytes":11701},{"path":"data/kri/viewport-poi-shards/base/12/2554/1598.json","required":false,"warm":false,"offlineRuntime":true,"bytes":60325},{"path":"data/kri/viewport-poi-shards/base/12/2554/1599.json","required":false,"warm":false,"offlineRuntime":true,"bytes":329185},{"path":"data/kri/viewport-poi-shards/base/12/2555/1598.json","required":false,"warm":false,"offlineRuntime":true,"bytes":4916},{"path":"data/kri/viewport-poi-shards/base/12/2555/1599.json","required":false,"warm":false,"offlineRuntime":true,"bytes":22276},{"path":"data/kri/viewport-poi-shards/base/12/2562/1626.json","required":false,"warm":false,"offlineRuntime":true,"bytes":3020},{"path":"data/kri/viewport-poi-shards/base/12/2562/1627.json","required":false,"warm":false,"offlineRuntime":true,"bytes":44901},{"path":"data/kri/viewport-poi-shards/base/12/2563/1626.json","required":false,"warm":false,"offlineRuntime":true,"bytes":6723},{"path":"data/kri/viewport-poi-shards/base/12/2563/1627.json","required":false,"warm":false,"offlineRuntime":true,"bytes":329580},{"path":"data/kri/viewport-poi-shards/base/12/2564/1615.json","required":false,"warm":false,"offlineRuntime":true,"bytes":58557},{"path":"data/kri/viewport-poi-shards/base/12/2565/1615.json","required":false,"warm":false,"offlineRuntime":true,"bytes":115538},{"path":"data/kri/viewport-poi-shards/base/13/5066/3184.json","required":false,"warm":false,"offlineRuntime":true,"bytes":65394},{"path":"data/kri/viewport-poi-shards/base/13/5066/3185.json","required":false,"warm":false,"offlineRuntime":true,"bytes":15584},{"path":"data/kri/viewport-poi-shards/base/13/5067/3184.json","required":false,"warm":false,"offlineRuntime":true,"bytes":338563},{"path":"data/kri/viewport-poi-shards/base/13/5067/3185.json","required":false,"warm":false,"offlineRuntime":true,"bytes":32082},{"path":"data/kri/viewport-poi-shards/base/13/5072/3192.json","required":false,"warm":false,"offlineRuntime":true,"bytes":174033},{"path":"data/kri/viewport-poi-shards/base/13/5072/3193.json","required":false,"warm":false,"offlineRuntime":true,"bytes":10331},{"path":"data/kri/viewport-poi-shards/base/13/5073/3193.json","required":false,"warm":false,"offlineRuntime":true,"bytes":16290},{"path":"data/kri/viewport-poi-shards/base/13/5074/3193.json","required":false,"warm":false,"offlineRuntime":true,"bytes":28997},{"path":"data/kri/viewport-poi-shards/base/13/5075/3192.json","required":false,"warm":false,"offlineRuntime":true,"bytes":97919},{"path":"data/kri/viewport-poi-shards/base/13/5075/3193.json","required":false,"warm":false,"offlineRuntime":true,"bytes":21408},{"path":"data/kri/viewport-poi-shards/base/13/5096/3210.json","required":false,"warm":false,"offlineRuntime":true,"bytes":155675},{"path":"data/kri/viewport-poi-shards/base/13/5096/3211.json","required":false,"warm":false,"offlineRuntime":true,"bytes":303686},{"path":"data/kri/viewport-poi-shards/base/13/5096/3212.json","required":false,"warm":false,"offlineRuntime":true,"bytes":189638},{"path":"data/kri/viewport-poi-shards/base/13/5096/3213.json","required":false,"warm":false,"offlineRuntime":true,"bytes":51766},{"path":"data/kri/viewport-poi-shards/base/13/5097/3213.json","required":false,"warm":false,"offlineRuntime":true,"bytes":76933},{"path":"data/kri/viewport-poi-shards/base/13/5098/3210.json","required":false,"warm":false,"offlineRuntime":true,"bytes":190522},{"path":"data/kri/viewport-poi-shards/base/13/5098/3212.json","required":false,"warm":false,"offlineRuntime":true,"bytes":271704},{"path":"data/kri/viewport-poi-shards/base/13/5098/3213.json","required":false,"warm":false,"offlineRuntime":true,"bytes":128477},{"path":"data/kri/viewport-poi-shards/base/13/5099/3210.json","required":false,"warm":false,"offlineRuntime":true,"bytes":98294},{"path":"data/kri/viewport-poi-shards/base/13/5099/3211.json","required":false,"warm":false,"offlineRuntime":true,"bytes":140768},{"path":"data/kri/viewport-poi-shards/base/13/5099/3212.json","required":false,"warm":false,"offlineRuntime":true,"bytes":112109},{"path":"data/kri/viewport-poi-shards/base/13/5099/3213.json","required":false,"warm":false,"offlineRuntime":true,"bytes":7529},{"path":"data/kri/viewport-poi-shards/base/13/5104/3232.json","required":false,"warm":false,"offlineRuntime":true,"bytes":6683},{"path":"data/kri/viewport-poi-shards/base/13/5104/3233.json","required":false,"warm":false,"offlineRuntime":true,"bytes":34328},{"path":"data/kri/viewport-poi-shards/base/13/5105/3233.json","required":false,"warm":false,"offlineRuntime":true,"bytes":203333},{"path":"data/kri/viewport-poi-shards/base/13/5106/3230.json","required":false,"warm":false,"offlineRuntime":true,"bytes":80656},{"path":"data/kri/viewport-poi-shards/base/13/5106/3231.json","required":false,"warm":false,"offlineRuntime":true,"bytes":355021},{"path":"data/kri/viewport-poi-shards/base/13/5106/3232.json","required":false,"warm":false,"offlineRuntime":true,"bytes":317383},{"path":"data/kri/viewport-poi-shards/base/13/5106/3233.json","required":false,"warm":false,"offlineRuntime":true,"bytes":205630},{"path":"data/kri/viewport-poi-shards/base/13/5107/3230.json","required":false,"warm":false,"offlineRuntime":true,"bytes":3547},{"path":"data/kri/viewport-poi-shards/base/13/5107/3231.json","required":false,"warm":false,"offlineRuntime":true,"bytes":23778},{"path":"data/kri/viewport-poi-shards/base/13/5107/3232.json","required":false,"warm":false,"offlineRuntime":true,"bytes":14038},{"path":"data/kri/viewport-poi-shards/base/13/5107/3233.json","required":false,"warm":false,"offlineRuntime":true,"bytes":17371},{"path":"data/kri/viewport-poi-shards/base/13/5128/3228.json","required":false,"warm":false,"offlineRuntime":true,"bytes":208885},{"path":"data/kri/viewport-poi-shards/base/13/5128/3229.json","required":false,"warm":false,"offlineRuntime":true,"bytes":181396},{"path":"data/kri/viewport-poi-shards/base/13/5130/3228.json","required":false,"warm":false,"offlineRuntime":true,"bytes":177231},{"path":"data/kri/viewport-poi-shards/base/13/5131/3228.json","required":false,"warm":false,"offlineRuntime":true,"bytes":1461},{"path":"data/kri/viewport-poi-shards/base/13/5131/3229.json","required":false,"warm":false,"offlineRuntime":true,"bytes":18601},{"path":"data/kri/viewport-poi-shards/base/14/10146/6384.json","required":false,"warm":false,"offlineRuntime":true,"bytes":90163},{"path":"data/kri/viewport-poi-shards/base/14/10146/6385.json","required":false,"warm":false,"offlineRuntime":true,"bytes":67729},{"path":"data/kri/viewport-poi-shards/base/14/10147/6384.json","required":false,"warm":false,"offlineRuntime":true,"bytes":114618},{"path":"data/kri/viewport-poi-shards/base/14/10147/6385.json","required":false,"warm":false,"offlineRuntime":true,"bytes":100022},{"path":"data/kri/viewport-poi-shards/base/14/10148/6384.json","required":false,"warm":false,"offlineRuntime":true,"bytes":160002},{"path":"data/kri/viewport-poi-shards/base/14/10148/6385.json","required":false,"warm":false,"offlineRuntime":true,"bytes":127405},{"path":"data/kri/viewport-poi-shards/base/14/10149/6384.json","required":false,"warm":false,"offlineRuntime":true,"bytes":7027},{"path":"data/kri/viewport-poi-shards/base/14/10149/6385.json","required":false,"warm":false,"offlineRuntime":true,"bytes":92788},{"path":"data/kri/viewport-poi-shards/base/14/10194/6420.json","required":false,"warm":false,"offlineRuntime":true,"bytes":192726},{"path":"data/kri/viewport-poi-shards/base/14/10194/6421.json","required":false,"warm":false,"offlineRuntime":true,"bytes":200824},{"path":"data/kri/viewport-poi-shards/base/14/10194/6422.json","required":false,"warm":false,"offlineRuntime":true,"bytes":263328},{"path":"data/kri/viewport-poi-shards/base/14/10194/6423.json","required":false,"warm":false,"offlineRuntime":true,"bytes":206226},{"path":"data/kri/viewport-poi-shards/base/14/10194/6424.json","required":false,"warm":false,"offlineRuntime":true,"bytes":201659},{"path":"data/kri/viewport-poi-shards/base/14/10194/6425.json","required":false,"warm":false,"offlineRuntime":true,"bytes":36266},{"path":"data/kri/viewport-poi-shards/base/14/10195/6420.json","required":false,"warm":false,"offlineRuntime":true,"bytes":4366},{"path":"data/kri/viewport-poi-shards/base/14/10195/6421.json","required":false,"warm":false,"offlineRuntime":true,"bytes":112719},{"path":"data/kri/viewport-poi-shards/base/14/10195/6422.json","required":false,"warm":false,"offlineRuntime":true,"bytes":208723},{"path":"data/kri/viewport-poi-shards/base/14/10195/6423.json","required":false,"warm":false,"offlineRuntime":true,"bytes":239976},{"path":"data/kri/viewport-poi-shards/base/14/10195/6424.json","required":false,"warm":false,"offlineRuntime":true,"bytes":222815},{"path":"data/kri/viewport-poi-shards/base/14/10195/6425.json","required":false,"warm":false,"offlineRuntime":true,"bytes":127330},{"path":"data/kri/viewport-poi-shards/base/14/10196/6422.json","required":false,"warm":false,"offlineRuntime":true,"bytes":193587},{"path":"data/kri/viewport-poi-shards/base/14/10196/6423.json","required":false,"warm":false,"offlineRuntime":true,"bytes":165868},{"path":"data/kri/viewport-poi-shards/base/14/10197/6422.json","required":false,"warm":false,"offlineRuntime":true,"bytes":75907},{"path":"data/kri/viewport-poi-shards/base/14/10197/6423.json","required":false,"warm":false,"offlineRuntime":true,"bytes":50306},{"path":"data/kri/viewport-poi-shards/base/14/10210/6464.json","required":false,"warm":false,"offlineRuntime":true,"bytes":1539},{"path":"data/kri/viewport-poi-shards/base/14/10210/6465.json","required":false,"warm":false,"offlineRuntime":true,"bytes":56158},{"path":"data/kri/viewport-poi-shards/base/14/10211/6464.json","required":false,"warm":false,"offlineRuntime":true,"bytes":174480},{"path":"data/kri/viewport-poi-shards/base/14/10211/6465.json","required":false,"warm":false,"offlineRuntime":true,"bytes":209519},{"path":"data/kri/viewport-poi-shards/base/14/10258/6456.json","required":false,"warm":false,"offlineRuntime":true,"bytes":63497},{"path":"data/kri/viewport-poi-shards/base/14/10258/6457.json","required":false,"warm":false,"offlineRuntime":true,"bytes":144403},{"path":"data/kri/viewport-poi-shards/base/14/10258/6458.json","required":false,"warm":false,"offlineRuntime":true,"bytes":169816},{"path":"data/kri/viewport-poi-shards/base/14/10258/6459.json","required":false,"warm":false,"offlineRuntime":true,"bytes":67051},{"path":"data/kri/viewport-poi-shards/base/14/10259/6456.json","required":false,"warm":false,"offlineRuntime":true,"bytes":43280},{"path":"data/kri/viewport-poi-shards/base/14/10259/6457.json","required":false,"warm":false,"offlineRuntime":true,"bytes":172087},{"path":"data/kri/viewport-poi-shards/base/14/10259/6458.json","required":false,"warm":false,"offlineRuntime":true,"bytes":296397},{"path":"data/kri/viewport-poi-shards/base/14/10259/6459.json","required":false,"warm":false,"offlineRuntime":true,"bytes":68820},{"path":"data/kri/viewport-poi-shards/base/14/10260/6458.json","required":false,"warm":false,"offlineRuntime":true,"bytes":435846},{"path":"data/kri/viewport-poi-shards/base/14/10260/6459.json","required":false,"warm":false,"offlineRuntime":true,"bytes":122983},{"path":"data/kri/viewport-poi-shards/base/14/10261/6458.json","required":false,"warm":false,"offlineRuntime":true,"bytes":91969},{"path":"data/kri/viewport-poi-shards/base/14/10261/6459.json","required":false,"warm":false,"offlineRuntime":true,"bytes":52486},{"path":"data/kri/viewport-poi-shards/base/8/157/100.json","required":false,"warm":false,"offlineRuntime":true,"bytes":129552},{"path":"data/kri/viewport-poi-shards/base/8/157/99.json","required":false,"warm":false,"offlineRuntime":true,"bytes":25789},{"path":"data/kri/viewport-poi-shards/base/8/158/101.json","required":false,"warm":false,"offlineRuntime":true,"bytes":38712},{"path":"data/kri/viewport-poi-shards/base/8/159/102.json","required":false,"warm":false,"offlineRuntime":true,"bytes":3246},{"path":"data/kri/viewport-poi-shards/base/8/160/102.json","required":false,"warm":false,"offlineRuntime":true,"bytes":158537},{"path":"data/kri/viewport-poi-shards/base/8/160/99.json","required":false,"warm":false,"offlineRuntime":true,"bytes":12947},{"path":"data/kri/viewport-poi-shards/base/9/316/198.json","required":false,"warm":false,"offlineRuntime":true,"bytes":151102},{"path":"data/kri/viewport-poi-shards/base/9/316/200.json","required":false,"warm":false,"offlineRuntime":true,"bytes":186928},{"path":"data/kri/viewport-poi-shards/base/9/317/198.json","required":false,"warm":false,"offlineRuntime":true,"bytes":139943},{"path":"data/kri/viewport-poi-shards/base/9/317/201.json","required":false,"warm":false,"offlineRuntime":true,"bytes":85129},{"path":"data/kri/viewport-poi-shards/base/9/318/198.json","required":false,"warm":false,"offlineRuntime":true,"bytes":16046},{"path":"data/kri/viewport-poi-shards/base/9/318/202.json","required":false,"warm":false,"offlineRuntime":true,"bytes":347987},{"path":"data/kri/viewport-poi-shards/base/9/318/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":6315},{"path":"data/kri/viewport-poi-shards/base/9/319/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":223158},{"path":"data/kri/viewport-poi-shards/base/9/320/200.json","required":false,"warm":false,"offlineRuntime":true,"bytes":319915},{"path":"data/kri/viewport-poi-shards/base/9/321/201.json","required":false,"warm":false,"offlineRuntime":true,"bytes":130165},{"path":"data/kri/viewport-poi-shards/base/9/321/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":7838},{"path":"data/kri/viewport-poi-shards/natural/10/638/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":119597},{"path":"data/kri/viewport-poi-shards/natural/10/638/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":147017},{"path":"data/kri/viewport-poi-shards/natural/10/638/400.json","required":false,"warm":false,"offlineRuntime":true,"bytes":302817},{"path":"data/kri/viewport-poi-shards/natural/10/638/401.json","required":false,"warm":false,"offlineRuntime":true,"bytes":88990},{"path":"data/kri/viewport-poi-shards/natural/10/639/398.json","required":false,"warm":false,"offlineRuntime":true,"bytes":244084},{"path":"data/kri/viewport-poi-shards/natural/10/639/399.json","required":false,"warm":false,"offlineRuntime":true,"bytes":230344},{"path":"data/kri/viewport-poi-shards/natural/10/639/400.json","required":false,"warm":false,"offlineRuntime":true,"bytes":201768},{"path":"data/kri/viewport-poi-shards/natural/10/639/401.json","required":false,"warm":false,"offlineRuntime":true,"bytes":101428},{"path":"data/kri/viewport-poi-shards/natural/10/640/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":325142},{"path":"data/kri/viewport-poi-shards/natural/10/640/403.json","required":false,"warm":false,"offlineRuntime":true,"bytes":221183},{"path":"data/kri/viewport-poi-shards/natural/10/640/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":308253},{"path":"data/kri/viewport-poi-shards/natural/10/640/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":211259},{"path":"data/kri/viewport-poi-shards/natural/10/641/402.json","required":false,"warm":false,"offlineRuntime":true,"bytes":187638},{"path":"data/kri/viewport-poi-shards/natural/10/641/403.json","required":false,"warm":false,"offlineRuntime":true,"bytes":234229},{"path":"data/kri/viewport-poi-shards/natural/10/641/404.json","required":false,"warm":false,"offlineRuntime":true,"bytes":108798},{"path":"data/kri/viewport-poi-shards/natural/10/641/405.json","required":false,"warm":false,"offlineRuntime":true,"bytes":164140},{"path":"data/kri/viewport-poi-shards/natural/8/157/100.json","required":false,"warm":false,"offlineRuntime":true,"bytes":179485},{"path":"data/kri/viewport-poi-shards/natural/8/157/99.json","required":false,"warm":false,"offlineRuntime":true,"bytes":13612},{"path":"data/kri/viewport-poi-shards/natural/8/158/100.json","required":false,"warm":false,"offlineRuntime":true,"bytes":431072},{"path":"data/kri/viewport-poi-shards/natural/8/158/101.json","required":false,"warm":false,"offlineRuntime":true,"bytes":45385},{"path":"data/kri/viewport-poi-shards/natural/8/159/102.json","required":false,"warm":false,"offlineRuntime":true,"bytes":13734},{"path":"data/kri/viewport-poi-shards/natural/8/160/102.json","required":false,"warm":false,"offlineRuntime":true,"bytes":96554},{"path":"data/kri/viewport-poi-shards/natural/8/160/99.json","required":false,"warm":false,"offlineRuntime":true,"bytes":10624},{"path":"data/kri/viewport-poi-shards/natural/9/316/198.json","required":false,"warm":false,"offlineRuntime":true,"bytes":38273},{"path":"data/kri/viewport-poi-shards/natural/9/316/199.json","required":false,"warm":false,"offlineRuntime":true,"bytes":247981},{"path":"data/kri/viewport-poi-shards/natural/9/317/198.json","required":false,"warm":false,"offlineRuntime":true,"bytes":146115},{"path":"data/kri/viewport-poi-shards/natural/9/317/199.json","required":false,"warm":false,"offlineRuntime":true,"bytes":309264},{"path":"data/kri/viewport-poi-shards/natural/9/318/198.json","required":false,"warm":false,"offlineRuntime":true,"bytes":111279},{"path":"data/kri/viewport-poi-shards/natural/9/318/199.json","required":false,"warm":false,"offlineRuntime":true,"bytes":403041},{"path":"data/kri/viewport-poi-shards/natural/9/318/200.json","required":false,"warm":false,"offlineRuntime":true,"bytes":269130},{"path":"data/kri/viewport-poi-shards/natural/9/318/201.json","required":false,"warm":false,"offlineRuntime":true,"bytes":253611},{"path":"data/kri/viewport-poi-shards/natural/9/318/202.json","required":false,"warm":false,"offlineRuntime":true,"bytes":202722},{"path":"data/kri/viewport-poi-shards/natural/9/318/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":4674},{"path":"data/kri/viewport-poi-shards/natural/9/319/201.json","required":false,"warm":false,"offlineRuntime":true,"bytes":426087},{"path":"data/kri/viewport-poi-shards/natural/9/319/202.json","required":false,"warm":false,"offlineRuntime":true,"bytes":310365},{"path":"data/kri/viewport-poi-shards/natural/9/319/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":220852},{"path":"data/kri/viewport-poi-shards/natural/9/320/200.json","required":false,"warm":false,"offlineRuntime":true,"bytes":160961},{"path":"data/kri/viewport-poi-shards/natural/9/320/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":386816},{"path":"data/kri/viewport-poi-shards/natural/9/321/201.json","required":false,"warm":false,"offlineRuntime":true,"bytes":205052},{"path":"data/kri/viewport-poi-shards/natural/9/321/202.json","required":false,"warm":false,"offlineRuntime":true,"bytes":272907},{"path":"data/kri/viewport-poi-shards/natural/9/321/203.json","required":false,"warm":false,"offlineRuntime":true,"bytes":12409},{"path":"fonts/DroidLogo-Bold.ttf","required":true,"warm":true,"bytes":116996},{"path":"fonts/RedHatDisplay-Variable.woff2","required":true,"warm":true,"bytes":46656},{"path":"fonts/UniQAIDAR-Money-Heist-002.ttf","required":true,"warm":true,"bytes":48504},{"path":"icons/apple-touch-icon.png","required":false,"warm":true,"bytes":36922},{"path":"icons/favicon-32x32.png","required":true,"warm":true,"bytes":2307},{"path":"icons/nav-kurd-icon-192.png","required":true,"warm":true,"bytes":41203},{"path":"icons/nav-kurd-icon-512.png","required":false,"warm":true,"bytes":204386},{"path":"icons/nav-kurd-logo.png","required":false,"warm":true,"offlineRuntime":true,"bytes":478173},{"path":"index.html","required":true,"warm":true,"bytes":4835},{"path":"legal/account-deletion.html","required":false,"warm":true,"offlineRuntime":true,"bytes":7948},{"path":"legal/contribution-guidelines.html","required":false,"warm":true,"offlineRuntime":true,"bytes":9749},{"path":"legal/legal-i18n.js","required":false,"warm":true,"offlineRuntime":true,"bytes":1704},{"path":"legal/legal.css","required":false,"warm":true,"offlineRuntime":true,"bytes":3191},{"path":"legal/privacy.html","required":false,"warm":true,"offlineRuntime":true,"bytes":27061},{"path":"legal/security.html","required":false,"warm":true,"offlineRuntime":true,"bytes":2821},{"path":"legal/terms.html","required":false,"warm":true,"offlineRuntime":true,"bytes":19946},{"path":"manifest.webmanifest","required":true,"warm":true,"bytes":4005},{"path":"offline-manifest.json","required":true,"warm":true,"bytes":64733},{"path":"offline.css","required":true,"warm":true,"bytes":2699},{"path":"offline.html","required":true,"warm":true,"bytes":1909},{"path":"offline.js","required":true,"warm":true,"bytes":1517},{"path":"pwa-init.js","required":true,"warm":true,"bytes":1128}];
const REQUIRED_SHELL_PATHS = new Set(
  PRECACHE
    .filter((entry) => entry.required === true && typeof entry.path === "string")
    .map((entry) => new URL(entry.path.replace(/^\//, ""), self.registration.scope).pathname)
);
let offlineRuntimeAborter = null;
const cacheTrimStates = new Map();
const versionedDataFetches = new Map();

const absolute = (path) => new URL(path.replace(/^\//, ""), BASE).toString();
const isSameOrigin = (request) => new URL(request.url).origin === self.location.origin;
const workerIsOffline = () => self.navigator?.onLine === false;

async function fetchWithTimeout(input, init = {}, timeoutMs = NETWORK_TIMEOUT_MS) {
  const timeoutController = new AbortController();
  const upstreamSignal = init.signal;
  const abortFromUpstream = () => timeoutController.abort(upstreamSignal?.reason);
  if (upstreamSignal) {
    if (upstreamSignal.aborted) abortFromUpstream();
    else upstreamSignal.addEventListener("abort", abortFromUpstream, { once: true });
  }
  const timer = setTimeout(() => timeoutController.abort(new DOMException("Network timeout", "TimeoutError")), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: timeoutController.signal });
  } finally {
    clearTimeout(timer);
    upstreamSignal?.removeEventListener?.("abort", abortFromUpstream);
  }
}
const isPmtilesRequest = (request) => {
  const url = new URL(request.url);
  return url.pathname.endsWith(".pmtiles") || request.headers.has("range");
};
const isHashedBuildAsset = (url) => /\/assets\/[^/]+-[A-Za-z0-9_-]{6,}\.(?:js|css)$/.test(url.pathname);
const isRequiredShellAsset = (url) => REQUIRED_SHELL_PATHS.has(url.pathname);
const isStaticVisualAsset = (url) => /\/(?:icons|fonts)\//.test(url.pathname) || /\.(?:png|jpe?g|webp|svg|woff2?|ttf|webmanifest)$/.test(url.pathname);
const isVersionedDataAsset = (url) => url.pathname.includes("/data/kri/") && !url.pathname.endsWith(".pmtiles");
const isSentinelTileRequest = (url) => url.pathname.endsWith("/api/sentinel2") && url.searchParams.has("z") && url.searchParams.has("x") && url.searchParams.has("y");
const isMapTilerSatelliteRequest = (url) => url.origin === "https://api.maptiler.com" && /^\/tiles\/satellite-v2\/\d+\/\d+\/\d+\.jpg$/u.test(url.pathname);
const isReleaseBinaryRequest = (request, url) => request.headers.has("range")
  || url.pathname.startsWith("/downloads/")
  || /\.(?:apk|aab|msi|exe|dmg|pkg)$/iu.test(url.pathname);
const isPrivateOrMutableRequest = (request, url) => request.headers.has("authorization")
  || url.pathname === "/api"
  || url.pathname.startsWith("/api/")
  || url.pathname.startsWith("/auth/")
  || url.pathname.startsWith("/releases/");

function usableShellResponse(path, response) {
  if (!response?.ok) return false;
  const type = response.headers.get("content-type")?.toLowerCase() || "";
  if (path.endsWith(".js")) return /(?:java|ecma)script/u.test(type);
  if (path.endsWith(".css")) return type.includes("text/css");
  return true;
}

function offlineFailureResponse(request, message = "Resource unavailable while offline") {
  const url = new URL(request.url);
  const jsonLike = /\.(?:json|geojson)$/u.test(url.pathname) || request.headers.get("accept")?.includes("application/json");
  return new Response(jsonLike ? JSON.stringify({ error: message }) : message, {
    status: 504,
    statusText: "Offline Gateway Timeout",
    headers: {
      "Content-Type": jsonLike ? "application/json; charset=utf-8" : "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
      "X-NAV-KURD-Offline": "1"
    }
  });
}

async function cacheEntry(cache, path, required, signal = undefined) {
  try {
    const response = await fetchWithTimeout(absolute(path), { cache: "reload", credentials: "same-origin", signal }, INSTALL_FETCH_TIMEOUT_MS);
    if (!usableShellResponse(path, response)) {
      if (required) throw new Error(`Required offline asset failed: ${path}`);
      return false;
    }
    await cache.put(absolute(path), response.clone());
    return true;
  } catch (error) {
    if (error?.name === "AbortError" || signal?.aborted) throw error;
    if (required) throw error;
    return false;
  }
}

async function runBounded(entries, concurrency, worker) {
  let cursor = 0;
  const results = new Array(entries.length);
  const runners = Array.from({ length: Math.min(concurrency, entries.length) }, async () => {
    while (cursor < entries.length) {
      const index = cursor++;
      results[index] = await worker(entries[index]);
    }
  });
  await Promise.all(runners);
  return results;
}

async function installRequiredShell() {
  const cache = await caches.open(SHELL_CACHE);
  const entries = PRECACHE.filter((item) => item.required);
  try {
    await runBounded(entries, 3, (entry) => cacheEntry(cache, entry.path, true));
  } catch (error) {
    // Never leave a partially installed candidate cache behind. The previous
    // active worker remains intact and the browser can retry this release later.
    await caches.delete(SHELL_CACHE);
    throw error;
  }
}

async function warmOptionalShell() {
  const cache = await caches.open(SHELL_CACHE);
  const entries = PRECACHE.filter((item) => !item.required && item.warm !== false);
  const cached = await runBounded(entries, 8, async (entry) => Boolean(await cache.match(absolute(entry.path))));
  const missing = entries.filter((_, index) => !cached[index]);
  const results = await runBounded(missing, 4, (entry) => cacheEntry(cache, entry.path, false));
  return entries.length - missing.length + results.filter(Boolean).length;
}

function normalizedLanguage(value) {
  return ["ku", "ar", "en"].includes(value) ? value : "ku";
}

function offlineRuntimeEntries(language = "ku") {
  const selected = normalizedLanguage(language);
  return PRECACHE.filter((entry) => entry.offlineRuntime === true && (!entry.language || entry.language === selected));
}

function languageAssetEntries(language = "ku", assetKind = "all") {
  const selected = normalizedLanguage(language);
  return PRECACHE.filter((entry) => entry.language === selected
    && entry.languageAsset
    && (assetKind === "all" || entry.languageAsset === assetKind));
}

async function inspectLanguageAssets(cache, language = "ku", assetKind = "all") {
  const selected = normalizedLanguage(language);
  const entries = languageAssetEntries(selected, assetKind);
  let cachedEntries = 0;
  const missing = [];
  for (const entry of entries) {
    if (await cache.match(absolute(entry.path))) cachedEntries += 1;
    else missing.push(entry);
  }
  return {
    language: selected,
    cached: entries.length > 0 && cachedEntries === entries.length,
    cachedEntries,
    totalEntries: entries.length,
    missing
  };
}

async function inspectOfflineRuntime(cache, entries = offlineRuntimeEntries("ku")) {
  let cachedBytes = 0;
  let cachedEntries = 0;
  const missing = [];
  for (const entry of entries) {
    const cached = await cache.match(absolute(entry.path));
    if (cached) {
      cachedEntries += 1;
      cachedBytes += Number(entry.bytes) || 0;
    } else {
      missing.push(entry);
    }
  }
  return {
    cachedBytes,
    totalBytes: entries.reduce((sum, entry) => sum + (Number(entry.bytes) || 0), 0),
    cachedEntries,
    totalEntries: entries.length,
    missing
  };
}

async function readOfflineRuntimeMarker(cache) {
  const response = await cache.match(absolute(OFFLINE_READY_MARKER_PATH));
  if (!response) return null;
  try {
    const marker = await response.json();
    if (marker?.release !== RELEASE_ID
      || marker?.mapDataVersion !== MAP_DATA_VERSION
      || marker?.offlinePackVersion !== OFFLINE_PACK_VERSION) return null;
    if (marker.schema === 1
      && Array.isArray(marker.preparedLanguages)
      && marker.languages
      && typeof marker.languages === "object") return marker;
  } catch { /* invalid marker is treated as absent */ }
  return null;
}

async function writeOfflineRuntimeMarker(cache, marker) {
  const url = absolute(OFFLINE_READY_MARKER_PATH);
  if (!marker || marker.preparedLanguages.length === 0) {
    await cache.delete(url);
    return;
  }
  await cache.put(url, new Response(JSON.stringify(marker), {
    status: 200,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }
  }));
}

async function hasOfflineRuntimeMarker(language = null) {
  const cache = await caches.open(DATA_CACHE);
  const marker = await readOfflineRuntimeMarker(cache);
  if (!marker) return false;
  const selectedLanguages = language === null ? marker.preparedLanguages : [normalizedLanguage(language)];
  if (selectedLanguages.length === 0) return false;
  for (const selected of selectedLanguages) {
    if (!marker.preparedLanguages.includes(selected)) continue;
    const state = await inspectOfflineRuntime(cache, offlineRuntimeEntries(selected));
    const saved = marker.languages[selected];
    if (saved
      && saved.cachedBytes === state.totalBytes
      && saved.cachedEntries === state.totalEntries
      && state.cachedBytes === state.totalBytes
      && state.cachedEntries === state.totalEntries) return true;
  }
  return false;
}

async function setOfflineRuntimeMarker(ready, state = null, language = "ku") {
  const selected = normalizedLanguage(language);
  const cache = await caches.open(DATA_CACHE);
  const currentMarker = await readOfflineRuntimeMarker(cache);
  const marker = currentMarker ?? {
    schema: 1,
    release: RELEASE_ID,
    mapDataVersion: MAP_DATA_VERSION,
    offlinePackVersion: OFFLINE_PACK_VERSION,
    preparedLanguages: [],
    languages: {}
  };
  marker.preparedLanguages = marker.preparedLanguages.filter((entry) => entry !== selected);
  delete marker.languages[selected];
  if (ready) {
    const current = state ?? await inspectOfflineRuntime(cache, offlineRuntimeEntries(selected));
    marker.preparedLanguages.push(selected);
    marker.preparedLanguages.sort();
    marker.languages[selected] = {
      cachedBytes: current.cachedBytes,
      cachedEntries: current.cachedEntries,
      cachedAt: new Date().toISOString()
    };
  }
  await writeOfflineRuntimeMarker(cache, marker);
}

async function clearOfflineRuntimeMarker() {
  const cache = await caches.open(DATA_CACHE);
  await cache.delete(absolute(OFFLINE_READY_MARKER_PATH));
}

async function warmFullOfflineRuntime(reply, signal, language = "ku") {
  const selected = normalizedLanguage(language);
  const entries = offlineRuntimeEntries(selected);
  const cache = await caches.open(DATA_CACHE);
  let state = await inspectOfflineRuntime(cache, entries);
  await setOfflineRuntimeMarker(false, null, selected);
  reply({ type: "progress", ...state });

  await runBounded(state.missing, 2, async (entry) => {
    signal.throwIfAborted();
    const cached = await cacheEntry(cache, entry.path, false, signal);
    if (cached) {
      state.cachedEntries += 1;
      state.cachedBytes += Number(entry.bytes) || 0;
      reply({ type: "progress", cachedBytes: state.cachedBytes, totalBytes: state.totalBytes, cachedEntries: state.cachedEntries, totalEntries: state.totalEntries });
    }
    return cached;
  });

  state = await inspectOfflineRuntime(cache, entries);
  const complete = state.totalEntries > 0 && state.cachedEntries === state.totalEntries && state.cachedBytes === state.totalBytes;
  await setOfflineRuntimeMarker(complete, state, selected);
  return { ok: complete, cachedBytes: state.cachedBytes, totalBytes: state.totalBytes, cachedEntries: state.cachedEntries, totalEntries: state.totalEntries };
}

async function cancelFullOfflineRuntime() {
  offlineRuntimeAborter?.abort(new DOMException("Offline runtime download paused", "AbortError"));
  offlineRuntimeAborter = null;
}

async function clearFullOfflineRuntime() {
  const cache = await caches.open(DATA_CACHE);
  const entries = PRECACHE.filter((entry) => entry.offlineRuntime === true);
  await Promise.all(entries.map((entry) => cache.delete(absolute(entry.path))));
  await clearOfflineRuntimeMarker();
}

async function deleteOldCaches() {
  const keep = new Set([SHELL_CACHE, RUNTIME_CACHE, DATA_CACHE, SATELLITE_CACHE]);
  const keys = await caches.keys();
  // An old document may still import a hashed chunk after a new worker takes
  // control. Keep one verified prior shell for that in-flight import.
  const previousShell = [...keys].reverse().find((key) => key.startsWith(`${CACHE_PREFIX}shell-s${CACHE_SCHEMA}-`) && key !== SHELL_CACHE);
  if (previousShell) keep.add(previousShell);
  await Promise.all(keys
    .filter((key) => OWNED_CACHE_PREFIXES.some((prefix) => key.startsWith(prefix)) && !keep.has(key))
    .map((key) => caches.delete(key)));
}

async function notifyClients(type, detail = {}) {
  const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  for (const client of clients) client.postMessage({ type, ...detail });
}

async function networkFirst(request, cacheName, fallbackUrl) {
  const cache = await caches.open(cacheName);
  if (!workerIsOffline()) {
    try {
      const response = await fetchWithTimeout(request, { cache: "no-store" });
      if (response.ok) await cache.put(request, response.clone());
      return response;
    } catch { /* Cache fallback below. */ }
  }
  return (await cache.match(request)) || (fallbackUrl ? await caches.match(fallbackUrl) : undefined) || offlineFailureResponse(request);
}

async function offlineNavigation(event) {
  const request = event.request;
  const runtime = await caches.open(RUNTIME_CACHE);
  if (!workerIsOffline()) {
    try {
      // Navigation preload starts in parallel with worker boot. Consume it
      // before issuing a fallback fetch so one navigation never creates two
      // competing network requests.
      const preloaded = await event.preloadResponse;
      if (preloaded) {
        if (preloaded.ok) await runtime.put(request, preloaded.clone());
        return preloaded;
      }
      const response = await fetchWithTimeout(request, { cache: "no-store" }, NETWORK_TIMEOUT_MS);
      if (response.ok) await runtime.put(request, response.clone());
      return response;
    } catch { /* Deterministic offline response below. */ }
  }
  if (await hasOfflineRuntimeMarker(null)) {
    return (await caches.match(absolute("index.html"))) || (await caches.match(absolute(OFFLINE_FALLBACK_PATH))) || offlineFailureResponse(request);
  }
  return (await caches.match(absolute(OFFLINE_FALLBACK_PATH))) || (await caches.match(absolute("index.html"))) || offlineFailureResponse(request);
}

async function cacheFirst(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  const path = new URL(request.url).pathname;
  if (usableShellResponse(path, cached)) return cached;
  if (cached) await cache.delete(request);
  // The new worker can control a page with the previous release's HTML.
  // Its hashed main chunk is still valid in the previous atomic shell.
  if (cacheName === SHELL_CACHE) {
    const names = await caches.keys();
    for (const name of [...names].reverse()) {
      if (name === SHELL_CACHE || !name.startsWith(`${CACHE_PREFIX}shell-s${CACHE_SCHEMA}-`)) continue;
      const previous = await (await caches.open(name)).match(request);
      if (usableShellResponse(path, previous)) return previous;
    }
  }
  if (workerIsOffline()) return offlineFailureResponse(request);
  try {
    const response = await fetchWithTimeout(request, {}, SHELL_FETCH_TIMEOUT_MS);
    if (!usableShellResponse(path, response)) return offlineFailureResponse(request);
    await cache.put(request, response.clone());
    return response;
  } catch {
    return (await cache.match(request)) || offlineFailureResponse(request);
  }
}

function canonicalDataUrl(request) {
  const url = new URL(request.url);
  url.search = "";
  url.hash = "";
  return url.toString();
}

async function cacheFirstVersionedData(request) {
  const cache = await caches.open(DATA_CACHE);
  const key = canonicalDataUrl(request);
  const cached = (await cache.match(key)) || (await cache.match(request));
  if (cached) return cached;
  if (workerIsOffline()) return offlineFailureResponse(request);
  const existing = versionedDataFetches.get(key);
  if (existing) return (await existing).clone();

  const task = (async () => {
    try {
      // Language/property packs are immutable and can exceed one MiB. A short API
      // timeout used to abort valid mobile downloads and reject the FetchEvent.
      const response = await fetchWithTimeout(
        request,
        { cache: "no-store", credentials: "same-origin" },
        VERSIONED_DATA_TIMEOUT_MS
      );
      if (response.ok) await cache.put(key, response.clone());
      return response;
    } catch {
      // A FetchEvent must always resolve with a Response. Recheck the cache in
      // case another tab completed the same immutable request while this one ran.
      return (await cache.match(key)) || (await cache.match(request)) || offlineFailureResponse(request);
    }
  })().finally(() => {
    if (versionedDataFetches.get(key) === task) versionedDataFetches.delete(key);
  });
  versionedDataFetches.set(key, task);
  return (await task).clone();
}

async function trimCache(cache, limit) {
  const keys = await cache.keys();
  if (keys.length <= limit) return;
  await Promise.all(keys.slice(0, keys.length - limit).map((key) => cache.delete(key)));
}

async function trimCacheAfterWrite(cacheName, cache, limit) {
  let state = cacheTrimStates.get(cacheName);
  if (!state) {
    // Verify the persisted cache on the first write after worker startup, then
    // amortize keys()/delete scans across a bounded batch of later writes.
    state = { writes: CACHE_TRIM_WRITE_BATCH - 1, dirty: false, task: null };
    cacheTrimStates.set(cacheName, state);
  }
  state.writes += 1;
  if (state.writes < CACHE_TRIM_WRITE_BATCH) return state.task;
  state.writes = 0;
  state.dirty = true;
  if (!state.task) {
    const task = (async () => {
      while (state.dirty) {
        state.dirty = false;
        await trimCache(cache, limit);
      }
    })().finally(() => {
      if (state.task === task) state.task = null;
    });
    state.task = task;
  }
  return state.task;
}

async function staleWhileRevalidate(request, cacheName, limit = 0, lifetimeEvent = null) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (workerIsOffline()) return cached || offlineFailureResponse(request);
  const network = fetchWithTimeout(request)
    .then(async (response) => {
      if (response.ok) {
        await cache.put(request, response.clone());
        if (limit > 0) await trimCacheAfterWrite(cacheName, cache, limit);
      }
      return response;
    })
    .catch(() => undefined);
  if (cached && lifetimeEvent) lifetimeEvent.waitUntil(network.then(() => undefined));
  return cached || (await network) || offlineFailureResponse(request);
}

async function cacheFirstVisual(request, lifetimeEvent = null) {
  const [shell, runtime] = await Promise.all([caches.open(SHELL_CACHE), caches.open(RUNTIME_CACHE)]);
  const cached = (await shell.match(request)) || (await runtime.match(request));
  if (cached) return cached;
  if (workerIsOffline()) return offlineFailureResponse(request);
  try {
    // Visual assets are immutable and browser-cacheable. Do not impose the
    // general 4.5-second API timeout on fonts/icons over constrained mobile links.
    const response = await fetch(request, { cache: "force-cache", credentials: "same-origin" });
    if (response.ok) {
      const write = runtime.put(request, response.clone())
        .then(() => trimCacheAfterWrite(RUNTIME_CACHE, runtime, RUNTIME_CACHE_LIMIT));
      if (lifetimeEvent) lifetimeEvent.waitUntil(write);
      else await write;
    }
    return response;
  } catch {
    return offlineFailureResponse(request);
  }
}

function satelliteCacheRequest(request) {
  const url = new URL(request.url);
  url.searchParams.delete("key");
  return new Request(url.toString(), { method: "GET", mode: "no-cors", credentials: "omit", referrerPolicy: "no-referrer" });
}

function transparentSatelliteTile() {
  return new Response(TRANSPARENT_TILE_BYTES.slice(0), {
    status: 200,
    headers: {
      "Content-Type": "image/png",
      "Cache-Control": "no-store",
      "X-NAV-KURD-Satellite-Cache": "offline-transparent"
    }
  });
}

async function cachedMapTilerSatellite(request, lifetimeEvent = null) {
  const cache = await caches.open(SATELLITE_CACHE);
  const key = satelliteCacheRequest(request);
  const cached = await cache.match(key);
  if (workerIsOffline()) return cached || transparentSatelliteTile();
  const network = fetchWithTimeout(request)
    .then(async (response) => {
      if (response.ok || response.type === "opaque") {
        await cache.put(key, response.clone());
        await trimCacheAfterWrite(SATELLITE_CACHE, cache, SATELLITE_CACHE_LIMIT);
      }
      return response;
    })
    .catch(() => undefined);
  if (cached && lifetimeEvent) lifetimeEvent.waitUntil(network.then(() => undefined));
  return cached || (await network) || transparentSatelliteTile();
}

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    await installRequiredShell();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    await deleteOldCaches();
    if (self.registration.navigationPreload) {
      try { await self.registration.navigationPreload.enable(); } catch { /* optional capability */ }
    }
    await self.clients.claim();
    await updateNavKurdWidgets();
    await notifyClients("NAV_KURD_SW_ACTIVATED", {
      release: RELEASE_ID,
      mapDataVersion: MAP_DATA_VERSION,
      cacheSchema: CACHE_SCHEMA,
      offlinePackVersion: OFFLINE_PACK_VERSION
    });
  })());
});

self.addEventListener("message", (event) => {
  const data = event.data || {};
  const reply = (payload) => event.ports?.[0]?.postMessage(payload);

  if (data.type === "SKIP_WAITING") {
    event.waitUntil(self.skipWaiting());
    return;
  }

  if (data.type === "GET_RUNTIME_INFO") {
    reply({
      release: RELEASE_ID,
      mapDataVersion: MAP_DATA_VERSION,
      cacheSchema: CACHE_SCHEMA,
      offlinePackVersion: OFFLINE_PACK_VERSION,
      shellCache: SHELL_CACHE,
      runtimeCache: RUNTIME_CACHE,
      dataCache: DATA_CACHE
    });
    return;
  }

  if (data.type === "CLEAR_RUNTIME_CACHES") {
    event.waitUntil((async () => {
      await Promise.all([caches.delete(RUNTIME_CACHE), caches.delete(DATA_CACHE), caches.delete(SATELLITE_CACHE)]);
      reply({ ok: true });
    })());
    return;
  }

  if (data.type === "MAINTAIN_RUNTIME_CACHES") {
    event.waitUntil((async () => {
      await deleteOldCaches();
      const inactiveForMs = Math.max(0, Number(data.inactiveForMs) || 0);
      if (inactiveForMs >= 10 * 60 * 1000) {
        const [runtime, satellite] = await Promise.all([
          caches.open(RUNTIME_CACHE),
          caches.open(SATELLITE_CACHE)
        ]);
        await Promise.all([
          trimCache(runtime, RUNTIME_CACHE_LIMIT),
          trimCache(satellite, SATELLITE_CACHE_LIMIT)
        ]);
      }
      reply({ ok: true, release: RELEASE_ID, cacheSchema: CACHE_SCHEMA, inactiveForMs });
    })());
    return;
  }

  if (data.type === "WARM_OFFLINE_SHELL") {
    event.waitUntil((async () => {
      const cached = await warmOptionalShell();
      reply({ ok: true, cached });
    })());
    return;
  }

  if (data.type === "WARM_OFFLINE_RUNTIME") {
    event.waitUntil((async () => {
      await cancelFullOfflineRuntime();
      const controller = new AbortController();
      const language = normalizedLanguage(data.language);
      offlineRuntimeAborter = controller;
      try {
        const result = await warmFullOfflineRuntime(reply, controller.signal, language);
        reply({ type: "complete", ...result });
      } catch (error) {
        const cache = await caches.open(DATA_CACHE);
        const state = await inspectOfflineRuntime(cache, offlineRuntimeEntries(language));
        const cancelled = error?.name === "AbortError";
        reply({
          type: "complete",
          ok: false,
          cancelled,
          reason: cancelled ? "cancelled" : (error?.message || "runtime-cache-write-failed"),
          missingPaths: state.missing.map((entry) => entry.path),
          cachedBytes: state.cachedBytes,
          totalBytes: state.totalBytes,
          cachedEntries: state.cachedEntries,
          totalEntries: state.totalEntries
        });
      } finally {
        if (offlineRuntimeAborter === controller) offlineRuntimeAborter = null;
      }
    })());
    return;
  }

  if (data.type === "CANCEL_OFFLINE_RUNTIME") {
    event.waitUntil((async () => { await cancelFullOfflineRuntime(); reply({ ok: true, cancelled: true }); })());
    return;
  }

  if (data.type === "CLEAR_OFFLINE_RUNTIME") {
    event.waitUntil((async () => { await cancelFullOfflineRuntime(); await clearFullOfflineRuntime(); reply({ ok: true }); })());
    return;
  }

  if (data.type === "CHECK_OFFLINE_RUNTIME") {
    event.waitUntil((async () => {
      const language = normalizedLanguage(data.language);
      const cache = await caches.open(DATA_CACHE);
      const state = await inspectOfflineRuntime(cache, offlineRuntimeEntries(language));
      const markerValid = await hasOfflineRuntimeMarker(language);
      const entriesComplete = state.totalEntries > 0
        && state.cachedEntries === state.totalEntries
        && state.cachedBytes === state.totalBytes;
      reply({
        ok: markerValid && entriesComplete,
        language,
        reason: !entriesComplete ? "runtime-assets-missing" : !markerValid ? "runtime-marker-missing" : "ready",
        missingPaths: state.missing.map((entry) => entry.path),
        ...state
      });
    })());
    return;
  }

  if (data.type === "CHECK_LANGUAGE_ASSETS") {
    event.waitUntil((async () => {
      const language = normalizedLanguage(data.language);
      const assetKind = data.assetKind === "search" ? "search" : "properties";
      const cache = await caches.open(DATA_CACHE);
      const state = await inspectLanguageAssets(cache, language, assetKind);
      reply({ ok: true, assetKind, ...state });
    })());
    return;
  }

  if (data.type === "WARM_LANGUAGE_ASSETS" || data.type === "WARM_LANGUAGE_SEARCH") {
    event.waitUntil((async () => {
      const language = normalizedLanguage(data.language);
      const assetKind = data.type === "WARM_LANGUAGE_SEARCH" || data.assetKind === "search" ? "search" : "properties";
      const cache = await caches.open(DATA_CACHE);
      let state = await inspectLanguageAssets(cache, language, assetKind);
      if (state.missing.length > 0) {
        await runBounded(state.missing, 2, (entry) => cacheEntry(cache, entry.path, false));
        state = await inspectLanguageAssets(cache, language, assetKind);
      }
      reply({ ok: state.cached, assetKind, ...state });
    })());
    return;
  }
});


async function refreshResilienceData() {
  const cached = await warmOptionalShell();
  await notifyClients("NAV_KURD_BACKGROUND_REFRESH", { cached, release: RELEASE_ID });
  return cached;
}

function safeNotificationUrl(value) {
  try {
    const url = new URL(value || "", BASE);
    return url.origin === self.location.origin ? url.toString() : BASE;
  } catch {
    return BASE;
  }
}

function readPushPayload(event) {
  if (!event.data) return {};
  try {
    return event.data.json();
  } catch {
    try { return { body: event.data.text() }; } catch { return {}; }
  }
}

async function focusOrOpenClient(targetUrl) {
  const target = safeNotificationUrl(targetUrl);
  const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  for (const client of windows) {
    if (new URL(client.url).origin !== self.location.origin) continue;
    if ("focus" in client) {
      await client.focus();
      if ("navigate" in client && client.url !== target) await client.navigate(target);
      return;
    }
  }
  await self.clients.openWindow(target);
}

async function renderWidget(widget) {
  if (!self.widgets || !widget?.definition || widget.definition.tag !== WIDGET_TAG) return;
  const templateUrl = widget.definition.msAcTemplate;
  const dataUrl = widget.definition.data;
  if (!templateUrl || !dataUrl) return;
  const [templateResponse, dataResponse] = await Promise.all([fetch(templateUrl), fetch(dataUrl)]);
  if (!templateResponse.ok || !dataResponse.ok) return;
  const [template, data] = await Promise.all([templateResponse.text(), dataResponse.text()]);
  await self.widgets.updateByTag(widget.definition.tag, { template, data });
}

async function updateNavKurdWidgets() {
  if (!self.widgets?.getByTag) return;
  const widget = await self.widgets.getByTag(WIDGET_TAG);
  if (widget) await renderWidget(widget);
}

async function installNavKurdWidget(widget) {
  if (!widget?.definition || widget.definition.tag !== WIDGET_TAG) return;
  if (self.registration.periodicSync && Number.isFinite(widget.definition.update)) {
    try {
      const tags = await self.registration.periodicSync.getTags();
      if (!tags.includes(WIDGET_TAG)) {
        await self.registration.periodicSync.register(WIDGET_TAG, { minInterval: widget.definition.update * 1000 });
      }
    } catch {
      // Widget rendering still works when periodic sync is unsupported or denied.
    }
  }
  await renderWidget(widget);
}

async function uninstallNavKurdWidget(widget) {
  if (!widget?.definition || widget.definition.tag !== WIDGET_TAG || !self.registration.periodicSync) return;
  if (widget.instances?.length === 1) {
    try { await self.registration.periodicSync.unregister(WIDGET_TAG); } catch { /* optional capability */ }
  }
}

self.addEventListener("sync", (event) => {
  if (event.tag !== BACKGROUND_SYNC_TAG) return;
  event.waitUntil(refreshResilienceData());
});

self.addEventListener("periodicsync", (event) => {
  if (event.tag === PERIODIC_SYNC_TAG) {
    event.waitUntil(refreshResilienceData());
    return;
  }
  if (event.tag === WIDGET_TAG) event.waitUntil(updateNavKurdWidgets());
});

self.addEventListener("push", (event) => {
  const payload = readPushPayload(event);
  const title = typeof payload.title === "string" && payload.title.trim() ? payload.title.trim() : "NAV KURD";
  const body = typeof payload.body === "string" ? payload.body : "NAV KURD";
  const targetUrl = safeNotificationUrl(payload.url);
  event.waitUntil(self.registration.showNotification(title, {
    body,
    icon: absolute("icons/nav-kurd-icon-192.png"),
    badge: absolute("icons/favicon-32x32.png"),
    tag: typeof payload.tag === "string" ? payload.tag : "nav-kurd-update",
    renotify: false,
    data: { url: targetUrl }
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(focusOrOpenClient(event.notification.data?.url));
});

self.addEventListener("widgetinstall", (event) => {
  if (event.widget?.definition?.tag !== WIDGET_TAG) return;
  event.waitUntil(Promise.all([refreshResilienceData(), installNavKurdWidget(event.widget)]));
});

self.addEventListener("widgetuninstall", (event) => {
  if (event.widget?.definition?.tag !== WIDGET_TAG) return;
  event.waitUntil(uninstallNavKurdWidget(event.widget));
});

self.addEventListener("widgetresume", (event) => {
  if (event.widget?.definition?.tag !== WIDGET_TAG) return;
  event.waitUntil(renderWidget(event.widget));
});

self.addEventListener("widgetclick", (event) => {
  if (event.widget?.definition?.tag !== WIDGET_TAG) return;
  event.waitUntil(focusOrOpenClient(BASE));
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET" || isPmtilesRequest(request)) return;

  const url = new URL(request.url);
  if (isMapTilerSatelliteRequest(url)) {
    event.respondWith(cachedMapTilerSatellite(request, event));
    return;
  }
  if (!isSameOrigin(request)) return;
  // Never retain signed installers, byte-range responses, credentials or
  // mutable API payloads in CacheStorage. These requests stay browser/network
  // owned and therefore cannot leak into the offline runtime cache.
  if (isReleaseBinaryRequest(request, url) || isPrivateOrMutableRequest(request, url)) return;

  if (request.mode === "navigate") {
    event.respondWith(offlineNavigation(event));
    return;
  }

  if (url.pathname.endsWith("/offline-manifest.json")) {
    event.respondWith(networkFirst(request, SHELL_CACHE));
    return;
  }

  if (isRequiredShellAsset(url)) {
    event.respondWith(cacheFirst(request, SHELL_CACHE));
    return;
  }

  if (isSentinelTileRequest(url)) {
    event.respondWith(staleWhileRevalidate(request, SATELLITE_CACHE, SATELLITE_CACHE_LIMIT, event));
    return;
  }

  if (isHashedBuildAsset(url)) {
    event.respondWith(cacheFirst(request, SHELL_CACHE));
    return;
  }

  if (isVersionedDataAsset(url)) {
    event.respondWith(cacheFirstVersionedData(request));
    return;
  }

  if (isStaticVisualAsset(url)) {
    event.respondWith(cacheFirstVisual(request, event));
    return;
  }

  event.respondWith(networkFirst(request, RUNTIME_CACHE));
});
