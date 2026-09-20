/// Temporary R16 presentation transport, not another GPS provider. Device fixes,
/// permission and recent-location ownership live in NativeLocationService.
const nativeLocationPresentationScript = r'''
(() => {
  'use strict';
  if (window.top !== window || window.__NAV_KURD_LOCATION_PRESENTATION__) return;
  Object.defineProperty(window, '__NAV_KURD_LOCATION_PRESENTATION__', {value: true});
  let sequence = 0;
  const subscribers = new Map();
  let reconcile = Promise.resolve();
  const ready = new Promise(resolve => {
    if (window.flutter_inappwebview?.callHandler) resolve();
    else window.addEventListener('flutterInAppWebViewPlatformReady', resolve, {once: true});
  });
  const failure = (code, message) => ({code, message, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3});
  const deliverError = (entry, error) => {
    if (typeof entry.error === 'function') queueMicrotask(() => entry.error(error));
    else console.error(`NAV KURD location: ${error.message}`);
  };
  function synchronize() {
    reconcile = reconcile.then(async () => {
      await ready;
      const reply = await window.flutter_inappwebview.callHandler('nativeLocationControl',
        {operation: subscribers.size ? 'start' : 'stop'});
      if (!reply?.ok) throw failure(reply?.error?.code === 'permission_denied' ? 1 : 2,
        reply?.error?.message || 'Native location failed.');
    }).catch(error => {
      const message = error?.code ? error : failure(2, String(error));
      for (const [id, entry] of [...subscribers]) {
        if (entry.once) clearWatch(id);
        deliverError(entry, message);
      }
    });
  }
  function clearWatch(id) {
    const entry = subscribers.get(id);
    if (!entry) return;
    clearTimeout(entry.timeout); subscribers.delete(id);
    if (!subscribers.size) synchronize();
  }
  function add(success, error, options, once) {
    if (typeof success !== 'function') throw new TypeError('A position callback is required.');
    const id = ++sequence;
    const maximumAge = Math.max(0, Number(options?.maximumAge) || 0);
    const timeout = options?.timeout === undefined ? Infinity : Math.max(0, Number(options.timeout) || 0);
    const entry = {success, error, once, maximumAge, started: Date.now(), timeout: null};
    subscribers.set(id, entry);
    if (Number.isFinite(timeout)) entry.timeout = setTimeout(() => {
      if (!subscribers.has(id)) return;
      if (once) clearWatch(id);
      deliverError(entry, failure(3, 'Location request timed out.'));
    }, Math.min(timeout, 2147483647));
    synchronize(); return id;
  }
  window.addEventListener('nav-kurd:native-location', event => {
    const update = event.detail;
    if (update?.type === 'position') {
      const p = update.position;
      const position = {timestamp: p.timestamp, coords: {latitude: p.latitude, longitude: p.longitude,
        accuracy: p.accuracy, heading: p.heading, speed: p.speed, altitude: p.altitude, altitudeAccuracy: null}};
      for (const [id, entry] of [...subscribers]) {
        if (p.timestamp < entry.started - entry.maximumAge) continue;
        clearTimeout(entry.timeout);
        if (entry.once) clearWatch(id);
        queueMicrotask(() => entry.success(position));
      }
    } else if (update?.type === 'error') {
      const error = failure(update.code === 'permission_denied' ? 1 : 2, update.message);
      for (const [id, entry] of [...subscribers]) {
        if (entry.once) clearWatch(id);
        deliverError(entry, error);
      }
    }
  });
  Object.defineProperty(navigator, 'geolocation', {configurable: false, value: Object.freeze({
    getCurrentPosition: (success, error, options) => {add(success, error, options, true);},
    watchPosition: (success, error, options) => add(success, error, options, false), clearWatch
  })});
  window.addEventListener('pagehide', () => {for (const id of [...subscribers.keys()]) clearWatch(id);});
})();
''';
