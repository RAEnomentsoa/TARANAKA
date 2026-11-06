import 'package:flutter/material.dart';

import 'pages/cycle_page.dart';
import 'pages/home_page.dart';

abstract final class AppRoutes {
  static const String home = '/';
  static const String cycle = '/cycle';

  static final Map<String, WidgetBuilder> routes = {
    home: (context) => const HomePage(),
    cycle: (context) => const CyclePage(),
  };
}
