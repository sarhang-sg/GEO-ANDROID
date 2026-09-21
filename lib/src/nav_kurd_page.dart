import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/download_name.dart';
import 'package:geo_android/src/local/android_local_runtime.dart';
import 'package:geo_android/src/local/android_location.dart';
import 'package:geo_android/src/local/location_presentation_bridge.dart';
import 'package:geo_android/src/native_bridge.dart';
import 'package:geo_android/src/permission_coordinator.dart';
import 'package:geo_android/src/url_policy.dart';
import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';
import 'package:url_launcher/url_launcher.dart';

Map<String, Object?> _stringKeyedPayload(Map<Object?, Object?> value) {
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key case final String key) key: entry.value,
  };
}

final class NavKurdPage extends StatefulWidget {
  const NavKurdPage({required this.initialDeepLink, super.key});

  final String? initialDeepLink;

  @override
  State<NavKurdPage> createState() => _NavKurdPageState();
}

final class _NavKurdPageState extends State<NavKurdPage>
    with WidgetsBindingObserver {
  final NativeBridge _bridge = NativeBridge.instance;
  late final PermissionCoordinator _permissions;
  late final AndroidLocation _location;
  late Future<AndroidLocalRuntime> _localOpening;
  AndroidLocalRuntime? _local;
  Map<String, dynamic>? _runtimeInfo;
  StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  StreamSubscription<Map<String,dynamic>>? _mapSubscription;
  bool _trustedDocument = false;
  late Uri _initialUri;
  Future<void> _documentNavigation = Future.value();
  StreamSubscription<String>? _deepLinkSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  InAppWebViewController? _controller;
  bool _mainFrameFailed = false;
  bool _isOnline = true;
  bool _connectivityKnown = false;
  bool _notificationsAsked = false;
  int _webViewGeneration = 0;
  String? _offlinePackStatus;

  static const Color _background = Color(0xFF061225);

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    domStorageEnabled: true,
    databaseEnabled: true,
    geolocationEnabled: false,
    useShouldInterceptRequest: true,
    cacheEnabled: true,
    cacheMode: CacheMode.LOAD_DEFAULT,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
    supportMultipleWindows: false,
    thirdPartyCookiesEnabled: true,
    transparentBackground: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    overScrollMode: OverScrollMode.NEVER,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    safeBrowsingEnabled: true,
    allowFileAccess: false,
    allowContentAccess: true,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    useHybridComposition: true,
    // Keep MapLibre's raster compositor on the GPU and use Android's supported
    // darkening control so satellite raster tiles retain their source colors.
    hardwareAcceleration: true,
    algorithmicDarkeningAllowed: false,
    // This WebView already fills the screen; off-screen pre-rasterization is
    // unnecessary and adds work while the map compositor is active.
    offscreenPreRaster: false,
    isInspectable: kDebugMode,
    applicationNameForUserAgent:
        'NAV-KURD-Flutter/${AppConfig.appVersion}',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissions = PermissionCoordinator(_bridge);
    _location = AndroidLocation(_permissions);
    _locationSubscription = _location.events.listen(_deliverLocation, onError: (Object error) {
      unawaited(_bridge.recordDiagnostic(level: 'error', source: 'native.location', message: error.toString()));
      _deliverLocation({'type':'error','code':'location_channel','message':'Native location service failed.'});
    });
    _localOpening = _openLocal();
    _initialUri = UrlPolicy.appUriForDeepLink(widget.initialDeepLink);
    _deepLinkSubscription = _bridge.deepLinks.listen(_handleDeepLink);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivity,
    );
    unawaited(_bridge.enterImmersiveMode());
    unawaited(_readInitialConnectivity());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_locationSubscription?.cancel());
    unawaited(_mapSubscription?.cancel());
    unawaited(_location.stop());
    unawaited(_local?.close());
    super.dispose();
  }

  Future<AndroidLocalRuntime> _openLocal() async {
    try {
      final runtimeFuture = AndroidLocalRuntime.open();
      final runtimeInfoFuture = _bridge.runtimeInfo();
      final runtime = await runtimeFuture;
      _runtimeInfo = await runtimeInfoFuture;
      if (!mounted) { await runtime.close(); throw StateError('Page disposed during local installation.'); }
      _local = runtime;
      _mapSubscription = runtime.mapEvents.listen((snapshot)=>unawaited(_deliverMapSnapshot(snapshot)),onError:(Object error,StackTrace stack){
        unawaited(_bridge.recordDiagnostic(level:'error',source:'local.maps.events',message:'$error',stack:stack.toString()));
      });
      return runtime;
    } catch (error, stack) {
      unawaited(_bridge.recordDiagnostic(level: 'error', source: 'local.startup', message: error.toString(), stack: stack.toString()));
      rethrow;
    }
  }
  void _deliverLocation(Map<String, dynamic> event) {
    final controller = _controller;
    if (!mounted || !_trustedDocument || controller == null) return;
    unawaited(controller.evaluateJavascript(source:
      'window.dispatchEvent(new CustomEvent("nav-kurd:native-location",{detail:${jsonEncode(event)}}));').catchError((Object error) {
        unawaited(_bridge.recordDiagnostic(level: 'error', source: 'location.presentation', message: error.toString()));
        return null;
      }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.inactive||state==AppLifecycleState.paused){
      unawaited(_persistLocalUi());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_bridge.enterImmersiveMode());
      unawaited(_bridge.refreshWidgetWeather());
      // Android's document/photo picker temporarily backgrounds the Flutter
      // activity. Tell the web runtime explicitly when its surface is usable
      // again; focus/visibility events are not reliable on every WebView OEM.
      unawaited(_notifyWebViewResumed());
      if (_mainFrameFailed) unawaited(_loadLocalDocument());
    }
  }

  Future<void> _notifyWebViewResumed() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(
        source:
            "window.dispatchEvent(new CustomEvent('nav-kurd:native-resume',{detail:{at:Date.now()}}));",
      );
    } catch (error, stack) {
      await _bridge.recordDiagnostic(level: 'warning', source: 'local.resume',
        message: '$error', stack: stack.toString());
    }
  }

  Future<void> _persistLocalUi() async {
    final controller = _controller;
    if (controller == null || !_trustedDocument) return;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: "if(window.__navKurdPersistUi) await window.__navKurdPersistUi(); else window.dispatchEvent(new Event('nav-kurd:native-suspend'));");
      if (result?.error != null) throw CoreFailure('preference_write', result!.error.toString());
    } catch (error, stack) {
      await _bridge.recordDiagnostic(level: 'error', source: 'local.lifecycle',
        message: 'UI persistence failed: $error', stack: stack.toString());
    }
  }

  Future<void> _loadLocalDocument({Uri? target}) {
    final task = _documentNavigation.then((_) async {
      final controller = _controller;
      if (controller == null || !mounted) return;
      final current = Uri.tryParse((await controller.getUrl())?.toString() ?? '');
      final next = target ?? (AppConfig.isTrustedOrigin(current) ? current! : _initialUri);
      if (!AppConfig.isTrustedOrigin(next)) throw const CoreFailure('untrusted_origin', 'Local navigation requires the approved origin.');
      await _persistLocalUi();
      final local = await _localOpening;
      if (!mounted || controller != _controller) return;
      _initialUri = next;
      _trustedDocument = false;
      await controller.loadData(data: local.initialDocument, baseUrl: WebUri(next.toString()),
        historyUrl: WebUri(next.toString()), mimeType: 'text/html', encoding: 'utf-8');
    });
    _documentNavigation = task.catchError((Object error, StackTrace stack) async {
      await _bridge.recordDiagnostic(level: 'error', source: 'local.navigation',
        message: '$error', stack: stack.toString());
      if (mounted) setState(() => _mainFrameFailed = true);
    });
    return _documentNavigation;
  }

  Future<void> _readInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _handleConnectivity(results);
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (!mounted || (_connectivityKnown && _isOnline == online)) return;
    _connectivityKnown = true;
    setState(() => _isOnline = online);
    unawaited(
      _bridge.updateWidget(
        status: online ? 'ONLINE' : 'OFFLINE',
        detail: online
            ? 'NAV KURD is connected'
            : 'Offline maps remain available',
      ),
    );
    if (online) unawaited(_bridge.refreshWidgetWeather());
  }

  void _handleDeepLink(String value) {
    if (!mounted) return;
    final controller = _controller;
    final raw = Uri.tryParse(value);
    if (raw?.scheme.toLowerCase() == 'navkurd' &&
        (raw?.host.toLowerCase() == 'open' ||
            raw?.host.toLowerCase() == 'locate')) {
      final action = raw?.host.toLowerCase() ?? 'open';
      unawaited(
        controller?.evaluateJavascript(
          source:
              "window.dispatchEvent(new CustomEvent('nav-kurd:widget-open',{detail:{action:'$action',at:Date.now()}}));",
        ),
      );
      return;
    }
    final target = UrlPolicy.appUriForDeepLink(value);
    unawaited(_loadLocalDocument(target: target));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidLocalRuntime>(
    future: _localOpening,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(backgroundColor: _background,
          body: _OfflinePanel(isOnline: true, localDataFailure: true,
            onRetry: () => setState(() => _localOpening = _openLocal()), onSettings: _bridge.openAppSettings));
      }
      if (!snapshot.hasData) return const Scaffold(backgroundColor: _background);
      return _buildReady(context);
    },
  );

  Widget _buildReady(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final controller = _controller;
        if (controller != null && await controller.canGoBack()) {
          await controller.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: _background,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            InAppWebView(
              key: ValueKey<int>(_webViewGeneration),
              initialData: InAppWebViewInitialData(data:_local!.initialDocument,
                baseUrl:WebUri(_initialUri.toString()),historyUrl:WebUri(_initialUri.toString()),
                mimeType:'text/html',encoding:'utf-8'),
              initialSettings: _settings,
              initialUserScripts: UnmodifiableListView<UserScript>(
                <UserScript>[
                  UserScript(
                    source:
                        'window.__NAV_KURD_NATIVE_HARDWARE__=Object.freeze(${jsonEncode(_runtimeInfo)});$_documentStartBridgeScript',
                  forMainFrameOnly: true,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                UserScript(source: nativeLocationPresentationScript,
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
                ],
              ),
              onWebViewCreated: _onWebViewCreated,
              shouldInterceptRequest: (controller, request) => _local!.resources.respond(request),
              onLoadStart: (controller, url) {
                _trustedDocument = AppConfig.isTrustedOrigin(Uri.tryParse(url?.toString() ?? ''));
                unawaited(_location.stop());
                if (!mounted) return;
                if (_mainFrameFailed) {
                  setState(() => _mainFrameFailed = false);
                }
              },
              onLoadStop: _onLoadStop,
              onReceivedError: (controller, request, error) {
                final description = error.description.toUpperCase();
                final isMainFrame = request.isForMainFrame == true;
                final isCancelledSubresource = !isMainFrame &&
                    (description.contains('ERR_FAILED') ||
                        description.contains('ERR_ABORTED') ||
                        description.contains('CANCEL'));
                if (isCancelledSubresource) return;
                unawaited(
                  _bridge.recordDiagnostic(
                    level: isMainFrame ? 'error' : 'warning',
                    source: 'webview.resource',
                    message: '${error.type}: ${error.description}',
                  ),
                );
                if (!isMainFrame || !mounted) return;
                setState(() {
                  _mainFrameFailed = true;
                });
              },
              onReceivedHttpError: (controller, request, response) {
                final status = response.statusCode ?? 0;
                if (request.isForMainFrame == true || status >= 500) {
                  unawaited(
                    _bridge.recordDiagnostic(
                      level: request.isForMainFrame == true ? 'error' : 'warning',
                      source: 'webview.http',
                      message: '$status ${response.reasonPhrase ?? 'HTTP error'}',
                    ),
                  );
                }
              },
              onConsoleMessage: (controller, message) {
                final level = message.messageLevel;
                final text = message.message;
                final isUnsupportedUsbPolicyWarning =
                    text.contains('Permissions-Policy header') &&
                    text.contains("Unrecognized feature: 'usb'");
                if (isUnsupportedUsbPolicyWarning) return;
                if (level == ConsoleMessageLevel.ERROR ||
                    level == ConsoleMessageLevel.WARNING) {
                  unawaited(
                    _bridge.recordDiagnostic(
                      level: level == ConsoleMessageLevel.ERROR
                          ? 'error'
                          : 'warning',
                      source: 'webview.console',
                      message: text,
                    ),
                  );
                }
              },
              onRenderProcessGone: (controller, detail) {
                unawaited(
                  _bridge.recordDiagnostic(
                    level: 'error',
                    source: 'webview.renderer',
                    message: detail.didCrash
                        ? 'Android WebView renderer crashed.'
                        : 'Android reclaimed the WebView renderer.',
                  ),
                );
                if (!mounted) return;
                setState(() {
                  _controller = null;
                  _mainFrameFailed = true;
                  _webViewGeneration += 1;
                });
              },
              onPermissionRequest: (controller, request) =>
                  _permissions.handleWebPermission(request),
              onDownloadStartRequest: (controller, request) async {
                await _handleDownload(controller, request);
              },
              shouldOverrideUrlLoading: _handleNavigation,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: _mainFrameFailed
                  ? _OfflinePanel(
                      key: const ValueKey<String>('offline'),
                      isOnline: _isOnline,
                      onRetry: () {
                        setState(() => _mainFrameFailed = false);
                        unawaited(_loadLocalDocument());
                      },
                      onSettings: _bridge.openAppSettings,
                    )
                  : const SizedBox.shrink(key: ValueKey<String>('map')),
            ),
          ],
        ),
      ),
    );
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    controller.addJavaScriptHandler(handlerName: 'nativeLocalCore', callback: _handleLocalCore);
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'nativeShare',
      callback: _handleNativeShare,
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeOpenExternal',
      callback: _handleOpenExternal,
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeSaveBase64',
      callback: _handleBase64Download,
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeLocationControl',
      callback: _handleLocationControl,
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeDiagnostics',
      callback: (_) async {
        if (!await _isCurrentOriginTrusted()) return '';
        return _bridge.diagnosticReport();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeRecordDiagnostic',
      callback: _handleNativeDiagnostic,
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeRuntimeInfo',
      callback: (arguments) async {
        if (!await _isCurrentOriginTrusted()) return <String, dynamic>{};
        final request = arguments.isNotEmpty && arguments.first is Map
            ? arguments.first as Map
            : const <Object?, Object?>{};
        return _bridge.runtimeInfo(includeStorage: request['includeStorage'] == true);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeClearTransientCache',
      callback: (_) async {
        if (!await _isCurrentOriginTrusted()) return <String, bool>{'cleared': false};
        await InAppWebViewController.clearAllCache();
        final cleared = await _bridge.clearTransientCache();
        return <String, bool>{'cleared': cleared};
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeOpenSettings',
      callback: (_) async {
        if (!await _isCurrentOriginTrusted()) return false;
        await _bridge.openAppSettings();
        return true;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeSetLanguage',
      callback: (List<dynamic> arguments) async {
        if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
        final value = arguments.first;
        if (value is! Map<Object?, Object?>) return false;
        final rawLanguage = value['language'];
        final language = rawLanguage is String ? rawLanguage : 'ku';
        await _bridge.setLanguage(language);
        return true;
      },
    );
  }

  Future<void> _onLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    if (!AppConfig.isTrustedOrigin(Uri.tryParse(url?.toString() ?? ''))) return;
    await controller.evaluateJavascript(source: _afterLoadBridgeScript);
    if (!mounted) return;
    if (_mainFrameFailed) setState(() => _mainFrameFailed = false);
    unawaited(_bridge.refreshWidgetWeather());
    if (!_notificationsAsked) {
      _notificationsAsked = true;
      unawaited(_requestNotificationsAfterLoad());
    }
  }

  Future<void> _requestNotificationsAfterLoad() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (await _permissions.requestNotifications()) {
      await _bridge.scheduleNotifications();
    }
  }

  Future<NavigationActionPolicy> _handleNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final webUri = action.request.url;
    final uri = Uri.tryParse(webUri?.toString() ?? '');
    if (uri == null) return NavigationActionPolicy.CANCEL;
    final decision = UrlPolicy.decide(
      uri,
      userGesture: action.hasGesture ?? false,
      linkActivated: action.navigationType == NavigationType.LINK_ACTIVATED,
    );
    switch (decision) {
      case UrlDecision.allowInWebView:
        return NavigationActionPolicy.ALLOW;
      case UrlDecision.openExternally:
        await _launchExternal(uri);
        return NavigationActionPolicy.CANCEL;
      case UrlDecision.block:
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<void> _handleDownload(
    InAppWebViewController controller,
    DownloadStartRequest request,
  ) async {
    final uri = Uri.tryParse(request.url.toString());
    if (uri == null || uri.scheme != 'https') {
      _showMessage('Only secure HTTPS downloads are allowed.');
      return;
    }
    if (!await _permissions.ensureDownloadPermission()) {
      _showMessage('Download permission was denied.');
      return;
    }

    final cookies = await CookieManager.instance().getCookies(url: request.url);
    final cookieHeader = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    final fileName = DownloadName.sanitize(request.suggestedFilename);
    final id = await _bridge.enqueueDownload(
      url: uri.toString(),
      fileName: fileName,
      mimeType: request.mimeType,
      userAgent: request.userAgent,
      cookies: cookieHeader.isEmpty ? null : cookieHeader,
    );
    _showMessage(
      id == null
          ? 'The download could not be started.'
          : '$fileName is downloading.',
      actionLabel: id == null ? null : 'Downloads',
      onAction: id == null ? null : _bridge.openDownloads,
    );
  }

  Future<Object?> _handleNativeShare(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! Map<Object?, Object?>) return false;
    final data = _stringKeyedPayload(value);
    final title = data['title']?.toString().trim() ?? '';
    final text = data['text']?.toString().trim() ?? '';
    final url = data['url']?.toString().trim() ?? '';
    final body = <String>[
      if (text.isNotEmpty) text,
      if (url.isNotEmpty) url,
    ].join('\n');
    if (body.isEmpty) return false;
    final shared = await _bridge.shareText(
      title: title,
      text: text,
      url: url,
    );
    if (!shared) {
      await _bridge.recordDiagnostic(
        level: 'warning',
        source: 'native.share',
        message: 'Android did not open a compatible share target.',
      );
    }
    return shared;
  }

  Future<Object?> _handleOpenExternal(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! String) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return _launchExternal(uri);
  }

  Future<Object?> _handleBase64Download(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! Map<Object?, Object?>) return false;
    final data = _stringKeyedPayload(value);
    final rawEncoded = data['data'];
    final encoded = rawEncoded is String ? rawEncoded : null;
    if (encoded == null || encoded.isEmpty) return false;
    if (encoded.length > 70 * 1024 * 1024) {
      _showMessage('This blob is too large for the native bridge.');
      return false;
    }
    if (!await _permissions.ensureDownloadPermission()) return false;
    final rawFileName = data['fileName'];
    final rawMimeType = data['mimeType'];
    final fileName = DownloadName.sanitize(
      rawFileName is String ? rawFileName : null,
    );
    final uri = await _bridge.saveBase64Download(
      fileName: fileName,
      mimeType: rawMimeType is String
          ? rawMimeType
          : 'application/octet-stream',
      base64Data: encoded,
    );
    _showMessage(
      uri == null ? 'The file could not be saved.' : '$fileName was saved.',
      actionLabel: uri == null ? null : 'Downloads',
      onAction: uri == null ? null : _bridge.openDownloads,
    );
    return uri != null;
  }

  Future<void> _deliverMapSnapshot(Map<String,dynamic> data) async {
    try {
      final status=data['status'] as String,progress=((data['progress'] as num)*100).round().clamp(0,100);
      final previous=_offlinePackStatus;
      _offlinePackStatus=status;
      final controller=_controller;
      if(mounted&&_trustedDocument&&controller!=null){
        await controller.evaluateJavascript(source:'window.dispatchEvent(new CustomEvent("nav-kurd:native-map-pack",{detail:${jsonEncode(data)}}));');
      }
      if(previous!=status){
        await _bridge.updateWidget(status:status=='ready'?'OFFLINE READY':status.toUpperCase(),
          detail:status=='ready'?'Kurdistan Atlas is available offline':'Offline map $progress%');
        if(status=='ready')await _bridge.showNotificationOnce(key:'offline-map-ready',title:'NAV KURD',body:'The Kurdistan offline map is ready.');
      }
    }catch(error,stack){
      await _bridge.recordDiagnostic(level:'error',source:'local.maps.presentation',message:'$error',stack:stack.toString());
    }
  }

  Map<String, Object?> _localError(Object error) {
    final code = error is CoreFailure ? error.code : error is PlatformException ? error.code : 'local_request';
    final message = error is CoreFailure ? error.message : error is PlatformException ? error.message ?? error.code : error.toString();
    if (code != 'cancelled') unawaited(_bridge.recordDiagnostic(level: 'error', source: 'local.request', message: '$code: $message'));
    return {'ok':false, 'error':{'code':code,'message':message}};
  }
  Future<Object?> _handleLocationControl(List<dynamic> arguments) async {
    try {
      if (!await _isCurrentOriginTrusted()) throw const CoreFailure('untrusted_origin','Location request origin is not trusted.');
      final request = Map<String, dynamic>.from(arguments.single as Map);
      final Object? value;
      switch (request['operation']) {
        case 'start': await _location.start(); value = null;
        case 'stop': await _location.stop(); value = null;
        case 'status': value = await _location.status();
        default: throw const CoreFailure('invalid_operation','Unknown location operation.');
      }
      return {'ok':true,'value':value};
    } catch (error) { return _localError(error); }
  }
  Future<Object?> _handleLocalCore(List<dynamic> arguments) async {
    try {
      if (!await _isCurrentOriginTrusted()) throw const CoreFailure('untrusted_origin','Local request origin is not trusted.');
      final request = Map<String, dynamic>.from(arguments.single as Map);
      final runtime = await _localOpening;
      final data = runtime.data;
      final Object? value;
      switch (request['operation']) {
        case 'mapPackSnapshot':value=runtime.takeInitialMapSnapshot()??await runtime.mapSnapshot();
        case 'mapPackDownload':value=await runtime.downloadMaps();
        case 'mapPackPause':value=await runtime.pauseMaps();
        case 'mapPackDelete':value=await runtime.deleteMaps();
        case 'poiManifest': value=await data.poiManifest();
        case 'poiShard': value=await data.poiShard(request['dataset'] as String,request['key'] as String);
        case 'statistics': value=await data.statistics();
        case 'localitySearch': value=await data.localitySearch(request['text'] as String,request['language'] as String,quick:request['quick']==true);
        case 'versions': value = await data.versions();
        case 'search': value = await data.search(request['text'] as String, request['language'] as String, limit: (request['limit'] as num?)?.toInt() ?? 24);
        case 'viewport': value = await data.viewport((request['bounds'] as List).map((v) => (v as num).toDouble()).toList(), request['language'] as String,
          datasets: List<String>.from(request['datasets'] as List), minimumLocalityRank:(request['minimumLocalityRank'] as num?)?.toInt()??0, after: (request['after'] as num?)?.toInt() ?? 0, limit: (request['limit'] as num?)?.toInt() ?? 128);
        case 'place': value = await data.place((request['id'] as num).toInt(), request['language'] as String);
        case 'reverse': value = await data.reverse((request['longitude'] as num).toDouble(), (request['latitude'] as num).toDouble(), request['language'] as String);
        case 'importNavigationHistory':value=await data.importNavigationHistory(request['raw'] as String?);
        case 'navigationHistory':value=await data.navigationHistory(request['userId'] as String?);
        case 'queueNavigationHistory':await data.queueNavigationHistory(Map<String,Object?>.from(request['entry'] as Map),request['userId'] as String?);value=null;
        case 'removeNavigationHistory':await data.removeNavigationHistory(request['id'] as String?,request['userId'] as String,expectedRevision:request['expectedRevision'] as int?);value=null;
        case 'importR16Preferences':value=await data.importR16Preferences(Map<String,Object?>.from(request['values'] as Map));
        case 'saveUiSnapshot':await data.saveUiSnapshot(Map<String,Object?>.from(request['snapshot'] as Map));value=null;
        case 'preference': value = await data.preference(request['key'] as String);
        case 'setPreference': await data.setPreference(request['key'] as String, request['value']); value = null;
        case 'removePreference': await data.removePreference(request['key'] as String); value = null;
        case 'mapMetadata': value = await data.mapMetadata(request['archive'] as String);
        case 'mapTile':
          final tile = await data.mapTile(request['archive'] as String, (request['z'] as num).toInt(), (request['x'] as num).toInt(), (request['y'] as num).toInt());
          value = tile == null ? null : base64Encode(tile);
        default: throw const CoreFailure('invalid_operation','Unknown local operation.');
      }
      return {'ok':true,'value':value};
    } catch (error) { return _localError(error); }
  }

  Future<Object?> _handleNativeDiagnostic(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! Map<Object?, Object?>) return false;
    final data = _stringKeyedPayload(value);
    final message = data['message']?.toString().trim() ?? '';
    if (message.isEmpty) return false;
    await _bridge.recordDiagnostic(
      level: data['level']?.toString() ?? 'warning',
      source: data['source']?.toString() ?? 'web.runtime',
      message: message,
      stack: data['stack']?.toString(),
    );
    return true;
  }

  Future<bool> _isCurrentOriginTrusted() async {
    // onLoadStart invalidates this flag before an untrusted document can run;
    // avoid a WebView URL round-trip on every native bridge request.
    return _trustedDocument && _controller != null;
  }

  Future<bool> _launchExternal(Uri uri) async {
    if (!const <String>{
      'https',
      'mailto',
      'tel',
      'sms',
      'geo',
      'market',
    }.contains(uri.scheme.toLowerCase())) {
      return false;
    }
    var target = uri;
    if (uri.scheme.toLowerCase() == 'mailto') {
      final body = uri.queryParameters['body'];
      if (body != null &&
          body.startsWith('NAV KURD feedback report') &&
          !body.contains('Diagnostics not included by the user.') &&
          !body.contains('[META] Native Android diagnostics')) {
        final nativeReport = await _bridge.diagnosticReport();
        target = uri.replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'body': '$body\n\n$nativeReport',
          },
        );
      }
    }
    try {
      return await launchUrl(target, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }

  void _showMessage(
    String message, {
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  onPressed: () => unawaited(onAction()),
                ),
        ),
      );
  }
}

