import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';

class ShopperRepository {
  ShopperRepository(this.api);
  final ApiClient api;

  Future<List<Json>> categories() => api.list('/categories');
  Future<List<Json>> stores(int? category) =>
      api.list('/stores', category == null ? null : {'category': '$category'});
  Future<List<Json>> products(int store) => api.list('/stores/$store/products');
  Future<List<Json>> orders() => api.list('/orders');
  Future<void> checkout(int store, List<Json> items, String key) async {
    await api.object(
      'POST',
      '/orders',
      body: {'store_id': store, 'items': items},
      checkoutKey: key,
    );
  }

  Future<void> receive(int order) async {
    await api.object('POST', '/orders/$order/receive', body: {});
  }
}

class Cart extends ChangeNotifier {
  final _lines = <int, ({Json product, int quantity})>{};
  String? _checkoutKey;
  bool checkingOut = false;
  bool _disposed = false;
  int? get store => _lines.values.firstOrNull?.product['store_id'] as int?;
  Iterable<({Json product, int quantity})> get lines => _lines.values;
  int get units => lines.fold(0, (sum, item) => sum + item.quantity);
  int get total => lines.fold(
    0,
    (sum, item) => sum + item.quantity * (item.product['price_minor'] as int),
  );
  int quantity(int product) => _lines[product]?.quantity ?? 0;

  String? add(Json product) {
    if (checkingOut) return 'Checkout is in progress.';
    final id = product['id'] as int;
    if (store != null && store != product['store_id']) {
      return 'Your cart can contain items from one store.';
    }
    final count = quantity(id) + 1;
    if (count > (product['stock'] as int)) {
      return 'Only ${product['stock']} available.';
    }
    _lines[id] = (product: product, quantity: count);
    _changed();
    return null;
  }

  void remove(int id, {bool all = false}) {
    if (checkingOut) return;
    final line = _lines[id];
    if (line == null) return;
    if (all || line.quantity == 1) {
      _lines.remove(id);
    } else {
      _lines[id] = (product: line.product, quantity: line.quantity - 1);
    }
    _changed();
  }

  void clear() {
    if (checkingOut) return;
    _lines.clear();
    _changed();
  }

  void _changed() {
    _checkoutKey = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> place(ShopperRepository repository) async {
    final storeId = store;
    if (checkingOut || storeId == null) return;
    final random = Random.secure();
    _checkoutKey ??= List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    checkingOut = true;
    if (!_disposed) notifyListeners();
    try {
      await repository.checkout(storeId, [
        for (final line in lines)
          {'product_id': line.product['id'], 'quantity': line.quantity},
      ], _checkoutKey!);
      _lines.clear();
      _checkoutKey = null;
    } finally {
      checkingOut = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
