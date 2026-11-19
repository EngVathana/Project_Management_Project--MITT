import 'dart:convert';
import 'dart:io';

import 'package:mysql_client_plus/exception.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../infrastructure/database.dart';
import '../modules/accounts.dart';
import '../modules/catalog.dart';
import '../modules/contracts.dart';
import '../modules/media.dart';
import '../modules/orders.dart';

Response json(
  Object? data, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode(data),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    ...headers,
  },
);

Future<Row> readJson(Request request) async {
  if (request.headers['content-type']?.split(';').first.trim() !=
      'application/json') {
    throw const ApiError(415, 'unsupported_type', 'Send a JSON request.');
  }
  final maximum = request.url.path == 'files' ? 7100000 : 128000;
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    if (bytes.length + chunk.length > maximum)
      throw const ApiError(413, 'too_large', 'The request is too large.');
    bytes.addAll(chunk);
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) invalid('Provide a JSON object.');
  return decoded;
}

class Api {
  Api(
    this.db,
    Directory files, {
    required this.secureCookie,
    this.origin,
    int passwordCost = 12,
  }) : accounts = Accounts(db, cost: passwordCost),
       media = Media(db, files) {
    catalog = Catalog(db, media);
    orders = Orders(db, catalog);
  }
  final Database db;
  final Accounts accounts;
  final Media media;
  late final Catalog catalog;
  late final Orders orders;
  final bool secureCookie;
  final String? origin;

  String? cookieToken(Request request) => request.headers['cookie']
      ?.split(';')
      .map((value) => value.trim())
      .where((value) => value.startsWith('mitt_session='))
      .firstOrNull
      ?.substring('mitt_session='.length);

  String? token(Request request) {
    final authorization = request.headers['authorization'];
    if (authorization != null) {
      return authorization.startsWith('Bearer ')
          ? authorization.substring(7)
          : null;
    }
    return cookieToken(request);
  }

  Future<Actor> actor(Request request) => accounts.authenticate(token(request));

  void requireWebOrigin(Request request) {
    if (request.headers['origin'] != (origin ?? request.requestedUri.origin))
      forbidden();
  }

  String sessionCookie(String value, int maxAge) =>
      'mitt_session=$value; Path=/; HttpOnly; SameSite=Strict; Max-Age=$maxAge${secureCookie ? '; Secure' : ''}';

  int param(Request request, String field) => id(request.params[field]!);
  int? queryId(Request request, String field) {
    final value = request.url.queryParameters[field];
    return value == null ? null : id(value);
  }

