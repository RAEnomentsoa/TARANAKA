import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter ships no Material/Cupertino strings for Malagasy ("mg"). For the
/// few framework texts (date picker, back button tooltip…), French is used.
/// Every text of the app itself comes from lib/l10n/app_mg.arb.
const Locale _fallback = Locale('fr');

bool _isMalagasy(Locale locale) => locale.languageCode == 'mg';

class MgMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const MgMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isMalagasy(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(MgMaterialLocalizationsDelegate old) => false;
}

class MgCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const MgCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isMalagasy(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(MgCupertinoLocalizationsDelegate old) => false;
}

class MgWidgetsLocalizationsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const MgWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isMalagasy(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(MgWidgetsLocalizationsDelegate old) => false;
}

/// The delegates to give MaterialApp, Malagasy fallbacks first.
const List<LocalizationsDelegate<Object>> frameworkDelegates = [
  MgMaterialLocalizationsDelegate(),
  MgCupertinoLocalizationsDelegate(),
  MgWidgetsLocalizationsDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
