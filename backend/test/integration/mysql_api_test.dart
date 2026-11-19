import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:mitt_backend/src/http/api.dart';
import 'package:mitt_backend/src/infrastructure/config.dart';
import 'package:mitt_backend/src/infrastructure/database.dart';
import 'package:shelf/shelf_io.dart';
import 'package:test/test.dart';

void main() {
  final configured =
      File('.env.test').existsSync() ||
      Platform.environment['DB_NAME'] == 'mitt_test';
  group('MySQL API integration', skip: configured ? false : 'Configure the isolated mitt_test schema.', () {
    late Database db;
    late Api api;
    late HttpServer server;
    late Directory media;
    late http.Client client;
    late String origin;
    late String admin;
    late String seller;
    late String buyer;
    late String outsider;
    late int store;
    late int first;
    late int second;
    late int buyerId;
    final random = Random.secure();
    final phonePrefix =
        '08${random.nextInt(999999).toString().padLeft(6, '0')}';
    const initialPassword = 'initial-demo-password';
    const license = 'JVBERi0xLjQKJSVFT0Y=';
    var checkoutCount = 0;

    Future<http.Response> call(
      String method,
      String path, {
      String? token,
      Row? payload,
      String? key,
      String? cookie,
      String? requestOrigin,
    }) async {
      final request = http.Request(method, Uri.parse('$origin$path'))
        ..headers['accept'] = 'application/json';
      if (token != null) request.headers['authorization'] = 'Bearer $token';
      if (key != null) request.headers['idempotency-key'] = key;
      if (cookie != null) request.headers['cookie'] = cookie;
      if (requestOrigin != null) request.headers['origin'] = requestOrigin;
      if (payload != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(payload);
      }
      return http.Response.fromStream(await client.send(request));
    }

    dynamic body(http.Response response, int status) {
      expect(response.statusCode, status, reason: response.body);
      return jsonDecode(response.body);
    }

    Future<(int, String)> register(
      String name,
      String phone,
      String role,
    ) async {
      final user = body(
        await call(
          'POST',
          '/auth/register',
          payload: {
            'name': name,
            'phone': phone,
            'role': role,
            'password': initialPassword,
            'confirmation': initialPassword,
          },
        ),
        201,
      ) as Row;
      final session = body(
        await call(
          'POST',
          '/auth/login',
          payload: {'phone': phone, 'password': initialPassword},
        ),
        200,
      ) as Row;
      return (user['id'] as int, session['token'] as String);
    }

    Future<int> quantity(int product) async =>
        (await db.one('SELECT quantity FROM inventory WHERE product_id=:id', {
              'id': product,
            }))!['quantity']
            as int;
    Future<int> deductions(int order) async =>
        (await db.one(
              'SELECT COUNT(*) AS amount FROM stock_movements WHERE order_id=:id',
              {'id': order},
            ))!['amount']
            as int;
    Future<String> status(int order) async =>
        (await db.one('SELECT status FROM orders WHERE id=:id', {
              'id': order,
            }))!['status']
            as String;
    String productPath(int id) => '/seller/stores/$store/products/$id';

    Future<void> stock(int product, int units, {String action = 'add'}) async =>
        body(
          await call(
            'POST',
            '${productPath(product)}/stock',
            token: seller,
            payload: {'action': action, 'quantity': units},
          ),
          200,
        );

    Row checkoutPayload(Map<int, int> lines) => {
      'store_id': store,
      'items': [
        for (final entry in lines.entries)
          {'product_id': entry.key, 'quantity': entry.value},
      ],
    };
    Future<int> place(
      Map<int, int> lines, {
      String? token,
      String? key,
    }) async =>
        body(
              await call(
                'POST',
                '/orders',
                token: token ?? buyer,
                payload: checkoutPayload(lines),
                key: key ?? 'checkout-${phonePrefix}-${checkoutCount++}',
              ),
              201,
            )['id']
            as int;

    Future<int> addProduct(String name, int price) async =>
        body(
              await call(
                'POST',
                '/seller/stores/$store/products',
                token: seller,
                payload: {
                  'name': name,
                  'description': 'For pets',
                  'price_minor': price,
                },
              ),
              201,
            )['id']
            as int;

    setUpAll(() async {
      final config = Config.load('.env.test');
      if (config.get('DB_NAME') != 'mitt_test')
        throw StateError('Integration tests require mitt_test.');
      db = Database(config);
      await db.migrate(Directory('migrations/mysql'));
      media = await Directory.systemTemp.createTemp('mitt-integration-');
      api = Api(db, media, secureCookie: false, passwordCost: 4);
      server = await serve(api.handler, InternetAddress.loopbackIPv4, 0);
      origin = 'http://127.0.0.1:${server.port}';
      client = http.Client();
      await api.accounts.createAdmin({
        'phone': '${phonePrefix}1',
        'name': 'MITT test admin',
        'password': initialPassword,
      });
      admin =
          body(
                await call(
                  'POST',
                  '/auth/login',
                  payload: {
                    'phone': '${phonePrefix}1',
                    'password': initialPassword,
                  },
                ),
                200,
              )['token']
              as String;
      (_, seller) = await register(
        'Test seller ${phonePrefix}',
        '${phonePrefix}2',
        'store_owner',
      );
      (buyerId, buyer) = await register(
        'Test buyer ${phonePrefix}',
        '${phonePrefix}3',
        'pet_owner',
      );
      (_, outsider) = await register(
        'Test outsider ${phonePrefix}',
        '${phonePrefix}4',
        'pet_owner',
      );
      final file =
          body(
                await call(
                  'POST',
                  '/files',
                  token: seller,
                  payload: {
                    'purpose': 'license',
                    'filename': 'license.pdf',
                    'data': license,
                  },
                ),
                201,
              )['id']
              as int;
      store =
          body(
                await call(
                  'POST',
                  '/seller/stores',
                  token: seller,
                  payload: {
                    'name': 'MITT Test Shop ${phonePrefix}',
                    'license_id': file,
                  },
                ),
                201,
              )['id']
              as int;
      final applications = body(
        await call('GET', '/admin/store-applications', token: admin),
        200,
      ) as List;
      final application = applications.firstWhere(
        (entry) => entry['store_id'] == store,
      );
      expect(application['status'], 'pending');
      expect(
        (body(await call('GET', '/stores'), 200) as List).any(
          (item) => item['id'] == store,
        ),
        isFalse,
      );
      body(
        await call(
          'POST',
          '/seller/stores/$store/products',
          token: seller,
          payload: {
            'name': 'Pending',
            'description': 'For pets',
            'price_minor': 100,
          },
        ),
        403,
      );
      expect(
        await db.one('SELECT id FROM products WHERE store_id=:store', {
          'store': store,
        }),
        isNull,
      );
      expect(
        (await call('GET', '/files/$file', token: outsider)).statusCode,
        404,
      );
      expect(
        (await call('GET', '/files/$file', token: admin)).bodyBytes,
        base64Decode(license),
      );
      body(
        await call(
          'POST',
          "/admin/store-applications/${application['id']}",
          token: admin,
          payload: {'decision': 'approved'},
        ),
        200,
      );
      final reviewed = await db.one(
        'SELECT decision,reviewed_by,reviewed_at FROM store_applications WHERE store_id=:id',
        {'id': store},
      );
      expect(reviewed?['decision'], 'approved');
      expect(reviewed?['reviewed_by'], isNotNull);
      expect(reviewed?['reviewed_at'], isNotNull);
      expect(
        (body(await call('GET', '/stores'), 200) as List).any(
          (item) => item['id'] == store,
        ),
        isTrue,
      );
      first = await addProduct('Kibble ${phonePrefix}', 34900);
      second = await addProduct('Shampoo ${phonePrefix}', 18900);
      expect(await quantity(first), 0);
      expect(await quantity(second), 0);
    });

    tearDownAll(() async {
      if (!configured) return;
      client.close();
      await server.close(force: true);
      await db.pool.close();
      await media.delete(recursive: true);
    });

    test('multi-line checkout, rollback on shortage, idempotent confirmation and delivery ownership', () async {
      await stock(first, 14);
      await stock(second, 6);
      body(
        await call(
          'POST',
          '${productPath(first)}/stock',
          token: seller,
          payload: {'action': 'add', 'quantity': 0},
        ),
        422,
      );
      expect(await quantity(first), 14);

      final checkoutKey = 'stable-checkout-${phonePrefix}';
      final order = await place({first: 2, second: 1}, key: checkoutKey);
      expect(await place({second: 1, first: 2}, key: checkoutKey), order);
      body(
        await call(
          'POST',
          '/orders',
          token: buyer,
          key: checkoutKey,
          payload: checkoutPayload({first: 1}),
        ),
        409,
      );
      expect(await status(order), 'placed');
      expect(await quantity(first), 14);
      expect(await quantity(second), 6);
      expect(await deductions(order), 0);
      body(
        await call(
          'POST',
          '/orders/$order/dispatch',
          token: seller,
          payload: {},
        ),
        409,
      );
      await stock(second, 0, action: 'set');
      body(
        await call(
          'POST',
          '/orders/$order/confirm',
          token: seller,
          payload: {},
        ),
        409,
      );
      expect(await status(order), 'placed');
      expect(await quantity(first), 14);
      expect(await deductions(order), 0);

      await stock(second, 6);
      final confirmed = body(
        await call(
          'POST',
          '/orders/$order/confirm',
          token: seller,
          payload: {},
        ),
        200,
      );
      expect(confirmed['status'], 'confirmed');
      body(
        await call(
          'POST',
          '/orders/$order/confirm',
          token: seller,
          payload: {},
        ),
        200,
      );
      expect(await quantity(first), 12);
      expect(await quantity(second), 5);
      expect(await deductions(order), 2);

      body(
        await call(
          'POST',
          '/orders/$order/dispatch',
          token: seller,
          payload: {},
        ),
        200,
      );
      body(
        await call(
          'POST',
          '/orders/$order/receive',
          token: outsider,
          payload: {},
        ),
        403,
      );
      expect(await status(order), 'on_delivery');
      body(
        await call('POST', '/orders/$order/receive', token: buyer, payload: {}),
        200,
      );
      expect(await status(order), 'delivered');
      expect(await deductions(order), 2);
    });

    test(
      'concurrent confirmations for the last unit allow exactly one deduction',
      () async {
        final item = await addProduct('Last unit ${phonePrefix}', 2000);
        await stock(item, 1);
        final one = await place({item: 1});
        final two = await place({item: 1}, token: outsider);
        final results = await Future.wait([
          call('POST', '/orders/$one/confirm', token: seller, payload: {}),
          call('POST', '/orders/$two/confirm', token: seller, payload: {}),
        ]);
        expect(
          results.map((response) => response.statusCode).toList()..sort(),
          [200, 409],
        );
        expect(await quantity(item), 0);
        expect([await status(one), await status(two)]..sort(), [
          'confirmed',
          'placed',
        ]);
        expect([await deductions(one), await deductions(two)]..sort(), [0, 1]);
      },
    );

    test('admin category and seller product writes enforce roles and preserve history', () async {
      final filtered = body(
        await call(
          'GET',
          '/admin/users?search=$phonePrefix&role=store_owner',
          token: admin,
        ),
        200,
      ) as List;
      expect(filtered.single['role'], 'store_owner');
      body(await call('GET', '/admin/users', token: seller), 403);
      body(
        await call(
          'POST',
          '/admin/categories',
          token: seller,
          payload: {'name': 'Blocked category'},
        ),
        403,
      );
      expect(
        await db.one("SELECT id FROM categories WHERE name='Blocked category'"),
        isNull,
      );

      final category =
          body(
                await call(
                  'POST',
                  '/admin/categories',
                  token: admin,
                  payload: {'name': 'Test category $phonePrefix'},
                ),
                201,
              )['id']
              as int;
      body(
        await call(
          'PUT',
          '/admin/categories/$category',
          token: admin,
          payload: {'name': 'Updated category $phonePrefix'},
        ),
        200,
      );
      final product = await addProduct('Catalog item $phonePrefix', 500);
      body(
        await call(
          'PUT',
          productPath(product),
          token: seller,
          payload: {
            'name': 'Edited product $phonePrefix',
            'description': 'Updated description',
            'price_minor': 900,
            'category_id': category,
          },
        ),
        200,
      );
      expect(
        (await db.one('SELECT price_minor FROM products WHERE id=:id', {
          'id': product,
        }))?['price_minor'],
        900,
      );
      await stock(product, 2);
      final order = await place({product: 1});
      body(await call('DELETE', productPath(product), token: seller), 409);
      expect(
        (await db.one('SELECT archived_at FROM products WHERE id=:id', {
          'id': product,
        }))?['archived_at'],
        isNull,
      );
      body(
        await call(
          'POST',
          '/orders/$order/confirm',
          token: seller,
          payload: {},
        ),
        200,
      );
      body(await call('DELETE', productPath(product), token: seller), 200);
      expect(
        (await db.one('SELECT archived_at FROM products WHERE id=:id', {
          'id': product,
        }))?['archived_at'],
        isNotNull,
      );
      expect(
        (await db.one(
          'SELECT unit_price_minor FROM order_items WHERE order_id=:id',
          {'id': order},
        ))?['unit_price_minor'],
        900,
      );
      body(
        await call('DELETE', '/admin/categories/$category', token: admin),
        200,
      );
      expect(
        await db.one('SELECT id FROM categories WHERE id=:id', {
          'id': category,
        }),
        isNull,
      );
    });

    test(
      'password preconditions and session invalidation, bans and web origin',
      () async {
        final phone = '${phonePrefix}3';
        final original = await db.one(
          'SELECT password_hash FROM users WHERE id=:id',
          {'id': buyerId},
        );
        body(
          await call(
            'POST',
            '/auth/password',
            payload: {
              'phone': phone,
              'old_password': initialPassword,
              'new_password': 'replacement-password',
              'confirmation': 'different-password',
            },
          ),
          422,
        );
        expect(
          await db.one('SELECT password_hash FROM users WHERE id=:id', {
            'id': buyerId,
          }),
          original,
        );
        body(
          await call(
            'POST',
            '/auth/password',
            payload: {
              'phone': phone,
              'old_password': 'wrong-password',
              'new_password': 'replacement-password',
              'confirmation': 'replacement-password',
            },
          ),
          401,
        );
        body(
          await call(
            'POST',
            '/auth/password',
            payload: {
              'phone': phone,
              'old_password': initialPassword,
              'new_password': 'replacement-password',
              'confirmation': 'replacement-password',
            },
          ),
          200,
        );
        body(await call('GET', '/auth/me', token: buyer), 401);
        body(
          await call(
            'POST',
            '/auth/login',
            payload: {'phone': phone, 'password': initialPassword},
          ),
          401,
        );
        final signedIn = body(
          await call(
            'POST',
            '/auth/login',
            payload: {'phone': phone, 'password': 'replacement-password'},
          ),
          200,
        );
        buyer = signedIn['token'] as String;

        body(
          await call(
            'POST',
            '/admin/users/$buyerId/ban',
            token: admin,
            payload: {'duration': 'week'},
          ),
          200,
        );
        final blocked = body(await call('GET', '/orders', token: buyer), 403);
        expect(blocked['code'], 'banned');
        await db.execute(
          '''
        UPDATE user_bans SET starts_at=UTC_TIMESTAMP(6)-INTERVAL 8 DAY,ends_at=UTC_TIMESTAMP(6)-INTERVAL 1 DAY
        WHERE user_id=:id
      ''',
          {'id': buyerId},
        );
        body(await call('GET', '/orders', token: buyer), 200);

        final webLogin = await call(
          'POST',
          '/auth/login',
          requestOrigin: origin,
          payload: {
            'client': 'web',
            'phone': phone,
            'password': 'replacement-password',
          },
        );
        expect(body(webLogin, 200).containsKey('token'), isFalse);
        final setCookie = webLogin.headers['set-cookie']!;
        expect(setCookie, contains('HttpOnly'));
        final cookie = setCookie.split(';').first;
        body(
          await call(
            'POST',
            '/auth/logout',
            cookie: cookie,
            requestOrigin: 'https://unrelated.invalid',
          ),
          403,
        );
        body(await call('GET', '/auth/me', cookie: cookie), 200);
        body(
          await call(
            'POST',
            '/auth/logout',
            cookie: cookie,
            requestOrigin: origin,
          ),
          200,
        );
        body(await call('GET', '/auth/me', cookie: cookie), 401);
      },
    );
  });
}
