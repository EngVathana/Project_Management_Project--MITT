import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mitt_project_management/app/mitt_app.dart';
import 'package:mitt_project_management/core/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Explore loads categories and public stores from the API', (
    tester,
  ) async {
    final requests = <String>[];
    final api = ApiClient(
      base: 'http://localhost/api/v1',
      client: MockClient((request) async {
        requests.add(request.url.path);
        final data = switch (request.url.path) {
          '/api/v1/categories' => '[{"id":1,"name":"Food"}]',
          '/api/v1/stores' =>
            '[{"id":2,"name":"Pet Pantry","status":"approved"}]',
          '/api/v1/stores/2/products' => '[{"id":10,"store_id":2,"name":"Kibble","description":"For cats","price_minor":14900,"stock":2}]',
          _ => '[]',
        };
        return http.Response(data, 200);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(MittApp(client: api));
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Pet Pantry'), findsOneWidget);
    expect(find.text('Kibble'), findsNothing);
    await tester.tap(find.text('Pet Pantry'));
    await tester.pumpAndSettle();
    expect(find.text('Kibble'), findsOneWidget);
    expect(requests, contains('/api/v1/stores/2/products'));
  });

  testWidgets(
    'Password form rejects a mismatched confirmation before sending a request',
    (tester) async {
      tester.view.physicalSize = const Size(560, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <String>[];
      final api = ApiClient(
        base: 'http://localhost/api/v1',
        client: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(MittApp(portal: true, client: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '0800000101');
      await tester.enterText(fields.at(1), 'current-password');
      await tester.enterText(fields.at(2), 'new-password');
      await tester.enterText(fields.at(3), 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(requests, isNot(contains('/api/v1/auth/password')));
    },
  );
}
