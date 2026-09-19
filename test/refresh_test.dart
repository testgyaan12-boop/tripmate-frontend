import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripmate_app/core/data/refresh.dart';

void main() {
  test('tab requests and version start empty, then update', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(tabRefreshRequestProvider), isNull);
    expect(c.read(dataVersionProvider), 0);
    c.read(tabRefreshRequestProvider.notifier).state =
        TabRefresh(2, 123);
    expect(c.read(tabRefreshRequestProvider)!.tab, 2);
    c.read(dataVersionProvider.notifier).state++;
    expect(c.read(dataVersionProvider), 1);
  });
}
