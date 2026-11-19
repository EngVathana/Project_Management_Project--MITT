import '../../core/api_client.dart';

class SellerRepository {
  SellerRepository(this.api);
  final ApiClient api;
  String store(int id) => '/seller/stores/$id';
  String product(int storeId, int productId) =>
      '${store(storeId)}/products/$productId';

  Future<List<Json>> stores() => api.list('/seller/stores');
  Future<List<Json>> categories() => api.list('/categories');
  Future<List<Json>> products(int id) => api.list('${store(id)}/products');
  Future<List<Json>> deliveries(int id) => api.list('${store(id)}/orders');

  Future<void> registerStore(String name, int license) async {
    await api.object(
      'POST',
      '/seller/stores',
      body: {'name': name, 'license_id': license},
    );
  }

  Future<void> saveProduct(int storeId, int? id, Json values) async {
    await api.object(
      id == null ? 'POST' : 'PUT',
      id == null ? '${store(storeId)}/products' : product(storeId, id),
      body: values,
    );
  }

  Future<void> archive(int storeId, int id) async {
    await api.object('DELETE', product(storeId, id));
  }

  Future<void> stock(int storeId, int id, String action, int quantity) async {
    await api.object(
      'POST',
      '${product(storeId, id)}/stock',
      body: {'action': action, 'quantity': quantity},
    );
  }

  Future<void> transition(int order, String action) async {
    await api.object('POST', '/orders/$order/$action', body: {});
  }
}
