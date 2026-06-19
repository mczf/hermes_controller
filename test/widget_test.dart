import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_controller/main.dart';

void main() {
  testWidgets('App renders login page with title', (WidgetTester tester) async {
    await tester.pumpWidget(const HermesControllerApp());
    await tester.pumpAndSettle();

    expect(find.text('养码猿'), findsOneWidget);
    expect(find.text('连接'), findsOneWidget);
  });
}
