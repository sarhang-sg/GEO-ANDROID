import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/local/bundled_presentation.dart';

class WeatherCityPicker extends StatefulWidget {
  const WeatherCityPicker({super.key, required this.language, required this.onSelect, required this.onGps, required this.onBack});
  final String language;
  final ValueChanged<Map<String,dynamic>> onSelect;
  final VoidCallback onGps, onBack;
  @override
  State<WeatherCityPicker> createState() => _WeatherCityPickerState();
}

class _WeatherCityPickerState extends State<WeatherCityPicker> {
  late Future<BundledPresentation> presentation = BundledPresentation.open(AppConfig.appVersion);
  Uri get uri => AppConfig.appUri.resolve('/weather-cities.html').replace(queryParameters:{'lang':widget.language,'native':'1'});
  Future<bool> trusted(InAppWebViewController c) async {
    final current = Uri.tryParse((await c.getUrl())?.toString() ?? '');
    return mounted && AppConfig.isTrustedOrigin(current) && current?.path == uri.path;
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<BundledPresentation>(
    future:presentation, builder:(context,snapshot) {
      if (snapshot.hasError) return Center(child:IconButton(icon:const Icon(Icons.refresh),onPressed:()=>setState(()=>presentation=BundledPresentation.open(AppConfig.appVersion))));
      final bundle=snapshot.data;
      if (bundle==null) return const SizedBox.expand();
      return InAppWebView(
        initialUserScripts: UnmodifiableListView([UserScript(
          source:'window.__NAV_KURD_PUBLIC_CONFIG__ = {};',
          injectionTime:UserScriptInjectionTime.AT_DOCUMENT_START,forMainFrameOnly:true)]),
        initialUrlRequest: URLRequest(url:WebUri(uri.toString())),
        initialSettings:InAppWebViewSettings(javaScriptEnabled:true,domStorageEnabled:true,
          allowFileAccess:false,allowContentAccess:false,useShouldInterceptRequest:true,
          useShouldOverrideUrlLoading:true,hardwareAcceleration:true,algorithmicDarkeningAllowed:false,
          mixedContentMode:MixedContentMode.MIXED_CONTENT_NEVER_ALLOW),
        shouldOverrideUrlLoading:(_,action) async =>
          action.request.url?.path==uri.path && AppConfig.isTrustedOrigin(action.request.url) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL,
        shouldInterceptRequest:(_,request) async {
          final url=request.url;
          if (!AppConfig.isTrustedOrigin(url)) return null;
          return bundle.response(url.path,request.method ?? 'GET');
        },
        onWebViewCreated:(c) {
          c.addJavaScriptHandler(handlerName:'weatherLocalities',callback:(_) async =>
            await trusted(c) ? jsonDecode(await rootBundle.loadString('assets/weather/cities.json')) : []);
          c.addJavaScriptHandler(handlerName:'weatherSelect',callback:(args) async {
            if (!await trusted(c) || args.length!=1 || args.first is! Map) return;
            final city=Map<String,dynamic>.from(args.first as Map);
            if(city['name'] is String && city['lat'] is num && city['lon'] is num) widget.onSelect(city);
          });
          c.addJavaScriptHandler(handlerName:'weatherBack',callback:(_) async { if(await trusted(c)) widget.onBack(); });
          c.addJavaScriptHandler(handlerName:'weatherGps',callback:(_) async { if(await trusted(c)) widget.onGps(); });
        },
      );
    });
}
