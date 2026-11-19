import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../../core/files_native.dart'
    if (dart.library.js_interop) '../../core/files_web.dart'
    as files;
import '../../core/picked_file.dart';
import 'seller_repository.dart';
import 'seller_view_model.dart';

class SellerView extends StatefulWidget {
  const SellerView({super.key, required this.repository});
  final SellerRepository repository;
  @override
  State<SellerView> createState() => _SellerViewState();
}

class _SellerViewState extends State<SellerView> {
  late final model = SellerViewModel(widget.repository);
  SellerRepository get repo => widget.repository;
  int? get store => model.store;
  int get tab => model.tab;
  bool get working => model.working;

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> change(
    Future<void> Function() action, {
    bool reloadStores = false,
  }) async {
    await perform(
      context,
      () => model.save(action, reloadStores: reloadStores),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: model, builder: (_, _) => body());

  Widget body() => AsyncPanel(
    future: model.stores,
    retry: model.refreshStores,
    builder: (owned) {
      final tabs = ['Products', 'Stock', 'Deliveries', 'Registration'];
      final approved = owned.where((item) => item['status'] == 'approved');
      return Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Refresh stores',
                    onPressed: working ? null : model.refreshStores,
                    icon: const Icon(Icons.refresh),
                  ),
                  if (approved.isNotEmpty)
                    DropdownButton<int>(
                      value: store,
                      onChanged: working ? null : model.selectStore,
                      items: [
                        for (final item in approved)
                          DropdownMenuItem(
                            value: item['id'] as int,
                            child: Text(item['name'] as String),
                          ),
                      ],
                    ),
                  for (var index = 0; index < tabs.length; index++)
                    ChoiceChip(
                      label: Text(tabs[index]),
                      selected: tab == index,
                      onSelected: working ? null : (_) => model.show(index),
                    ),
                ],
              ),
            ),
          ),
          if (working) const LinearProgressIndicator(),
          Expanded(
            child: tab == 3 || store == null
                ? registration(owned)
                : AsyncPanel(
                    future: model.records!,
                    retry: model.refreshRecords,
                    builder: (items) => switch (tab) {
                      0 => products(items),
                      1 => stock(items),
                      _ => deliveries(items),
                    },
                  ),
          ),
        ],
      );
    },
  );

  Widget registration(List<Json> owned) => PageList(
    children: [
      const SectionTitle('Store registration'),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: working ? null : register,
          child: const Text('Register a store'),
        ),
      ),
      for (final item in owned)
        Card(
          child: ListTile(
            title: Text(item['name'] as String),
            trailing: Chip(label: Text(statusLabel(item['status'] as String))),
          ),
        ),
    ],
  );

  Future<void> register() async {
    final name = await prompt(
      context,
      'Register a store',
      'Store name',
      validate: (value) =>
          value.length > 100 ? 'Use up to 100 characters.' : null,
    );
    if (name == null || !mounted) return;
    final license = await files.pick(
      context,
      'image/png,image/jpeg,application/pdf',
    );
    if (license == null || !mounted) return;
    await change(() async {
      final id = await repo.api.upload('license', license.name, license.bytes);
      await repo.registerStore(name, id);
      if (mounted) notify(context, 'License submitted for review.');
    }, reloadStores: true);
  }

  Widget products(List<Json> items) => PageList(
    children: [
      const SectionTitle('Products'),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: working ? null : () => edit(),
          icon: const Icon(Icons.add),
          label: const Text('Add product'),
        ),
      ),
      if (items.isEmpty) const Text('No products yet.'),
      for (final item in items)
        Card(
          child: ListTile(
            leading: ProductPhoto(api: repo.api, id: item['photo_id'] as int?),
            title: Text(item['name'] as String),
            subtitle: Text(
              "${item['description']} · ${money(item['price_minor'] as int)}",
            ),
            trailing: PopupMenuButton<String>(
              enabled: !working,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              onSelected: (value) async {
                if (value == 'edit') {
                  await edit(item);
                } else if (await confirm(
                      context,
                      'Delete ${item['name']}?',
                      'Delete',
                    ) &&
                    mounted) {
                  await change(() => repo.archive(store!, item['id'] as int));
                }
              },
            ),
          ),
        ),
    ],
  );

  Future<void> edit([Json? item]) async {
    final storeId = store!;
    final List<Json> categories;
    try {
      categories = await repo.categories();
    } on ApiFailure catch (error) {
      if (mounted) notify(context, error.message);
      return;
    }
    if (!mounted) return;
    final input = await showDialog<({Json fields, PickedFile? photo})>(
      context: context,
      builder: (_) => _ProductForm(item: item, categories: categories),
    );
    if (input == null || !mounted) return;
    await change(() async {
      final photo = input.photo;
      if (photo != null) {
        input.fields['photo_id'] = await repo.api.upload(
          'product',
          photo.name,
          photo.bytes,
        );
      }
      await repo.saveProduct(storeId, item?['id'] as int?, input.fields);
    });
  }

  Widget stock(List<Json> items) => PageList(
    children: [
      const SectionTitle('Stock'),
      if (items.isEmpty) const Text('Add a product to start managing stock.'),
      for (final item in items)
        Card(
          child: ListTile(
            title: Text(item['name'] as String),
            subtitle: Text('${item['stock']} units in stock'),
            trailing: PopupMenuButton<String>(
              enabled: !working,
              tooltip: 'Manage stock',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Add stock')),
                PopupMenuItem(value: 'set', child: Text('Edit stock')),
                PopupMenuItem(value: 'clear', child: Text('Clear stock')),
              ],
              onSelected: (action) async {
                final storeId = store!;
                final int amount;
                if (action == 'clear') {
                  if (!await confirm(
                    context,
                    'Clear stock for ${item['name']}?',
                    'Clear stock',
                  )) {
                    return;
                  }
                  amount = 0;
                } else {
                  final adding = action == 'add';
                  final units = await prompt(
                    context,
                    adding ? 'Add stock' : 'Edit stock',
                    adding ? 'Units to add' : 'Units in stock',
                    initial: adding ? '' : '${item['stock']}',
                    validate: (value) {
                      final quantity = int.tryParse(value) ?? -1;
                      return quantity < (adding ? 1 : 0) ||
                              quantity > 1000000000
                          ? 'Enter a valid whole number.'
                          : null;
                    },
                  );
                  if (units == null) return;
                  amount = int.parse(units);
                }
                if (mounted) {
                  await change(
                    () => repo.stock(
                      storeId,
                      item['id'] as int,
                      action == 'add' ? 'add' : 'set',
                      amount,
                    ),
                  );
                }
              },
            ),
          ),
        ),
    ],
  );

  Widget deliveries(List<Json> items) => PageList(
    children: [
      const SectionTitle('Deliveries'),
      if (items.isEmpty) const Text('No orders for this store yet.'),
      for (final order in items)
        OrderTile(
          order,
          seller: true,
          act: (action) =>
              change(() => repo.transition(order['id'] as int, action)),
        ),
    ],
  );
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({required this.item, required this.categories});
  final Json? item;
  final List<Json> categories;
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final form = GlobalKey<FormState>();
  late String name = widget.item?['name'] as String? ?? '';
  late String description = widget.item?['description'] as String? ?? '';
  late String price = widget.item == null
      ? ''
      : ((widget.item!['price_minor'] as int) / 100).toStringAsFixed(2);
  late int category =
      widget.categories.any((item) => item['id'] == widget.item?['category_id'])
      ? widget.item!['category_id'] as int
      : 0;
  PickedFile? photo;

  String? requiredText(String? value, int limit) =>
      value == null || value.trim().isEmpty || value.trim().length > limit
      ? 'Enter 1–$limit characters.'
      : null;

  int? parsePrice(String? value) {
    final normalized = value?.trim() ?? '';
    if (!RegExp(r'^\d{1,8}(\.\d{1,2})?$').hasMatch(normalized)) return null;
    final parts = normalized.split('.');
    final amount =
        100 * int.parse(parts[0]) +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
    return amount > 0 && amount <= 1000000000 ? amount : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? 'Add product' : 'Edit product'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InputField(
                label: 'Name',
                initial: name,
                onChanged: (value) => name = value.trim(),
                validator: (value) => requiredText(value, 100),
              ),
              InputField(
                label: 'Description',
                initial: description,
                onChanged: (value) => description = value.trim(),
                validator: (value) => requiredText(value, 2000),
                maxLines: 3,
              ),
              InputField(
                label: 'Price (\$)',
                initial: price,
                onChanged: (value) => price = value.trim(),
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) => parsePrice(value) == null
                    ? 'Enter a positive price with up to two decimals.'
                    : null,
              ),
              DropdownButtonFormField<int>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text('Uncategorized'),
                  ),
                  for (final item in widget.categories)
                    DropdownMenuItem(
                      value: item['id'] as int,
                      child: Text(item['name'] as String),
                    ),
                ],
                onChanged: (value) => category = value!,
              ),
              TextButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: Text(photo?.name ?? 'Choose product photo'),
                onPressed: () async {
                  final file = await files.pick(
                    context,
                    'image/png,image/jpeg',
                  );
                  if (file != null && mounted) setState(() => photo = file);
                },
              ),
              if (photo != null)
                Image.memory(
                  photo!.bytes,
                  height: 72,
                  errorBuilder: (_, _, _) =>
                      const Text('Image preview unavailable'),
                ),
              if (widget.item == null) const Text('Starting stock · 0 units'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, (
            fields: <String, dynamic>{
              'name': name,
              'description': description,
              'price_minor': parsePrice(price),
              'category_id': category == 0 ? null : category,
              'photo_id': widget.item?['photo_id'],
            },
            photo: photo,
          ));
        },
        child: const Text('Save product'),
      ),
    ],
  );
}
