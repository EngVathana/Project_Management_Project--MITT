import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../../core/api_client.dart';
import '../auth/account_view.dart';
import '../auth/session.dart';
import 'shopper_repository.dart';
import 'shopper_view_model.dart';

class ShopperView extends StatefulWidget {
  const ShopperView({
    super.key,
    required this.repository,
    required this.session,
  });
  final ShopperRepository repository;
  final Session session;
  @override
  State<ShopperView> createState() => _ShopperViewState();
}

class _ShopperViewState extends State<ShopperView> {
  late final model = ShopperViewModel(widget.repository, widget.session);
  ShopperRepository get repo => widget.repository;
  Cart get cart => model.cart;
  int get tab => model.tab;
  int? get category => model.category;
  Json? get store => model.store;

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, cart]),
    builder: (context, _) => Column(
      children: [
        Expanded(
          child: switch (tab) {
            0 => store == null ? storefronts() : storefront(),
            1 => cartView(),
            2 => orderView(),
            _ => AccountView(session: widget.session),
          },
        ),
        NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: model.show,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: cart.units > 0,
                label: Text('${cart.units}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              label: 'Cart',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Orders',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Account',
            ),
          ],
        ),
      ],
    ),
  );

  Widget storefronts() => AsyncPanel(
    future: model.exploreData,
    retry: model.refreshExplore,
    builder: (data) {
      final (categories, stores) = data;
      return PageList(
        children: [
          const SectionTitle('Categories'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in <Json>[
                  {'id': null, 'name': 'All'},
                  ...categories,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry['name'] as String),
                      selected: category == entry['id'],
                      onSelected: (_) => model.filter(entry['id'] as int?),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Pet stores'),
          if (stores.isEmpty) const Text('No stores match this category.'),
          for (final item in stores)
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.storefront_outlined),
                ),
                title: Text(item['name'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => model.openStore(item),
              ),
            ),
        ],
      );
    },
  );

  Widget storefront() => AsyncPanel(
    future: model.products!,
    retry: model.refreshProducts,
    builder: (items) => PageList(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => model.openStore(null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('All stores'),
          ),
        ),
        SectionTitle(store!['name'] as String),
        if (items.isEmpty) const Text('This store has no products yet.'),
        for (final item in items)
          Card(
            child: ListTile(
              leading: ProductPhoto(
                api: repo.api,
                id: item['photo_id'] as int?,
              ),
              title: Text(item['name'] as String),
              isThreeLine: true,
              subtitle: Text(
                "${item['description']}\n${money(item['price_minor'] as int)} · ${item['stock']} available",
              ),
              trailing: IconButton(
                tooltip: 'Add to cart',
                icon: const Icon(Icons.add_shopping_cart),
                onPressed:
                    cart.quantity(item['id'] as int) >= (item['stock'] as int)
                    ? null
                    : () {
                        notify(
                          context,
                          cart.add({...item, 'store_name': store!['name']}) ??
                              'Added to cart.',
                        );
                      },
              ),
            ),
          ),
      ],
    ),
  );

  Widget cartView() => PageList(
    children: [
      const SectionTitle('Your cart'),
      if (cart.lines.isEmpty) const Text('Your cart is empty.'),
      if (cart.lines.isNotEmpty) ...[
        Text(cart.lines.first.product['store_name'] as String),
        for (final line in cart.lines)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      ProductPhoto(
                        api: repo.api,
                        id: line.product['photo_id'] as int?,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(line.product['name'] as String)),
                      Text(
                        money(
                          line.quantity * (line.product['price_minor'] as int),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: cart.checkingOut
                            ? null
                            : () => cart.remove(
                                line.product['id'] as int,
                                all: true,
                              ),
                        child: const Text('Remove'),
                      ),
                      IconButton(
                        tooltip: 'Decrease quantity',
                        onPressed: cart.checkingOut
                            ? null
                            : () => cart.remove(line.product['id'] as int),
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${line.quantity}'),
                      IconButton(
                        tooltip: 'Increase quantity',
                        onPressed:
                            cart.checkingOut ||
                                line.quantity >= (line.product['stock'] as int)
                            ? null
                            : () => cart.add(line.product),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Total · ${money(cart.total)}'),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffc4e0f1),
            foregroundColor: const Color(0xff183e55),
          ),
          onPressed: cart.checkingOut
              ? null
              : () async {
                  if (widget.session.user == null) {
                    notify(context, 'Sign in to place your order.');
                    model.show(3);
                    return;
                  }
                  final success = await perform(context, model.place);
                  if (success && mounted) model.show(2);
                },
          child: Text(cart.checkingOut ? 'Placing order…' : 'Place order'),
        ),
      ],
    ],
  );

  Widget orderView() => widget.session.user == null
      ? PageList(
          children: [
            const SectionTitle('Your orders'),
            const Text('Sign in to see your orders.'),
            TextButton(
              onPressed: () => model.show(3),
              child: const Text('Go to account'),
            ),
          ],
        )
      : AsyncPanel(
          future: model.orders!,
          retry: model.refreshOrders,
          builder: (items) => PageList(
            children: [
              const SectionTitle('Your orders'),
              if (items.isEmpty) const Text('No orders yet.'),
              for (final order in items)
                OrderTile(
                  order,
                  act: (_) async {
                    await perform(
                      context,
                      () => model.receive(order['id'] as int),
                    );
                  },
                ),
            ],
          ),
        );
}
