import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A bottom-nav tab tap (including re-taps of the active tab).
/// Every tap refetches that tab's data.
class TabRefresh {
  final int tab;
  final int atMs;
  TabRefresh(this.tab, this.atMs);
}

final tabRefreshRequestProvider =
    StateProvider<TabRefresh?>((_) => null);

/// Bumped after every successful local write (vote, place, comment,
/// RSVP, itinerary, chat, trip changes) so visible screens refresh.
final dataVersionProvider = StateProvider<int>((_) => 0);

void bumpData(WidgetRef ref) =>
    ref.read(dataVersionProvider.notifier).update((v) => v + 1);
