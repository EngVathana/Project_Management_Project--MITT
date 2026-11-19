import 'package:flutter/material.dart';

import '../core/api_client.dart';

void notify(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

Future<bool> perform(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
    return true;
  } on ApiFailure catch (error) {
    if (context.mounted) notify(context, error.message);
    return false;
  }
}

class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.width = 760});
  final List<Widget> children;
  final double width;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: ListView(padding: const EdgeInsets.all(20), children: children),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class InputField extends StatelessWidget {
  const InputField({
    super.key,
    required this.label,
    this.controller,
    this.initial,
    this.onChanged,
    this.validator,
    this.keyboard,
    this.obscure = false,
    this.suffix,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController? controller;
  final String? initial;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboard;
  final bool obscure;
  final Widget? suffix;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      initialValue: initial,
      onChanged: onChanged,
      validator: validator,
      keyboardType: keyboard,
      obscureText: obscure,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, suffixIcon: suffix),
    ),
  );
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel({
    super.key,
    required this.future,
    required this.retry,
    required this.builder,
  });
  final Future<T> future;
  final VoidCallback retry;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error is ApiFailure
                      ? snapshot.error.toString()
                      : 'Unable to load this page.',
                ),
                TextButton(onPressed: retry, child: const Text('Try again')),
              ],
            ),
          ),
        );
      }
      return builder(snapshot.requireData);
    },
  );
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({super.key, required this.api, required this.id});
  final ApiClient api;
  final int? id;
  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: Color(0xffeee3f7),
      child: Icon(Icons.pets, color: Color(0xff7748ae)),
    );
    return SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: id == null
            ? fallback
            : Image.network(
                api.url('/files/$id').toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class OrderTile extends StatelessWidget {
  const OrderTile(
    this.order, {
    super.key,
    this.seller = false,
    required this.act,
  });
  final Json order;
  final bool seller;
  final Future<void> Function(String action) act;
  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final (action, label) = switch ((seller, status)) {
      (true, 'placed') => ('confirm', 'Confirm order'),
      (true, 'confirmed') => ('dispatch', 'Mark on delivery'),
      (false, 'on_delivery') => ('receive', 'Confirm receipt'),
      _ => ('', ''),
    };
    final lines = (order['lines'] as List).cast<Json>();
    final total = lines.fold(
      0,
      (sum, item) =>
          sum + (item['quantity'] as int) * (item['unit_price_minor'] as int),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '#${order['id']} · ${order['store_name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Chip(label: Text(statusLabel(status))),
            for (final item in lines)
              Text('${item['quantity']} × ${item['name']}'),
            const SizedBox(height: 6),
            Text('Total · ${money(total)}'),
            if (action.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  onPressed: () => act(action),
                  child: Text(label),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> prompt(
  BuildContext context,
  String title,
  String label, {
  String initial = '',
  String? Function(String)? validate,
}) {
  final form = GlobalKey<FormState>();
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: InputField(
          label: label,
          initial: initial,
          onChanged: (text) => value = text.trim(),
          validator: (text) => text == null || text.trim().isEmpty
              ? 'Required'
              : validate?.call(text.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(dialog, value);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
