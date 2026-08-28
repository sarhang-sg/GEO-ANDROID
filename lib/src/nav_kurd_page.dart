import 'dart:async';
import 'dart:collection';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/download_name.dart';
import 'package:geo_android/src/native_bridge.dart';
import 'package:geo_android/src/permission_coordinator.dart';
import 'package:geo_android/src/url_policy.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final Uri _initialUri;
  StreamSubscription<String>? _deepLinkSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  InAppWebViewController? _controller;
  bool _mainFrameFailed = false;
  bool _isOnline = true;
  bool _notificationsAsked = false;
  int _webViewGeneration = 0;
  String? _offlinePackStatus;

  static const Color _background = Color(0xFF090D19);

  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    domStorageEnabled: true,
    databaseEnabled: true,
    geolocationEnabled: true,
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bridge.enterImmersiveMode());
      unawaited(_bridge.refreshWidgetWeather());
      unawaited(
        _controller?.evaluateJavascript(
          source: "window.dispatchEvent(new CustomEvent('nav-kurd:native-resume', {detail:{at:Date.now()}}));",
        ),
      );
      if (_mainFrameFailed && _isOnline) unawaited(_controller?.reload());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(
        _controller?.evaluateJavascript(
          source: "window.dispatchEvent(new CustomEvent('nav-kurd:native-pause', {detail:{at:Date.now()}}));",
        ),
      );
    }
  }

  Future<void> _readInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _handleConnectivity(results);
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (!mounted) return;
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
    if (online && _mainFrameFailed) unawaited(_controller?.reload());
  }

  void _handleDeepLink(String value) {
    final target = UrlPolicy.appUriForDeepLink(value);
    unawaited(
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target.toString()))),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              initialUrlRequest: URLRequest(
                url: WebUri(_initialUri.toString()),
                headers: const <String, String>{
                  'X-NAV-KURD-CLIENT': 'flutter-android',
                },
              ),
              initialSettings: _settings,
              initialUserScripts: UnmodifiableListView<UserScript>(
                <UserScript>[
                  UserScript(
                    source: _documentStartBridgeScript,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ],
              ),
              onWebViewCreated: _onWebViewCreated,
              onLoadStart: (controller, url) {
                if (!mounted) return;
                if (_mainFrameFailed) {
                  setState(() => _mainFrameFailed = false);
                }
              },
              onLoadStop: _onLoadStop,
              onReceivedError: (controller, request, error) {
                unawaited(
                  _bridge.recordDiagnostic(
                    level: request.isForMainFrame == true ? 'error' : 'warning',
                    source: 'webview.resource',
                    message: '${error.type}: ${error.description}',
                  ),
                );
                if (request.isForMainFrame != true || !mounted) return;
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
              onGeolocationPermissionsShowPrompt: (controller, origin) async {
                final uri = Uri.tryParse(origin);
                final allowed = await _permissions.requestLocation(uri);
                return GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: allowed,
                  retain: allowed,
                );
              },
              onPermissionRequest: (controller, request) =>
                  _permissions.handleWebPermission(request),
              onDownloadStarting: (controller, request) async {
                await _handleDownload(controller, request);
                return DownloadStartResponse(handled: true);
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
                        unawaited(_controller?.reload());
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
      handlerName: 'offlinePackStatus',
      callback: _handleOfflinePackStatus,
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeLocationSnapshot',
      callback: _handleLocationSnapshot,
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
      callback: (_) async {
        if (!await _isCurrentOriginTrusted()) return <String, dynamic>{};
        return _bridge.runtimeInfo();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'nativeClearTransientCache',
      callback: (_) async {
        if (!await _isCurrentOriginTrusted()) return <String, bool>{'cleared': false};
        await controller.clearCache();
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
      callback: (arguments) async {
        if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
        final value = arguments.first;
        if (value is! Map) return false;
        final language = value['language']?.toString() ?? 'ku';
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
    if (value is! Map) return false;
    final data = Map<String, dynamic>.from(value);
    final title = data['title'] as String?;
    final text = data['text'] as String?;
    final url = data['url'] as String?;
    final body = <String>[
      if (text != null && text.trim().isNotEmpty) text.trim(),
      if (url != null && url.trim().isNotEmpty) url.trim(),
    ].join('\n');
    if (body.isEmpty) return false;
    await SharePlus.instance.share(
      ShareParams(text: body, title: title, subject: title),
    );
    return true;
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
    if (value is! Map) return false;
    final data = Map<String, dynamic>.from(value);
    final encoded = data['data'] as String?;
    if (encoded == null || encoded.isEmpty) return false;
    if (encoded.length > 70 * 1024 * 1024) {
      _showMessage('This blob is too large for the native bridge.');
      return false;
    }
    if (!await _permissions.ensureDownloadPermission()) return false;
    final fileName = DownloadName.sanitize(data['fileName'] as String?);
    final uri = await _bridge.saveBase64Download(
      fileName: fileName,
      mimeType: (data['mimeType'] as String?) ?? 'application/octet-stream',
      base64Data: encoded,
    );
    _showMessage(
      uri == null ? 'The file could not be saved.' : '$fileName was saved.',
      actionLabel: uri == null ? null : 'Downloads',
      onAction: uri == null ? null : _bridge.openDownloads,
    );
    return uri != null;
  }

  Future<Object?> _handleOfflinePackStatus(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! Map) return false;
    final data = Map<String, dynamic>.from(value);
    final status = (data['status'] as String? ?? 'idle').toLowerCase();
    final progress = data['progress'] as int? ?? 0;
    final previous = _offlinePackStatus;
    _offlinePackStatus = status;
    await _bridge.updateWidget(
      status: status == 'ready' ? 'OFFLINE READY' : status.toUpperCase(),
      detail: status == 'ready'
          ? 'Kurdistan Atlas is available offline'
          : 'Offline map $progress%',
    );
    if (status == 'ready' && previous != 'ready') {
      await _bridge.showNotification(
        title: 'NAV KURD',
        body: 'The Kurdistan offline map is ready.',
      );
    }
    return true;
  }

  Future<Object?> _handleLocationSnapshot(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! Map) return false;
    final data = Map<String, dynamic>.from(value);
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final accuracy = data['accuracy'];
    if (latitude is! num || longitude is! num) return false;
    final lat = latitude.toDouble();
    final lon = longitude.toDouble();
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      return false;
    }
    await _bridge.updateWidgetLocation(
      latitude: lat,
      longitude: lon,
      accuracy: accuracy is num && accuracy.isFinite
          ? accuracy.toDouble().clamp(0, 100000).toDouble()
          : 0,
    );
    return true;
  }

  Future<Object?> _handleNativeDiagnostic(List<dynamic> arguments) async {
    if (!await _isCurrentOriginTrusted() || arguments.isEmpty) return false;
    final value = arguments.first;
    if (value is! Map) return false;
    final data = Map<String, dynamic>.from(value);
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
    final current = await _controller?.getUrl();
    return AppConfig.isTrustedOrigin(
      Uri.tryParse(current?.toString() ?? ''),
    );
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
    required this.onRetry,
    required this.onSettings,
    super.key,
  });

  final bool isOnline;
  final VoidCallback onRetry;
  final Future<void> Function() onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF090D19),
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
                  const Text(
                    'دووبارە هەوڵ بدە، یان Settings بکەرەوە. پەکی خەریتەی offline دوای یەکەم دابەزاندن بەردەست دەبێت.',
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
  const publishPosition = position => {
    const coords = position?.coords;
    if (!coords) return;
    call('nativeLocationSnapshot', {
      latitude: Number(coords.latitude),
      longitude: Number(coords.longitude),
      accuracy: Number(coords.accuracy || 0)
    });
  };

  const geolocation = navigator.geolocation;
  if (geolocation) {
    try {
      const getCurrentPosition = geolocation.getCurrentPosition.bind(geolocation);
      Object.defineProperty(geolocation, 'getCurrentPosition', {
        configurable: true,
        value: (success, failure, options) => getCurrentPosition(position => {
          publishPosition(position);
          if (typeof success === 'function') success(position);
        }, failure, options)
      });
    } catch (_) { /* Keep the platform implementation if it is read-only. */ }
    try {
      const watchPosition = geolocation.watchPosition.bind(geolocation);
      Object.defineProperty(geolocation, 'watchPosition', {
        configurable: true,
        value: (success, failure, options) => watchPosition(position => {
          publishPosition(position);
          if (typeof success === 'function') success(position);
        }, failure, options)
      });
    } catch (_) { /* Keep the platform implementation if it is read-only. */ }
  }

  try {
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: data => call('nativeShare', data || {})
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

  navigator.storage?.persist?.().catch(() => false);

  const call = (name, payload) => {
    if (!window.flutter_inappwebview?.callHandler) return Promise.resolve(false);
    return window.flutter_inappwebview.callHandler(name, payload);
  };

  call('nativeRuntimeInfo', {}).then(info => {
    if (!info || typeof info !== 'object') return;
    window.__NAV_KURD_NATIVE_HARDWARE__ = Object.freeze(info);
    window.dispatchEvent(new CustomEvent('nav-kurd:native-hardware', { detail: info }));
  }).catch(() => false);

  const publish = () => {
    const root = document.querySelector('#offlineMapPack');
    const track = document.querySelector('#offlinePackProgress')?.parentElement;
    if (!root || !track) return;
    const status = root.dataset.status || 'idle';
    const progress = Number(track.getAttribute('aria-valuenow') || 0);
    call('offlinePackStatus', {
      status,
      progress: Number.isFinite(progress) ? Math.round(progress) : 0
    });
  };

  const installOfflineObserver = () => {
    const root = document.querySelector('#offlineMapPack');
    const track = document.querySelector('#offlinePackProgress')?.parentElement;
    if (!root || !track) return setTimeout(installOfflineObserver, 700);
    const observer = new MutationObserver(publish);
    observer.observe(root, {
      attributes: true,
      attributeFilter: ['data-status', 'data-progress-phase']
    });
    observer.observe(track, {
      attributes: true,
      attributeFilter: ['aria-valuenow']
    });
    publish();
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
  const reportObserver = new MutationObserver(() => {
    if (!applyingNativeReport) scheduleMerge();
  });
  reportObserver.observe(document.documentElement, {
    childList: true,
    subtree: true
  });
  document.addEventListener('click', scheduleMerge, true);
  installOfflineObserver();
})();
''';
