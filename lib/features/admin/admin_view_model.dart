import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'admin_repository.dart';

class AdminViewModel extends ChangeNotifier {
  AdminViewModel(this.repository) {
    reload();
  }

  final AdminRepository repository;
  int tab = 0;
  String? role;
  String search = '';
  late Future<List<Json>> records;
  bool working = false;
  bool _disposed = false;

  void show(int value) {
    tab = value;
    reload();
  }

  void query({required String search, required String? role}) {
    this.search = search;
    this.role = role;
    reload();
  }

  void reload() {
    records = switch (tab) {
      0 => repository.users(search, role),
      1 => repository.applications(),
      _ => repository.categories(),
    };
    notifyListeners();
  }

  Future<void> save(Future<void> Function() action) async {
    if (working) return;
    working = true;
    notifyListeners();
    try {
      await action();
      if (!_disposed) reload();
    } finally {
      working = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