  Handler get handler {
    final router = Router();

    router.get('/health', (Request request) async {
      await db.execute('SELECT 1');
      return json({'status': 'ok'});
    });

    router.post('/auth/register', (Request request) async {
      final user = await accounts.register(await readJson(request));
      return json(user.user, status: 201);
    });
    router.post('/auth/login', (Request request) async {
      final body = await readJson(request);
      final browser = body['client'] == 'web';
      if (browser) requireWebOrigin(request);
      final (user, session) = await accounts.login(body);
      return browser
          ? json(
              user.user,
              headers: {'set-cookie': sessionCookie(session, 604800)},
            )
          : json({...user.user, 'token': session});
    });
    router.get(
      '/auth/me',
      (Request request) async => json((await actor(request)).user),
    );
    router.post('/auth/logout', (Request request) async {
      await accounts.logout(token(request));
      return json({'ok': true}, headers: {'set-cookie': sessionCookie('', 0)});
    });
    router.post('/auth/password', (Request request) async {
      await accounts.changePassword(await readJson(request));
      return json({'ok': true}, headers: {'set-cookie': sessionCookie('', 0)});
    });

    router.get(
      '/categories',
      (Request request) async => json(await catalog.categories()),
    );
    router.get(
      '/stores',
      (Request request) async =>
          json(await catalog.stores(queryId(request, 'category'))),
    );
    router.get(
      '/stores/<store>/products',
      (Request request) async =>
          json(await catalog.products(param(request, 'store'))),
    );
    router.get('/files/<file>', (Request request) async {
      Actor? user;
      if (token(request) != null) {
        try {
          user = await actor(request);
        } on ApiError {
          // Public product photography remains available to signed-out visitors.
        }
      }
      final file = await media.read(param(request, 'file'), user);
      final content = file['file'] as File;
      return Response.ok(
        content.openRead(),
        headers: {
          'content-type': file['mime_type'] as String,
          'content-length': (await content.length()).toString(),
          'content-disposition':
              "inline; filename*=UTF-8''${Uri.encodeComponent(file['filename'] as String)}",
          'cache-control': 'private, no-store',
          'content-security-policy': "sandbox; default-src 'none'",
          'x-content-type-options': 'nosniff',
        },
      );
    });
    router.post(
      '/files',
      (Request request) async => json({
        'id': await media.upload(await actor(request), await readJson(request)),
      }, status: 201),
    );

    router.get(
      '/seller/stores',
      (Request request) async =>
          json(await catalog.ownedStores(await actor(request))),
    );
    router.post(
      '/seller/stores',
      (Request request) async => json({
        'id': await catalog.apply(
          await actor(request),
          await readJson(request),
        ),
      }, status: 201),
    );
    router.get(
      '/seller/stores/<store>/products',
      (Request request) async => json(
        await catalog.products(
          param(request, 'store'),
          actor: await actor(request),
        ),
      ),
    );
    router.post(
      '/seller/stores/<store>/products',
      (Request request) async => json({
        'id': await catalog.saveProduct(
          await actor(request),
          param(request, 'store'),
          await readJson(request),
        ),
      }, status: 201),
    );
    router.put(
      '/seller/stores/<store>/products/<product>',
      (Request request) async => json({
        'id': await catalog.saveProduct(
          await actor(request),
          param(request, 'store'),
          await readJson(request),
          param(request, 'product'),
        ),
      }),
    );
    router.delete('/seller/stores/<store>/products/<product>', (
      Request request,
    ) async {
      await catalog.archive(
        await actor(request),
        param(request, 'store'),
        param(request, 'product'),
      );
      return json({'ok': true});
    });
    router.post(
      '/seller/stores/<store>/products/<product>/stock',
      (Request request) async => json({
        'stock': await orders.stock(
          await actor(request),
          param(request, 'store'),
          param(request, 'product'),
          await readJson(request),
        ),
      }),
    );
    router.get(
      '/seller/stores/<store>/orders',
      (Request request) async => json(
        await orders.list(await actor(request), store: param(request, 'store')),
      ),
    );

    router.get(
      '/orders',
      (Request request) async => json(await orders.list(await actor(request))),
    );
    router.post(
      '/orders',
      (Request request) async => json({
        'id': await orders.checkout(
          await actor(request),
          await readJson(request),
          request.headers['idempotency-key'],
        ),
      }, status: 201),
    );
    router.post(
      '/orders/<order>/<action>',
      (Request request) async => json({
        'status': await orders.transition(
          await actor(request),
          param(request, 'order'),
          request.params['action']!,
        ),
      }),
    );

    router.get('/admin/users', (Request request) async {
      final query = request.url.queryParameters;
      final search = query['search'] ?? '';
      if (search.length > 100) invalid('Enter up to 100 characters to search.');
      return json(
        await accounts.users(await actor(request), search, query['role']),
      );
    });
    router.post('/admin/users/<user>/ban', (Request request) async {
      await accounts.ban(
        await actor(request),
        param(request, 'user'),
        await readJson(request),
      );
      return json({'ok': true});
    });
    router.get(
      '/admin/store-applications',
      (Request request) async =>
          json(await catalog.applications(await actor(request))),
    );
    router.post('/admin/store-applications/<application>', (
      Request request,
    ) async {
      await catalog.review(
        await actor(request),
        param(request, 'application'),
        await readJson(request),
      );
      return json({'ok': true});
    });
    router.post(
      '/admin/categories',
      (Request request) async => json({
        'id': await catalog.saveCategory(
          await actor(request),
          await readJson(request),
        ),
      }, status: 201),
    );
    router.put(
      '/admin/categories/<category>',
      (Request request) async => json({
        'id': await catalog.saveCategory(
          await actor(request),
          await readJson(request),
          param(request, 'category'),
        ),
      }),
    );
    router.delete('/admin/categories/<category>', (Request request) async {
      await catalog.deleteCategory(
        await actor(request),
        param(request, 'category'),
      );
      return json({'ok': true});
    });
    return (request) async {
      try {
        if (!{'GET', 'HEAD', 'OPTIONS'}.contains(request.method) &&
            cookieToken(request) != null)
          requireWebOrigin(request);
        final response = await router.call(request);
        if (response.statusCode == 404 &&
            response.headers['content-type'] !=
                'application/json; charset=utf-8')
          missing();
        return response;
      } on ApiError catch (error) {
        return json({
          'code': error.code,
          'message': error.message,
        }, status: error.status);
      } on FormatException {
        return json({
          'code': 'invalid_json',
          'message': 'The JSON payload is invalid.',
        }, status: 400);
      } on MySQLServerException catch (error) {
        if (error.errorCode == 1062) {
          return json({
            'code': 'duplicate',
            'message': 'An item with these details already exists.',
          }, status: 409);
        }
        if (error.errorCode == 1452) {
          return json({
            'code': 'invalid_reference',
            'message': 'A related item no longer exists.',
          }, status: 409);
        }
        stderr.writeln('MySQL request failed (${error.errorCode})');
        return json({
          'code': 'database_error',
          'message': 'The database could not complete the request.',
        }, status: 503);
      } catch (error, trace) {
        stderr.writeln('API request threw ${error.runtimeType}\n$trace');
        return json({
          'code': 'server_error',
          'message': 'The server could not complete the request.',
        }, status: 500);
      }
    };
  }
}
