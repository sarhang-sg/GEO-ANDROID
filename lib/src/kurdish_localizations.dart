import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// The SDK does not supply Material or Cupertino delegates for Sorani.
const navKurdLocales = <Locale>[
  Locale('ku'),
  Locale('ckb'),
  Locale('en'),
  Locale('ar'),
];
const navKurdDelegates = <LocalizationsDelegate<dynamic>>[
  _SoraniDelegate<MaterialLocalizations>(_SoraniMaterial()),
  _SoraniDelegate<CupertinoLocalizations>(_SoraniCupertino()),
  _SoraniDelegate<WidgetsLocalizations>(_SoraniWidgets()),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

class _SoraniDelegate<T> extends LocalizationsDelegate<T> {
  const _SoraniDelegate(this.value);
  final T value;
  @override
  bool isSupported(Locale locale) =>
      const {'ku', 'ckb'}.contains(locale.languageCode);
  @override
  Future<T> load(Locale locale) => SynchronousFuture<T>(value);
  @override
  bool shouldReload(_SoraniDelegate<T> old) => false;
}

class _SoraniWidgets extends DefaultWidgetsLocalizations {
  const _SoraniWidgets();
  @override
  TextDirection get textDirection => TextDirection.rtl;
}

class _SoraniMaterial extends DefaultMaterialLocalizations {
  const _SoraniMaterial();
  @override
  String get backButtonTooltip => 'گەڕانەوە';
  @override
  String get closeButtonTooltip => 'داخستن';
  @override
  String get closeButtonLabel => 'داخستن';
  @override
  String get cancelButtonLabel => 'هەڵوەشاندنەوە';
  @override
  String get okButtonLabel => 'باشە';
  @override
  String get modalBarrierDismissLabel => 'داخستن';
  @override
  String get moreButtonTooltip => 'زیاتر';
  @override
  String get selectAllButtonLabel => 'هەمووی هەڵبژێرە';
  @override
  String get copyButtonLabel => 'کۆپی';
  @override
  String get cutButtonLabel => 'بڕین';
  @override
  String get pasteButtonLabel => 'لکاندن';
}

class _SoraniCupertino extends DefaultCupertinoLocalizations {
  const _SoraniCupertino();
  @override
  String get modalBarrierDismissLabel => 'داخستن';
  @override
  String get alertDialogLabel => 'ئاگاداری';
}
