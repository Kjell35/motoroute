import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';
import 'package:motoroute_app/features/chat/chat_providers.dart';
import 'package:motoroute_app/features/chat/presentation/chat_hub_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedInAuthController extends AuthController {
  @override
  Future<void> restore() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signed-in state never shows the sign-in prompt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) {
            final controller = _SignedInAuthController();
            controller.state = const AuthState(
              user: AuthUser(id: 'u-1', email: 'rider@example.com'),
            );
            return controller;
          }),
          chatSessionTokenProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: ChatHubScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Zum Chatten anmelden'), findsNothing);
    expect(find.text('Deine Sitzung wird mit dem Chat verbunden.'), findsOneWidget);
  });
}
