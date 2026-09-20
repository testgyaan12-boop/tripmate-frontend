import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/dark_mode_provider.dart';
import 'features/auth/presentation/auth_provider.dart' show dioClientProvider;

class TripMateApp extends StatelessWidget {
  const TripMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: _App());
  }
}

class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final dark = ref.watch(darkModeProvider).dark;
    ref.read(dioClientProvider).onAuthLost = () {
      if (router.state.uri.toString() != '/login') {
        router.go('/login');
      }
    };
    return MaterialApp.router(
      title: 'TripMate',
      theme: buildAppTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}
