import 'package:flutter_test/flutter_test.dart';
import 'package:developer_app/main.dart';

void main() {
  testWidgets('shows the app name', (tester) async {
    await tester.pumpWidget(const DeveloperApp());
    expect(find.text('developer-app'), findsOneWidget);
  });
}
