import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import '../lib/src/http/api.dart';
import '../lib/src/infrastructure/config.dart';
import '../lib/src/infrastructure/database.dart';
import '../lib/src/modules/accounts.dart';

Future<void> main(List<String> args) async {
  final config = Config.load(
    Platform.environment['MITT_CONFIG'] ?? '.env.local',
  );
  final db = Database(config);
  if (args.contains('migrate')) {
    try {
      await db.migrate(Directory('migrations/mysql'));
    } finally {
      await db.pool.close();
    }
    return;
  }
  if (args.contains('create-admin')) {
    try {
      await Accounts(db).createAdmin({
        'phone': config.get('MITT_ADMIN_PHONE'),
        'name': config.get('MITT_ADMIN_NAME', 'MITT Administrator'),
        'password': config.get('MITT_ADMIN_PASSWORD'),
      });
      stdout.writeln('Admin account created.');
    } finally {
      await db.pool.close();
    }
    return;
  }
  await db.execute('SELECT 1');
  if (await db.one(
        "SELECT version FROM schema_migrations WHERE version='001_marketplace.sql'",
      ) ==
      null) {
    throw StateError('Apply the database migrations before starting the API.');
  }
  final api = Api(
    db,
    Directory(config.get('MITT_FILE_DIR', '.data/uploads')),
    secureCookie: config.get('MITT_SECURE_COOKIE', 'true') == 'true',
    origin: config.values['MITT_ORIGIN'],
  ).handler;
  final portal = Directory(config.get('MITT_WEB_DIR', '../build/web'));
  final servePortal = portal.existsSync()
      ? createStaticHandler(portal.path, defaultDocument: 'index.html')
      : null;
  final Handler handler = (request) {
    if (request.url.path.startsWith('api/v1/'))
      return api(request.change(path: 'api/v1/'));
    return servePortal == null
        ? Response.notFound('Build the MITT portal or use /api/v1/health.')
        : servePortal(request);
  };
  final server = await shelf_io.serve(
    handler,
    config.get('MITT_HOST', '127.0.0.1'),
    int.parse(config.get('MITT_PORT', '8080')),
  );
  stdout.writeln(
    'MITT listening on http://${server.address.address}:${server.port}',
  );
  ProcessSignal.sigint.watch().first.then((_) async {
    await server.close(force: true);
    await db.pool.close();
  });
}
