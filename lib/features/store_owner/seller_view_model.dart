import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'seller_repository.dart';

class SellerViewModel extends ChangeNotifier {
  SellerViewModel(this.repository) {
    refreshStores();
  }

  final SellerRepository repository;
  late Future<List<Json>> stores;
  Future<List<Json>>? records;
  int? store;
  int tab = 0;
  bool working = false;
  bool _disposed = false;

  void refreshStores() {
    stores = _loadStores();
    notifyListeners();
  }

  Future<List<Json>> _loadStores() async {
    final owned = await repository.stores();
    if (_disposed) return owned;
    final approved = owned.where((item) => item['status'] == 'approved');
    if (!approved.any((item) => item['id'] == store)) {
      store = approved.firstOrNull?['id'] as int?;
    }
    _loadRecords();
    return owned;
  }

  void show(int value) {
    tab = value;
    refreshRecords();
  }

  void selectStore(int? id) {
    store = id;
    refreshRecords();
  }

  void refreshRecords() {
    _loadRecords();
    notifyListeners();
  }

  void _loadRecords() {
    final id = store;
    records = id == null || tab == 3
        ? null
        : tab == 2
        ? repository.deliveries(id)
        : repository.products(id);
  }

  Future<void> save(
    Future<void> Function() action, {
    bool reloadStores = false,
  }) async {
    if (working) return;
    working = true;
    notifyListeners();
    try {
      await action();
      if (!_disposed) {
        if (reloadStores) {
          refreshStores();
        } else {
          refreshRecords();
        }
      }
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
