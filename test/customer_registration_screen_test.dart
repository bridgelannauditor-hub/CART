import 'package:craft_of_love/screens/auth/customer_register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('public registration is Customer-only', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CustomerRegisterScreen()));

    expect(find.text('Create your account'), findsOneWidget);
    expect(
      find.textContaining('Every new account starts as a customer'),
      findsOneWidget,
    );
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    expect(find.text('GOOGLE'), findsOneWidget);
    expect(find.text('FACEBOOK'), findsOneWidget);
    expect(find.text('Register as Buyer'), findsNothing);
    expect(find.text('Register as Seller'), findsNothing);
    expect(find.textContaining('choose whether'), findsNothing);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
  });
}
