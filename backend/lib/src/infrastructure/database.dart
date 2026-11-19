import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mysql_client_plus/exception.dart';
import 'package:mysql_client_plus/mysql_client_plus.dart';

import 'config.dart';

typedef Row = Map<String, dynamic>;
typedef Query = Future<IResultSet> Function(
  String sql, [
  Map<String, dynamic>? parameters,
]);

class Sql {
  Sql(this.execute);
  final Query execute;
  Future<List<Row>> rows(String query, [Row parameters = const {}]) async {
    final result = await execute(query, parameters);
    return result.rows
        .map(
          (row) => row.typedAssoc().map(
            (key, value) => MapEntry(key, switch (value) {
              BigInt value => value.toInt(),
              DateTime value => value.toIso8601String(),
              _ => value,
            }),
          ),
        )
        .toList();
  }

  Future<Row?> one(String query, [Row parameters = const {}]) async =>
      (await rows(query, parameters)).firstOrNull;

  Future<int> insert(String query, [Row parameters = const {}]) async =>
      (await execute(query, parameters)).lastInsertID.toInt();
}

class Database extends Sql {
  Database._(this.pool) : super(pool.execute);
  final MySQLConnectionPool pool;

  factory Database(Config config) {
    final host = config.get('DB_HOST', '127.0.0.1');
    final tls = config.get('DB_TLS', 'true') == 'true';
    if (!tls && !{'localhost', '127.0.0.1', '::1'}.contains(host)) {
      throw StateError('Remote MySQL connections must use TLS.');
    }
    return Database._(
      MySQLConnectionPool(
        host: host,
        port: int.parse(config.get('DB_PORT', '3306')),
        userName: config.get('DB_USER'),
        password: config.get('DB_PASSWORD'),
        databaseName: config.get('DB_NAME'),
        maxConnections: 12,
        secure: tls,
        allowPublicKeyRetrieval: !tls,
        collation: 'utf8mb4_general_ci',
      ),
    );
  }

  Future<T> transaction<T>(Future<T> Function(Sql) action) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await pool.transactional(
          (connection) => action(Sql(connection.execute)),
        );
      } on MySQLServerException catch (error) {
        if (!{1205, 1213}.contains(error.errorCode) || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
      }
    }
  }

  Future<void> migrate(Directory directory) async {
    await execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(100) PRIMARY KEY, checksum CHAR(64) NOT NULL
      ) ENGINE=InnoDB
    ''');
    final scripts =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((first, second) => first.path.compareTo(second.path));
    if (scripts.isEmpty) throw StateError('No MySQL migrations found.');
    for (final file in scripts) {
      final version = file.uri.pathSegments.last;
      final source = await file.readAsString();
      final checksum = sha256.convert(utf8.encode(source)).toString();
      final applied = await one(
        'SELECT checksum FROM schema_migrations WHERE version=:version',
        {'version': version},
      );
      if (applied != null) {
        if (applied['checksum'] != checksum)
          throw StateError('Changed applied migration: $version');
        continue;
      }
      for (final sql
          in source
              .split(';')
              .map((statement) => statement.trim())
              .where((statement) => statement.isNotEmpty)) {
        await execute(sql);
      }
      await execute(
        'INSERT INTO schema_migrations VALUES (:version,:checksum)',
        {'version': version, 'checksum': checksum},
      );
      stdout.writeln('Applied $version');
    }
  }
}
