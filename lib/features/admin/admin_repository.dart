import '../../core/api_client.dart';

class AdminRepository {
  AdminRepository(this.api);
  final ApiClient api;

  Future<List<Json>> users(String search, String? role) =>
      api.list('/admin/users', {'search': search, 'role': ?role});
  Future<List<Json>> applications() => api.list('/admin/store-applications');
  Future<List<Json>> categories() => api.list('/categories');
  Future<void> ban(int id, String duration) async {
    await api.object(
      'POST',
      '/admin/users/$id/ban',
      body: {'duration': duration},
    );
  }

  Future<void> review(int id, String decision) async {
    await api.object(
      'POST',
      '/admin/store-applications/$id',
      body: {'decision': decision},
    );
  }

  Future<void> saveCategory(int? id, String name) async {
    await api.object(
      id == null ? 'POST' : 'PUT',
      id == null ? '/admin/categories' : '/admin/categories/$id',
      body: {'name': name},
    );
  }

  Future<void> deleteCategory(int id) async {
    await api.object('DELETE', '/admin/categories/$id');
  }
}
