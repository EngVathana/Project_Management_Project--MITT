import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../auth/session.dart';
import 'shopper_repository.dart';

class ShopperViewModel extends ChangeNotifier {
  ShopperViewModel(this.repository, this.session) {
    refreshExplore();
    session.addListener(_sessionChanged);
  }

  final ShopperRepository repository;
  final Session session;
  final cart = Cart();
  int tab = 0;
  int? category;
  Json? store;
  late Future<(List<Json>, List<Json>)> exploreData;
  Future<List<Json>>? products;
  Future<List<Json>>? orders;
  bool _updatingOrder = false;
  bool _disposed = false;

  void refreshExplore() {
    exploreData = (repository.categories(), repository.stores(category)).wait;
    notifyListeners();
  }

  void filter(int? id) {
    category = id;
    refreshExplore();
  }

  void openStore(Json? item) {
    store = item;
    if (item == null) {
      refreshExplore();
    } else {
      refreshProducts();
    }
  }

  void refreshProducts() {
    products = repository.products(store!['id'] as int);
    notifyListeners();
  }

  void refreshOrders() {
    orders = repository.orders();
    notifyListeners();
  }

  void show(int next) {
    tab = next;
    if (tab == 0) {
      if (store == null) {
        refreshExplore();
      } else {
        refreshProducts();
      }
    } else if (tab == 2 && session.user != null) {
      refreshOrders();
    } else {
      notifyListeners();
    }
  }

  void _sessionChanged() {
    if (session.user == null) {
      cart.clear();
      orders = null;
    } else if (tab == 2) {
      refreshOrders();
      return;
    }
    notifyListeners();
  }

  Future<void> place() => cart.place(repository);

  Future<void> receive(int id) async {
    if (_updatingOrder) return;
    _updatingOrder = true;
    try {
      await repository.receive(id);
      if (!_disposed && tab == 2 && session.user != null) refreshOrders();
    } finally {
      _updatingOrder = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    cart.dispose();
    super.dispose();
  }
}
