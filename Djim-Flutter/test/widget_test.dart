import 'package:flutter_test/flutter_test.dart';
import 'package:djim_flutter/main.dart';

void main() {
  testWidgets('DjimPharmaApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DjimPharmaApp());
    expect(find.text('Pharmacie connectée • Togo 🇹🇬'), findsOneWidget);
  });
}
