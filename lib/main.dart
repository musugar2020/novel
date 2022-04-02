import 'package:bot_toast/bot_toast.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:novel/common/langs/translation_service.dart';
import 'package:novel/global.dart';
import 'package:novel/pages/listen/listen_view.dart';
import 'package:novel/router/app_pages.dart';
import 'package:novel/router/router_observer.dart';

import 'pages/listen/listen_binding.dart';

void main() => Global.init().then((e) => runApp(MyApp()));

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'novel',
      home: ListenPage(),
      initialBinding: ListenBinding(),
      initialRoute: AppPages.INITIAL,
      getPages: AppPages.routes,
      unknownRoute: AppPages.unknownRoute,
      navigatorObservers: [
        RouterObserver(),
        FirebaseAnalyticsObserver(analytics: Global.analytics)
      ],
      builder: BotToastInit(),
      locale: TranslationService.locale,
      fallbackLocale: TranslationService.fallbackLocale,
    );
  }
}
