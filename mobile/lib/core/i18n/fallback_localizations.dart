import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Flutter ships no Material/Cupertino strings for Malagasy ("mg"). The
/// framework texts the app can show (back and close tooltips, dialog buttons,
/// text selection menu) are translated here; the date formats come from
/// French (numeric dd/MM/yyyy everywhere). Every text of the app itself comes
/// from lib/l10n/app_mg.arb. English and French are supported by Flutter.
const Locale _fallback = Locale('fr');

bool _isMalagasy(Locale locale) => locale.languageCode == 'mg';

class MaterialLocalizationMg extends MaterialLocalizationFr {
  const MaterialLocalizationMg({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  }) : super(localeName: 'fr');

  @override
  String get backButtonTooltip => 'Miverina';
  @override
  String get closeButtonTooltip => 'Hidio';
  @override
  String get closeButtonLabel => 'Hidio';
  @override
  String get cancelButtonLabel => 'Hanafoana';
  @override
  String get okButtonLabel => 'OK';
  @override
  String get continueButtonLabel => 'Tohizo';
  @override
  String get deleteButtonTooltip => 'Fafao';
  @override
  String get moreButtonTooltip => 'Hafa koa';
  @override
  String get showMenuTooltip => 'Asehoy ny menio';
  @override
  String get openAppDrawerTooltip => 'Sokafy ny menio';
  @override
  String get copyButtonLabel => 'Adikao';
  @override
  String get cutButtonLabel => 'Tapaho';
  @override
  String get pasteButtonLabel => 'Apetaho';
  @override
  String get selectAllButtonLabel => 'Fidio daholo';
  @override
  String get searchFieldLabel => 'Hikaroka';
  @override
  String get alertDialogLabel => 'Fampitandremana';
  @override
  String get dialogLabel => 'Varavarankely';
  @override
  String get bottomSheetLabel => 'Takelaka ambany';
  @override
  String get modalBarrierDismissLabel => 'Hidio';
  @override
  String get scrimLabel => 'Hidio';
  @override
  String get clearButtonTooltip => 'Fafao ny soratra';
  @override
  String get keyboardKeyBackspace => 'Fafao';
}

class MgMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const MgMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isMalagasy(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    // Loads the French date symbols, then builds the Malagasy texts on them.
    await GlobalMaterialLocalizations.delegate.load(_fallback);
    const l = 'fr';
    return MaterialLocalizationMg(
      fullYearFormat: intl.DateFormat.y(l),
      compactDateFormat: intl.DateFormat.yMd(l),
      shortDateFormat: intl.DateFormat.yMMMd(l),
      mediumDateFormat: intl.DateFormat.MMMEd(l),
      longDateFormat: intl.DateFormat.yMMMMEEEEd(l),
      yearMonthFormat: intl.DateFormat.yMMMM(l),
      shortMonthDayFormat: intl.DateFormat.MMMd(l),
      decimalFormat: intl.NumberFormat.decimalPattern(l),
      twoDigitZeroPaddedFormat: intl.NumberFormat('00', l),
    );
  }

  @override
  bool shouldReload(MgMaterialLocalizationsDelegate old) => false;
}

class MgCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const MgCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isMalagasy(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) => GlobalCupertinoLocalizations.delegate.load(_fallback);

  @override
  bool shouldReload(MgCupertinoLocalizationsDelegate old) => false;
}

class MgWidgetsLocalizationsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const MgWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _isMalagasy(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) => GlobalWidgetsLocalizations.delegate.load(_fallback);

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
