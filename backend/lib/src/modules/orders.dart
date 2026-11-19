import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../infrastructure/database.dart';
import 'catalog.dart';
import 'contracts.dart';

class Orders {
  Orders(this.db, this.catalog);
  final Database db;
  final Catalog catalog;

  Future<int> checkout(Actor actor, Row payload, String? key) async {
    actor.require('pet_owner');
    if (key == null || !RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(key)) {
      invalid('A valid checkout key is required.');
    }
    final store = number(payload, 'store_id');
    final lines = parseCart(payload['items']);
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              store,
              ...lines.entries.map((entry) => [entry.key, entry.value]),
            ]),
          ),
        )
        .toString();
    return db.transaction((sql) async {
      final params = {
        'store': store,
        'buyer': actor.id,
        'key': key,
        'hash': fingerprint,
      };
      // Serialize duplicate checkout attempts for the same buyer before reading the key.
      await sql.one('SELECT id FROM users WHERE id=:buyer FOR UPDATE', params);
      final existing = await sql.one(
        'SELECT id,checkout_hash FROM orders WHERE buyer_id=:buyer AND checkout_key=:key FOR UPDATE',
        params,
      );
      if (existing != null) {
        if (existing['checkout_hash'] != fingerprint)
          conflict('This checkout key was already used for a different cart.');
        return existing['id'] as int;
      }
      final approved = await sql.one(
        "SELECT id FROM stores WHERE id=:store AND status='approved'",
        params,
      );
      if (approved == null) conflict('This store is unavailable.');
      final items = <Row>[];
      for (final entry in lines.entries) {
        final product = await sql.one(
          '''
          SELECT p.id,p.name,p.price_minor,i.quantity FROM products p JOIN inventory i ON i.product_id=p.id
          WHERE p.id=:id AND p.store_id=:store AND p.archived_at IS NULL FOR UPDATE
        ''',
          {'id': entry.key, 'store': store},
        );
        if (product == null)
          invalid('Every product must be available from the selected store.');
        if ((product['quantity'] as int) < entry.value)
          conflict(
            'Insufficient stock for ${product['name']}.',
            'insufficient_stock',
          );
        items.add({...product, 'requested': entry.value});
      }
      final order = await sql.insert('''
        INSERT INTO orders (store_id,buyer_id,checkout_key,checkout_hash) VALUES (:store,:buyer,:key,:hash)
      ''', params);
      for (final item in items) {
        await sql.execute(
          '''
          INSERT INTO order_items (order_id,store_id,product_id,product_name,unit_price_minor,quantity)
          VALUES (:order,:store,:id,:name,:price_minor,:requested)
        ''',
          {...item, 'order': order, 'store': store},
        );
      }
      return order;
    });
  }

  Future<List<Row>> list(Actor actor, {int? store}) async {
    if (store == null) {
      actor.require('pet_owner');
    } else {
      await catalog.verifyStore(db, actor, store);
    }
    final records = await db.rows(
      '''
      SELECT o.id,o.store_id,s.name AS store_name,o.status,o.created_at,
        i.product_id,i.product_name,i.unit_price_minor,i.quantity
      FROM orders o JOIN stores s ON s.id=o.store_id JOIN order_items i ON i.order_id=o.id
      WHERE (${store == null ? 'o.buyer_id=:owner' : 'o.store_id=:owner'})
      ORDER BY o.id DESC,i.product_id
    ''',
      {'owner': store ?? actor.id},
    );
    final orders = <int, Row>{};
    for (final row in records) {
      final order = orders.putIfAbsent(
        row['id'] as int,
        () => {
          'id': row['id'],
          'store_id': row['store_id'],
          'store_name': row['store_name'],
          'status': row['status'],
          'created_at': row['created_at'],
          'lines': <Row>[],
        },
      );
      (order['lines'] as List<Row>).add({
        'product_id': row['product_id'],
        'name': row['product_name'],
        'unit_price_minor': row['unit_price_minor'],
        'quantity': row['quantity'],
      });
    }
    return orders.values.toList();
  }

  Future<String> transition(Actor actor, int order, String action) async {
    final (expected, next, role) = switch (action) {
      'confirm' => ('placed', 'confirmed', 'store_owner'),
      'dispatch' => ('confirmed', 'on_delivery', 'store_owner'),
      'receive' => ('on_delivery', 'delivered', 'pet_owner'),
      _ => missing(),
    };
    actor.require(role);
    return db.transaction((sql) async {
      final record = await sql.one(
        'SELECT store_id,buyer_id,status FROM orders WHERE id=:id FOR UPDATE',
        {'id': order},
      );
      if (record == null) missing();
      if (role == 'store_owner') {
        await catalog.verifyStore(sql, actor, record['store_id'] as int);
      } else if (record['buyer_id'] != actor.id) {
        forbidden();
      }
      final status = record['status'] as String;
      if (status == next ||
          (action == 'confirm' &&
              {'on_delivery', 'delivered'}.contains(status)))
        return status;
      if (status != expected)
        conflict('The order cannot move from its current status.');
      if (action == 'confirm') {
        final lines = await sql.rows(
          '''
          SELECT product_id,quantity,product_name FROM order_items WHERE order_id=:order ORDER BY product_id
        ''',
          {'order': order},
        );
        if (lines.isEmpty) conflict('The order has no items.');
        for (final line in lines) {
          final stock = await sql.one(
            'SELECT quantity FROM inventory WHERE product_id=:product_id FOR UPDATE',
            line,
          );
          if (stock == null ||
              (stock['quantity'] as int) < (line['quantity'] as int)) {
            conflict(
              'Insufficient stock for ${line['product_name']}.',
              'insufficient_stock',
            );
          }
        }
        for (final line in lines) {
          await sql.execute(
            'UPDATE inventory SET quantity=quantity-:quantity WHERE product_id=:product_id',
            line,
          );
          await sql.execute(
            '''
            INSERT INTO stock_movements (product_id,actor_id,order_id,delta,reason)
            VALUES (:product_id,:actor,:order,-:quantity,'confirmation')
          ''',
            {...line, 'actor': actor.id, 'order': order},
          );
        }
      }
      await sql.execute('UPDATE orders SET status=:status WHERE id=:id', {
        'status': next,
        'id': order,
      });
      return next;
    });
  }

  Future<int> stock(Actor actor, int store, int product, Row payload) async {
    final action = payload['action'];
    if (action != 'add' && action != 'set') invalid('Choose add or set stock.');
    final amount = number(payload, 'quantity', min: action == 'add' ? 1 : 0);
    return db.transaction((sql) async {
      await catalog.verifyStore(sql, actor, store);
      await catalog.requireProduct(sql, store, product);
      final row = await sql.one(
        'SELECT quantity FROM inventory WHERE product_id=:id FOR UPDATE',
        {'id': product},
      );
      if (row == null) missing();
      final current = row['quantity'] as int;
      final updated = action == 'add' ? current + amount : amount;
      if (updated > 1000000000) invalid('Stock exceeds the allowed quantity.');
      final delta = updated - current;
      if (delta == 0) return current;
      await sql.execute(
        'UPDATE inventory SET quantity=:quantity WHERE product_id=:id',
        {'quantity': updated, 'id': product},
      );
      await sql.execute(
        '''
        INSERT INTO stock_movements (product_id,actor_id,delta,reason) VALUES (:id,:actor,:delta,:reason)
      ''',
        {
          'id': product,
          'actor': actor.id,
          'delta': delta,
          'reason': action == 'add' ? 'restock' : 'adjustment',
        },
      );
      return updated;
    });
  }
}

Map<int, int> parseCart(Object? payload) {
  if (payload is! List || payload.isEmpty || payload.length > 100)
    invalid('Choose between 1 and 100 distinct products.');
  final lines = <int, int>{};
  for (final item in payload) {
    if (item is! Map<String, dynamic>) invalid('Invalid order item.');
    final product = number(item, 'product_id');
    if (lines.containsKey(product))
      invalid('Each product can appear only once.');
    lines[product] = number(item, 'quantity');
  }
  return {for (final id in lines.keys.toList()..sort()) id: lines[id]!};
}
