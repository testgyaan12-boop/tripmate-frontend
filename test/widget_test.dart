import 'package:flutter_test/flutter_test.dart';
import 'package:tripmate_app/app.dart';

void main() {
  testWidgets('Splash shows brand and navigates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TripMateApp());
    await tester.pumpAndSettle();

    expect(find.text('TripMate'), findsOneWidget);
    expect(find.text('Plan Trips Together'), findsOneWidget);
    expect(
      find.text(
        'Create routes, invite friends, vote places and explore together',
      ),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('Get Started opens registration', (WidgetTester tester) async {
    await tester.pumpWidget(const TripMateApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
  });
}
