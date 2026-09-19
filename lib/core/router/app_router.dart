import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/trip_nav_bar.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/trips/create_trip_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/places/places_list_screen.dart';
import '../../features/places/place_detail_screen.dart';
import '../../features/places/ai_suggest_screen.dart';
import '../../features/members/members_screen.dart';
import '../../features/expense/expenses_screen.dart';
import '../../features/expense/add_expense_screen.dart';
import '../../features/expense/expense_detail_screen.dart';
import '../../features/expense/settlement_screen.dart';
import '../../features/itinerary/itinerary_screen.dart';
import '../../features/itinerary/ai_proposal_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/invite/join_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
import '../../features/settings/settings_screen.dart';

final appRouterProvider = Provider((_) => buildRouter());

/// Maps a location to the shell tab index for the trip bottom nav.
/// Returns -1 for the immersive map (no tab highlighted / no bar).
/// 0 Home, 1 Places, 2 Expenses, 3 Itinerary, 4 People.
int _tabIndexFor(String location) {
  if (location.startsWith('/home')) return 0;
  if (location.endsWith('/map')) return -1;
  if (location.contains('/places')) return 1;
  if (location.contains('/expenses')) return 2;
  if (location.endsWith('/itinerary')) return 3;
  if (location.endsWith('/members')) return 4;
  return 0;
}

/// Invite code from either path-style (/join?code=) or hash-style
/// (/#/join?code=) share links.
String? _joinCode(GoRouterState s) {
  final q = s.uri.queryParameters['code'];
  if (q != null && q.isNotEmpty) return q;
  final frag = s.uri.fragment;
  if (frag.contains('?')) {
    final c = Uri.splitQueryString(frag.split('?').last)['code'];
    if (c != null && c.isNotEmpty) return c;
  }
  return null;
}

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      // Rescue invite codes from the raw browser URL. In hash URL strategy
      // the router ignores the path part, so a cold-opened share link like
      // /join?code=X would otherwise boot into splash and drop the code.
      // Guarded to exact '/' (cold boot) only: in-app navigations keep a
      // stale ?code= in the address bar, and redirecting there would loop.
      redirect: (context, state) {
        if (state.matchedLocation == '/') {
          final code = Uri.base.queryParameters['code'];
          if (code != null && code.isNotEmpty) {
            return '/join?code=$code';
          }
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        // Dashboard data lives in app-wide Riverpod providers, so coming
        // back Home never refetches.
        GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
        GoRoute(
            path: '/trips/new',
            builder: (_, _) => const CreateTripScreen()),
        // Trip tabs share one IndexedStack shell nested under the
        // parameterized parent (go_router forbids parameterized branch
        // defaults). Switching tabs preserves each screen's state and
        // loaded data — no API calls on revisit.
        GoRoute(
          path: '/trips/:tripId',
          redirect: (context, state) =>
              state.uri.pathSegments.length == 2
                  ? '${state.uri}/map'
                  : null,
          builder: (_, s) =>
              MapScreen(tripId: s.pathParameters['tripId']!),
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) => _TripShell(
                shell: shell,
                location: state.uri.toString(),
                tripId: state.pathParameters['tripId']!,
              ),
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                        path: 'map',
                        builder: (_, s) => MapScreen(
                            tripId: s.pathParameters['tripId']!)),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: 'places',
                      builder: (_, s) => PlacesListScreen(
                          tripId: s.pathParameters['tripId']!),
                      routes: [
                        GoRoute(
                          path: ':placeId',
                          builder: (_, s) => PlaceDetailScreen(
                              tripId:
                                  s.pathParameters['tripId']!,
                              placeId:
                                  s.pathParameters['placeId']!),
                        ),
                      ],
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: 'expenses',
                      builder: (_, s) => ExpensesScreen(
                          initialTripId:
                              s.pathParameters['tripId']!),
                    ),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                        path: 'itinerary',
                        builder: (_, s) => ItineraryScreen(
                            tripId:
                                s.pathParameters['tripId']!)),
                  ],
                ),
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                        path: 'members',
                        builder: (_, s) => MembersScreen(
                            tripId:
                                s.pathParameters['tripId']!)),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
            path: '/trips/:tripId/chat',
            builder: (_, s) =>
                ChatScreen(tripId: s.pathParameters['tripId']!)),
        GoRoute(
            path: '/trips/:tripId/expenses/:expenseId',
            builder: (_, s) => ExpenseDetailScreen(
                tripId: s.pathParameters['tripId']!,
                expenseId: s.pathParameters['expenseId']!)),
        GoRoute(
          path: '/expenses/new',
          builder: (_, s) => AddExpenseScreen(
              tripId: s.uri.queryParameters['tripId']),
        ),
        GoRoute(
          path: '/expenses/settle',
          builder: (_, s) => SettlementScreen(
              tripId: s.uri.queryParameters['tripId']),
        ),
        GoRoute(
          path: '/join',
          builder: (_, s) => JoinScreen(code: _joinCode(s)),
        ),
        GoRoute(
            path: '/trips/:tripId/itinerary/ai/:proposalId',
            builder: (_, s) => AiProposalScreen(
                tripId: s.pathParameters['tripId']!,
                proposalId: s.pathParameters['proposalId']!)),
        GoRoute(
            path: '/trips/:tripId/places/ai/:suggestionId',
            builder: (_, s) => AiSuggestScreen(
                tripId: s.pathParameters['tripId']!,
                suggestionId: s.pathParameters['suggestionId']!,
                dayNo: int.tryParse(
                    s.uri.queryParameters['day'] ?? ''))),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationsScreen()),
        GoRoute(
            path: '/profile',
            builder: (_, _) => const ProfileScreen()),
        GoRoute(
            path: '/profile/edit',
            builder: (_, _) => const EditProfileScreen()),
        GoRoute(
            path: '/settings/notifications',
            builder: (_, _) => const NotificationSettingsScreen()),
      ],
    );

/// Trip bottom-nav frame: Home | Places | Expenses | Itinerary | People.
/// The IndexedStack above keeps every tab's state, so tab switches
/// never trigger API reloads.
class _TripShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  final String location;
  final String tripId;
  const _TripShell({
    required this.shell,
    required this.location,
    required this.tripId,
  });

  @override
  Widget build(BuildContext context) {
    final tab = _tabIndexFor(location);
    return Scaffold(
      body: shell,
      // Map stays immersive full-screen without the bar.
      bottomNavigationBar: tab < 0
          ? null
          : TripNavBar(
              tripId: tripId,
              currentIndex: tab,
            ),
    );
  }
}
