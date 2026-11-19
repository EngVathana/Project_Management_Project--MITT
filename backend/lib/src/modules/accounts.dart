import 'dart:convert';
import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

import '../infrastructure/database.dart';
import 'contracts.dart';

class Accounts {
  Accounts(this.db, {this.cost = 12});
  final Database db;
  final int cost;

  String digest(String token) => sha256.convert(utf8.encode(token)).toString();

  Future<String> hashPassword(String value) async {
    final rounds = cost;
    return Isolate.run(
      () => BCrypt.hashpw(value, BCrypt.gensalt(logRounds: rounds)),
    );
  }

  Future<bool> verifyPassword(String value, String hash) =>
      Isolate.run(() => BCrypt.checkpw(value, hash));

  Future<Actor> register(Row payload) async {
    final role = payload['role'];
    if (role != 'pet_owner' && role != 'store_owner')
      invalid('Select a valid account role.');
    final name = text(payload, 'name', 100);
    final phone = phoneNumber(payload);
    final pass = password(payload);
    if (payload['confirmation'] != pass) invalid('The passwords do not match.');
    final hash = await hashPassword(pass);
    final userId = await db.insert(
      'INSERT INTO users (name,phone,password_hash,role) VALUES (:name,:phone,:hash,:role)',
      {'name': name, 'phone': phone, 'hash': hash, 'role': role},
    );
    return Actor({'id': userId, 'name': name, 'phone': phone, 'role': role});
  }

  Future<void> createAdmin(Row payload) async {
    final phone = phoneNumber(payload);
    final hash = await hashPassword(password(payload));
    await db.execute(
      "INSERT INTO users (name,phone,password_hash,role) VALUES (:name,:phone,:hash,'admin')",
      {'name': text(payload, 'name', 100), 'phone': phone, 'hash': hash},
    );
  }

  Future<(Actor, String)> login(Row payload) async {
    final phone = phoneNumber(payload);
    final pass = password(payload);
    final user = await db.one(
      'SELECT id,name,phone,role,password_hash FROM users WHERE phone=:phone',
      {'phone': phone},
    );
    final dummyHash =
        r'$2b$12$C6UzMDM.H6dfI/f/IKcEe.yr2vH/4nup0XrMm6l17Ro7hX9N1wzAa';
    final hash = (user?['password_hash'] as String?) ?? dummyHash;
    final valid = await verifyPassword(pass, hash);
    if (user == null || !valid)
      throw const ApiError(
        401,
        'invalid_credentials',
        'Phone number or password is incorrect.',
      );
    final actor = Actor(user..remove('password_hash'));
    final token = secretToken();
    await db.transaction((sql) async {
      final current = await sql.one(
        'SELECT password_hash FROM users WHERE id=:id FOR UPDATE',
        {'id': actor.id},
      );
      if (current?['password_hash'] != hash) {
        throw const ApiError(
          401,
          'invalid_credentials',
          'Phone number or password is incorrect.',
        );
      }
      await ensureActive(actor.id, sql);
      await sql.execute(
        'INSERT INTO sessions VALUES (:token,:id,DATE_ADD(UTC_TIMESTAMP(6),INTERVAL 7 DAY))',
        {'token': digest(token), 'id': actor.id},
      );
    });
    return (actor, token);
  }

  Future<void> ensureActive(int userId, Sql sql) async {
    final ban = await sql.one(
      '''
      SELECT id FROM user_bans WHERE user_id=:id
      AND starts_at <= UTC_TIMESTAMP(6) AND ends_at > UTC_TIMESTAMP(6) LIMIT 1
    ''',
      {'id': userId},
    );
    if (ban != null)
      throw const ApiError(403, 'banned', 'This account is suspended.');
  }

  Future<Actor> authenticate(String? token) async {
    if (token == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const ApiError(401, 'unauthenticated', 'Sign in to continue.');
    }
    final user = await db.one(
      '''
      SELECT u.id,u.name,u.phone,u.role FROM users u JOIN sessions s ON s.user_id=u.id
      WHERE s.token_hash=:token AND s.expires_at > UTC_TIMESTAMP(6)
    ''',
      {'token': digest(token)},
    );
    if (user == null)
      throw const ApiError(401, 'unauthenticated', 'Sign in to continue.');
    final actor = Actor(user);
    await ensureActive(actor.id, db);
    return actor;
  }

  Future<void> logout(String? token) async {
    if (token != null)
      await db.execute('DELETE FROM sessions WHERE token_hash=:token', {
        'token': digest(token),
      });
  }

  Future<void> changePassword(Row payload) async {
    final phone = phoneNumber(payload);
    final old = password(payload, 'old_password');
    final replacement = password(payload, 'new_password');
    if (replacement == old || replacement != payload['confirmation']) {
      invalid(
        'Enter a different password and make sure the confirmation matches.',
      );
    }
    final user = await db.one(
      'SELECT id,password_hash FROM users WHERE phone=:phone',
      {'phone': phone},
    );
    final dummyHash =
        r'$2b$12$C6UzMDM.H6dfI/f/IKcEe.yr2vH/4nup0XrMm6l17Ro7hX9N1wzAa';
    final hash = (user?['password_hash'] as String?) ?? dummyHash;
    final valid = await verifyPassword(old, hash);
    if (user == null || !valid)
      throw const ApiError(
        401,
        'invalid_credentials',
        'Phone number or old password is incorrect.',
      );
    final newHash = await hashPassword(replacement);
    await db.transaction((sql) async {
      final current = await sql.one(
        'SELECT password_hash FROM users WHERE id=:id FOR UPDATE',
        user,
      );
      if (current?['password_hash'] != hash)
        conflict('Password changed. Sign in again.');
      await sql.execute('UPDATE users SET password_hash=:hash WHERE id=:id', {
        'hash': newHash,
        'id': user['id'],
      });
      await sql.execute('DELETE FROM sessions WHERE user_id=:id', user);
    });
  }

  Future<List<Row>> users(Actor actor, String search, String? role) async {
    actor.require('admin');
    if (role != null && !{'pet_owner', 'store_owner'}.contains(role))
      invalid('Select a valid role filter.');
    return db.rows(
      '''
      SELECT u.id,u.name,u.phone,u.role,
      (SELECT MAX(ends_at) FROM user_bans b WHERE b.user_id=u.id
        AND b.starts_at <= UTC_TIMESTAMP(6) AND b.ends_at > UTC_TIMESTAMP(6)) AS banned_until
      FROM users u WHERE u.role <> 'admin' AND (:role IS NULL OR u.role=:role)
      AND (LOCATE(:search,u.name)>0 OR LOCATE(:search,u.phone)>0 OR :search='')
      ORDER BY u.name LIMIT 100
    ''',
      {'role': role, 'search': search},
    );
  }

  Future<void> ban(Actor actor, int target, Row payload) async {
    actor.require('admin');
    final interval = switch (payload['duration']) {
      'day' => '1 DAY',
      'week' => '1 WEEK',
      'month' => '1 MONTH',
      _ => invalid('Select one day, one week, or one month.'),
    };
    final user = await db.one(
      "SELECT id FROM users WHERE id=:id AND role <> 'admin'",
      {'id': target},
    );
    if (user == null) missing();
    await db.execute(
      '''
      INSERT INTO user_bans (user_id,admin_id,ends_at)
      VALUES (:id,:admin,DATE_ADD(UTC_TIMESTAMP(6), INTERVAL $interval))
    ''',
      {'id': target, 'admin': actor.id},
    );
  }
}
