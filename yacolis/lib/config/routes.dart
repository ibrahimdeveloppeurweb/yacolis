import 'package:flutter/material.dart';
import 'package:yacolis/presentation/screens/delivery/delivery_screen.dart';
import '../presentation/screens/home/home_screen.dart';

class AppRoutes {
  static const String home = '/home';
  static const String delivery = '/';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        );
      case delivery:
        return MaterialPageRoute(
          builder: (_) => const DeliveryScreen(),
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
