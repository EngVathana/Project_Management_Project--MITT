import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mitt_project_management/core/api_client.dart';
import 'package:mitt_project_management/features/shopper/shopper_repository.dart';

Json product(int id, int store, {int stock = 2}) => {
  'id': id,
  'store_id': store,
  'stock': stock,
  'price_minor': 12900,
};

void main() {
  test(
    'cart allows multiple products from one store and respects quantity limits',
    () {
      final cart = Cart();
      addTearDown(cart.dispose);
      expect(cart.add(product(1, 1)), isNull);
      expect(cart.add(product(2, 1)), isNull);
      expect(cart.add(product(1, 1)), isNull);
      expect(cart.add(product(1, 1)), isNotNull);
      expect(cart.add(product(3, 2)), isNotNull);
      expect(cart.total, 38700);
      expect(cart.units, 3);
      cart.remove(1);
      expect(cart.quantity(1), 1);
    },
  );

  test(
    'failed checkout preserves the cart and retries reuse its key',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        base: 'http://localhost/api/v1',
        client: MockClient((request) async {
          requests.add(request);
          return requests.length == 1
              ? http.Response('{"message":"Temporary error"}', 503)
              : http.Response('{"id":1}', 201);
        }),
      );
      addTearDown(api.close);
      final cart = Cart();
      addTearDown(cart.dispose);
      cart.add(product(1, 1));
      final repository = ShopperRepository(api);
      await expectLater(cart.place(repository), throwsA(isA<ApiFailure>()));
      expect(cart.units, 1);
      await cart.place(repository);
      expect(cart.units, 0);
      expect(requests[0].headers['idempotency-key'], isNotEmpty);
      expect(
        requests[0].headers['idempotency-key'],
        requests[1].headers['idempotency-key'],
      );
    },
  );
}
