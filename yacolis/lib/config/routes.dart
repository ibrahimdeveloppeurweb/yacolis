import 'package:flutter/material.dart';
import '../presentation/screens/home/home_screen.dart';

class AppRoutes {
  static const String home = '/';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Route introuvable : ${settings.name}'),
            ),
          ),
        );
    }
  }
}
