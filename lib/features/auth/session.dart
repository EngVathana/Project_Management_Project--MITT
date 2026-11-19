import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';

class AuthRepository {
  AuthRepository(this.api);
  final ApiClient api;
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'mitt_session';

  Future<Json?> restore() async {
    if (!kIsWeb) api.token = await _storage.read(key: _tokenKey);
    if (!kIsWeb && api.token == null) return null;
    try {
      return await api.object('GET', '/auth/me');
    } on ApiFailure catch (error) {
      if (error.status != 401 && error.status != 403) rethrow;
      await clearToken();
      return null;
    }
  }

  Future<Json> login(String phone, String password) async {
    final user = await api.object(
      'POST',
      '/auth/login',
      body: {
        'phone': phone,
        'password': password,
        'client': kIsWeb ? 'web' : 'mobile',
      },
    );
    if (!kIsWeb) {
      api.token = user.remove('token') as String;
      await _storage.write(key: _tokenKey, value: api.token);
    }
    return user;
  }

  Future<void> register(
    String name,
    String phone,
    String password,
    String confirmation, {
    required bool portal,
  }) async {
    await api.object(
      'POST',
      '/auth/register',
      body: {
        'name': name,
        'phone': phone,
        'password': password,
        'confirmation': confirmation,
        'role': portal ? 'store_owner' : 'pet_owner',
      },
    );
  }

  Future<void> changePassword(
    String phone,
    String old,
    String next,
    String confirmation,
  ) async {
    await api.object(
      'POST',
      '/auth/password',
      body: {
        'phone': phone,
        'old_password': old,
        'new_password': next,
        'confirmation': confirmation,
      },
    );
    await clearToken();
  }

  Future<void> logout() async {
    await api.object('POST', '/auth/logout', body: {});
    await clearToken();
  }

  Future<void> clearToken() async {
    api.token = null;
    if (!kIsWeb) await _storage.delete(key: _tokenKey);
  }
}

class Session extends ChangeNotifier {
  Session(this.repository, {required this.portal});
  final AuthRepository repository;
  final bool portal;
  Json? user;
  bool loading = true;
  String? restoreError;
  bool _disposed = false;

  bool accepts(Json user) => portal
      ? {'store_owner', 'admin'}.contains(user['role'])
      : user['role'] == 'pet_owner';

  Future<void> restore() async {
    loading = true;
    restoreError = null;
    _update();
    try {
      final saved = await repository.restore();
      user = saved != null && accepts(saved) ? saved : null;
    } on ApiFailure catch (error) {
      restoreError = error.message;
    } on Exception {
      restoreError = 'Could not restore your session.';
    } finally {
      loading = false;
      _update();
    }
  }

  Future<void> login(String phone, String password) async {
    final signedIn = await repository.login(phone, password);
    if (!accepts(signedIn)) {
      await repository.logout();
      throw ApiFailure(
        portal
            ? 'Use a store owner or administrator account.'
            : 'Use a pet-owner account.',
      );
    }
    user = signedIn;
    _update();
  }

  Future<void> logout() async {
    await repository.logout();
    user = null;
    _update();
  }

  void _update() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
