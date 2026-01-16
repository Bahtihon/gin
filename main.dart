// lib/main.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

import 'pages/patient_list.dart';
import 'desktop/desktop_home.dart';
import 'server.dart';

void main() {
  // Устанавливаем язык по умолчанию — русский
  Intl.defaultLocale = 'ru_RU';

  // Запускаем встроенный сервер
  startEmbeddedServer();

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Регистратор',
      locale: const Locale('ru', 'RU'),
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _defaultHome(),
    ),
  );
}

Widget _defaultHome() {
  // если десктоп
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return const DesktopHome();
  }
  // иначе — мобильный вариант
  return PatientList(); // как раньше
}
