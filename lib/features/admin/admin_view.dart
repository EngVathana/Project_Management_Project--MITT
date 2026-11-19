import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/files_native.dart'
    if (dart.library.js_interop) '../../core/files_web.dart'
    as files;
import 'admin_repository.dart';
import 'admin_view_model.dart';

class AdminView extends StatefulWidget {
  const AdminView({super.key, required this.repository});
  final AdminRepository repository;
  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  late final model = AdminViewModel(widget.repository);
  AdminRepository get repo => widget.repository;
  final search = TextEditingController();
  int get tab => model.tab;
  String? get role => model.role;
  bool get working => model.working;

  @override
  void dispose() {
    search.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> edit(Future<void> Function() action) async {
    await perform(context, () => model.save(action));
  }

  void query() => model.query(search: search.text.trim(), role: role);

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: model, builder: (_, _) => body());

  Widget body() => Column(
    children: [
      Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              for (final (index, label) in [
                'Users',
                'Store requests',
                'Categories',
              ].indexed)
                ChoiceChip(
                  label: Text(label),
                  selected: tab == index,
                  onSelected: working ? null : (_) => model.show(index),
                ),
            ],
          ),
        ),
      ),
      if (working) const LinearProgressIndicator(),
      Expanded(
        child: AsyncPanel(
          future: model.records,
          retry: model.reload,
          builder: (items) => switch (tab) {
            0 => users(items),
            1 => applications(items),
            _ => categories(items),
          },
        ),
      ),
    ],
  );

  Widget users(List<Json> items) => PageList(
    children: [
      const SectionTitle('Manage users'),
      TextField(
        controller: search,
        maxLength: 100,
        onSubmitted: working ? null : (_) => query(),
        decoration: InputDecoration(
          labelText: 'Search name or phone',
          suffixIcon: IconButton(
            tooltip: 'Search users',
            onPressed: working ? null : () => query(),
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      DropdownButton<String>(
        value: role ?? '',
        onChanged: working
            ? null
            : (value) => model.query(
                search: search.text.trim(),
                role: value!.isEmpty ? null : value,
              ),
        items: const [
          DropdownMenuItem(value: '', child: Text('All users')),
          DropdownMenuItem(value: 'pet_owner', child: Text('Pet owners')),
          DropdownMenuItem(value: 'store_owner', child: Text('Pet stores')),
        ],
      ),
      if (items.isEmpty) const Text('No users match your search.'),
      for (final item in items)
        Card(
          child: ListTile(
            title: Text(item['name'] as String),
            subtitle: Text(
              "${statusLabel(item['role'] as String)} · ${item['phone']} · ${item['banned_until'] == null ? 'Active' : 'Banned'}",
            ),
            trailing: PopupMenuButton<String>(
              enabled: !working,
              tooltip: 'Ban user',
              onSelected: (value) async {
                final approved = await confirm(
                  context,
                  'Ban ${item['name']} for one $value?',
                  'Confirm ban',
                );
                if (approved && mounted) {
                  await edit(() => repo.ban(item['id'] as int, value));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'day', child: Text('Ban for 1 day')),
                PopupMenuItem(value: 'week', child: Text('Ban for 1 week')),
                PopupMenuItem(value: 'month', child: Text('Ban for 1 month')),
              ],
            ),
          ),
        ),
    ],
  );

  Widget applications(List<Json> items) => PageList(
    children: [
      const SectionTitle('Store requests'),
      if (items.isEmpty) const Text('No applications yet.'),
      for (final item in items)
        Card(
          child: ListTile(
            title: Text(item['name'] as String),
            subtitle: Text(statusLabel(item['status'] as String)),
            trailing: TextButton(
              onPressed: working ? null : () => review(item),
              child: const Text('View license'),
            ),
          ),
        ),
    ],
  );

  Future<void> review(Json item) async {
    final uri = repo.api.url("/files/${item['license_id']}");
    final filename = item['filename'] as String;
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(item['name'] as String),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(filename),
              if (RegExp(
                r'\.(jpe?g|png)$',
                caseSensitive: false,
              ).hasMatch(filename))
                Image.network(
                  uri.toString(),
                  height: 200,
                  errorBuilder: (_, _, _) =>
                      const Text('License preview unavailable'),
                ),
              TextButton.icon(
                onPressed: () => files.openUrl(uri),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open license'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
          if (item['status'] == 'pending') ...[
            OutlinedButton(
              onPressed: () => Navigator.pop(dialog, 'rejected'),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, 'approved'),
              child: const Text('Approve'),
            ),
          ],
        ],
      ),
    );
    if (result != null && mounted) {
      await edit(() => repo.review(item['id'] as int, result));
    }
  }

  Widget categories(List<Json> items) => PageList(
    children: [
      const SectionTitle('Platform categories'),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: working ? null : () => categoryForm(),
          child: const Text('Add category'),
        ),
      ),
      for (final item in items)
        Card(
          child: ListTile(
            title: Text(item['name'] as String),
            trailing: PopupMenuButton<String>(
              enabled: !working,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              onSelected: (value) async {
                if (value == 'edit') {
                  await categoryForm(item);
                } else if (await confirm(
                      context,
                      'Delete ${item['name']}?',
                      'Delete',
                    ) &&
                    mounted) {
                  await edit(() => repo.deleteCategory(item['id'] as int));
                }
              },
            ),
          ),
        ),
    ],
  );

  Future<void> categoryForm([Json? item]) async {
    final name = await prompt(
      context,
      item == null ? 'Add category' : 'Edit category',
      'Category name',
      initial: item?['name'] as String? ?? '',
      validate: (value) =>
          value.length > 80 ? 'Use up to 80 characters.' : null,
    );
    if (name != null && mounted) {
      await edit(() => repo.saveCategory(item?['id'] as int?, name));
    }
  }
}