final class _OfflinePanel extends StatelessWidget {
  const _OfflinePanel({
    required this.isOnline,
    this.localDataFailure = false,
    required this.onRetry,
    required this.onSettings,
    super.key,
  });

  final bool isOnline;
  final bool localDataFailure;
  final VoidCallback onRetry;
  final Future<void> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF061225),
      child: SafeArea(
        child: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Image.asset(
                    'assets/images/nav-kurd-logo.png',
                    width: 92,
                    height: 92,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    isOnline
                        ? 'نەتوانرا خەریتەکە بکرێتەوە'
                        : 'پەیوەندی ئینتەرنێت نییە',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    localDataFailure ? 'داتای خەریتەی ناوخۆیی نەکرایەوە. دووبارە هەوڵ بدە یان Settings بکەرەوە.' : 'دووبارە هەوڵ بدە، یان Settings بکەرەوە. پەکی خەریتەی offline دوای یەکەم دابەزاندن بەردەست دەبێت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFB8BCD1), height: 1.6),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('دووبارە هەوڵدان'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => unawaited(onSettings()),
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const String _documentStartBridgeScript = r'''
(() => {
  'use strict';
  Object.defineProperty(window, '__NAV_KURD_LOCAL_CORE__', {value: 1});
  Object.defineProperty(window, '__NAV_KURD_FLUTTER__', {
    value: true,
    configurable: false,
    enumerable: false,
    writable: false
  });

  const call = (name, payload) => {
    if (!window.flutter_inappwebview?.callHandler) return Promise.resolve(false);
    return window.flutter_inappwebview.callHandler(name, payload);
  };
  const record = (level, source, value) => {
    const error = value instanceof Error ? value : null;
    return call('nativeRecordDiagnostic', {
      level,
      source,
      message: String(error?.message || value || 'Unknown web runtime issue').slice(0, 1800),
      stack: String(error?.stack || '').slice(0, 6000)
    });
  };
  const platformFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const requestUrl = typeof input === 'string' ? input : String(input?.url || input || '');
    const isFeedbackSubmit = /\/rest\/v1\/rpc\/submit_atlas_feedback(?:\?|$)/.test(requestUrl);
    if (isFeedbackSubmit && typeof init?.body === 'string') {
      try {
        const payload = JSON.parse(init.body);
        const diagnostics = payload?.p_diagnostics;
        if (diagnostics && typeof diagnostics === 'object' &&
            Object.keys(diagnostics).length > 0) {
          const nativeReport = String(await call('nativeDiagnostics', {}) || '').slice(0, 12000);
          if (nativeReport) {
            payload.p_diagnostics = {
              ...diagnostics,
              android_native_report: nativeReport
            };
            return platformFetch(input, { ...init, body: JSON.stringify(payload) });
          }
        }
      } catch (error) {
        record('warning', 'web.feedback-bridge', error);
      }
    }
    return platformFetch(input, init);
  };
  try {
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: async data => {
        const handled = await call('nativeShare', data || {});
        if (handled !== true) throw new DOMException('Share was not handled', 'AbortError');
      }
    });
  } catch (_) { /* The browser implementation remains available. */ }

  try {
    const clipboard = navigator.clipboard;
    const writeText = clipboard?.writeText?.bind(clipboard);
    if (writeText) {
      Object.defineProperty(clipboard, 'writeText', {
        configurable: true,
        value: async value => {
          const text = String(value || '');
          if (!text.startsWith('NAV KURD feedback report') ||
              text.includes('Diagnostics not included by the user.')) {
            return writeText(text);
          }
          const nativeReport = String(await call('nativeDiagnostics', {}) || '').trim();
          return writeText(nativeReport && !text.includes('[META] Native Android diagnostics')
            ? `${text}\n\n${nativeReport}`
            : text);
        }
      });
    }
  } catch (_) { /* The secure clipboard remains available without enrichment. */ }

  window.addEventListener('error', event => {
    record('error', 'web.window', event.error || event.message);
  });
  window.addEventListener('unhandledrejection', event => {
    record('error', 'web.promise', event.reason);
  });

  document.addEventListener('click', event => {
    const anchor = event.target?.closest?.('a[href]');
    if (!anchor) return;
    const href = anchor.href || '';
    if (href.startsWith('blob:') && anchor.hasAttribute('download')) {
      event.preventDefault();
      fetch(href)
        .then(response => response.blob())
        .then(blob => new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve(reader.result);
          reader.onerror = reject;
          reader.readAsDataURL(blob);
        }))
        .then(data => call('nativeSaveBase64', {
          fileName: anchor.download || 'nav-kurd-file',
          mimeType: String(data).slice(5, String(data).indexOf(';')) || 'application/octet-stream',
          data: String(data)
        }))
        .catch(error => record('error', 'web.download', error));
      return;
    }
    if (anchor.target === '_blank') {
      event.preventDefault();
      try {
        const target = new URL(href, location.href);
        if (target.origin === location.origin) location.assign(target.href);
        else call('nativeOpenExternal', target.href);
      } catch (error) {
        record('warning', 'web.navigation', error);
      }
    }
  }, true);

  window.navKurdAndroid = Object.freeze({
    share: data => call('nativeShare', data || {}),
    openExternal: url => call('nativeOpenExternal', String(url || '')),
    saveBase64: data => call('nativeSaveBase64', data || {}),
    diagnostics: () => call('nativeDiagnostics', {}),
    recordDiagnostic: (level, source, message) => record(level, source, message)
  });
})();
''';

const String _afterLoadBridgeScript = r'''
(() => {
  'use strict';
  if (window.__NAV_KURD_FLUTTER_OBSERVER__) return;
  window.__NAV_KURD_FLUTTER_OBSERVER__ = true;

  const call = (name, payload) => {
    if (!window.flutter_inappwebview?.callHandler) return Promise.resolve(false);
    return window.flutter_inappwebview.callHandler(name, payload);
  };

  const marker = '[META] Native Android diagnostics';
  let applyingNativeReport = false;
  let reportRequestPending = false;
  let mergeTimer = 0;
  const mergeNativeReport = () => {
    mergeTimer = 0;
    if (applyingNativeReport || reportRequestPending) return;
    const preview = document.querySelector('[data-feedback-preview]');
    if (!preview || String(preview.textContent || '').includes(marker)) return;
    reportRequestPending = true;
    call('nativeDiagnostics', {}).then(report => {
      const nativeReport = String(report || '').trim();
      if (!nativeReport || !preview.isConnected) return;
      applyingNativeReport = true;
      const webReport = String(preview.textContent || '').trim();
      if (!webReport.includes(marker)) {
        if (webReport) preview.append(document.createTextNode('\n\n'));
        const fragment = document.createDocumentFragment();
        const nativeLines = nativeReport.split('\n');
        nativeLines.forEach((line, index) => {
          const span = document.createElement('span');
          const severity = line.startsWith('[ERROR]') ? 'error'
            : line.startsWith('[WARN]') ? 'warning'
            : line.startsWith('[OK]') ? 'ok'
            : line.startsWith('[INFO]') ? 'info'
            : 'meta';
          span.className = `diagnostic-line diagnostic-line--${severity}`;
          span.textContent = line || ' ';
          fragment.append(span);
          if (index < nativeLines.length - 1) {
            fragment.append(document.createTextNode('\n'));
          }
        });
        preview.append(fragment);
      }
      applyingNativeReport = false;
    }).catch(() => false).finally(() => {
      reportRequestPending = false;
    });
  };
  const scheduleMerge = () => {
    if (!mergeTimer) mergeTimer = window.setTimeout(mergeNativeReport, 100);
  };
  const watchFeedbackHost = host => {
    const reportObserver = new MutationObserver(() => {
      if (!applyingNativeReport) scheduleMerge();
    });
    reportObserver.observe(host, { childList: true, subtree: true });
    host.addEventListener('click', scheduleMerge, true);
    scheduleMerge();
  };
  const existingFeedbackHost = document.querySelector('.feedback-studio');
  if (existingFeedbackHost) {
    watchFeedbackHost(existingFeedbackHost);
  } else {
    const discoveryObserver = new MutationObserver(records => {
      const added = records.flatMap(record => Array.from(record.addedNodes));
      const host = added.find(node => node.nodeType === 1 && node.matches('.feedback-studio'));
      if (!host) return;
      discoveryObserver.disconnect();
      watchFeedbackHost(host);
    });
    // Observe only until the lazily loaded feedback host appears. The earlier code watched
    // every MapLibre DOM mutation forever and queried the whole document every
    // 100 ms while the map was busy.
    discoveryObserver.observe(document.body || document.documentElement, { childList: true });
  }
})();
''';
