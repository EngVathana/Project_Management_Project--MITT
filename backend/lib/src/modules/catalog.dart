import '../infrastructure/database.dart';
import 'contracts.dart';
import 'media.dart';

class Catalog {
  Catalog(this.db, this.media);
  final Database db;
  final Media media;

  Future<List<Row>> categories() =>
      db.rows('SELECT id,name FROM categories ORDER BY name');

  Future<List<Row>> stores(int? category) => db.rows(
    '''
    SELECT s.id,s.name,s.status FROM stores s WHERE s.status='approved'
    AND (:category IS NULL OR EXISTS (
      SELECT 1 FROM products p WHERE p.store_id=s.id AND p.category_id=:category AND p.archived_at IS NULL
    )) ORDER BY s.name
  ''',
    {'category': category},
  );

  Future<List<Row>> ownedStores(Actor actor) {
    actor.require('store_owner');
    return db.rows(
      'SELECT id,name,status FROM stores WHERE owner_id=:owner ORDER BY id',
      {'owner': actor.id},
    );
  }

  Future<void> verifyStore(Sql sql, Actor actor, int store) async {
    actor.require('store_owner');
    final record = await sql.one(
      "SELECT id FROM stores WHERE id=:id AND owner_id=:owner AND status='approved'",
      {'id': store, 'owner': actor.id},
    );
    if (record == null) forbidden();
  }

  Future<List<Row>> products(int store, {Actor? actor}) async {
    if (actor != null) {
      await verifyStore(db, actor, store);
    } else if (await db.one(
          "SELECT id FROM stores WHERE id=:id AND status='approved'",
          {'id': store},
        ) ==
        null) {
      missing();
    }
    return db.rows(
      '''
      SELECT p.id,p.store_id,p.category_id,p.photo_id,p.name,p.description,p.price_minor,i.quantity AS stock
      FROM products p JOIN inventory i ON i.product_id=p.id
      WHERE p.store_id=:store AND p.archived_at IS NULL ORDER BY p.name
    ''',
      {'store': store},
    );
  }

  Future<int> apply(Actor actor, Row payload) async {
    actor.require('store_owner');
    final name = text(payload, 'name', 100);
    final license = number(payload, 'license_id');
    return db.transaction((sql) async {
      await media.validateReference(sql, actor, license, 'license');
      final store = await sql.insert(
        'INSERT INTO stores (name,owner_id) VALUES (:name,:owner)',
        {'name': name, 'owner': actor.id},
      );
      await sql.execute(
        'INSERT INTO store_applications (store_id,license_id) VALUES (:store,:license)',
        {'store': store, 'license': license},
      );
      return store;
    });
  }

  Future<List<Row>> applications(Actor actor) {
    actor.require('admin');
    return db.rows('''
      SELECT a.id,a.store_id,a.license_id,s.name,a.decision AS status,f.filename,a.reviewed_by
      FROM store_applications a JOIN stores s ON s.id=a.store_id
      JOIN files f ON f.id=a.license_id ORDER BY a.id DESC
    ''');
  }

  Future<void> review(Actor actor, int application, Row payload) async {
    actor.require('admin');
    final decision = payload['decision'];
    if (decision != 'approved' && decision != 'rejected')
      invalid('Select approve or reject.');
    await db.transaction((sql) async {
      final record = await sql.one(
        'SELECT store_id,decision FROM store_applications WHERE id=:id FOR UPDATE',
        {'id': application},
      );
      if (record == null) missing();
      if (record['decision'] != 'pending')
        conflict('This application has already been reviewed.');
      await sql.execute(
        '''
        UPDATE store_applications SET decision=:decision,reviewed_by=:actor,reviewed_at=UTC_TIMESTAMP(6) WHERE id=:id
      ''',
        {'decision': decision, 'actor': actor.id, 'id': application},
      );
      await sql.execute('UPDATE stores SET status=:decision WHERE id=:id', {
        'decision': decision,
        'id': record['store_id'],
      });
    });
  }

  Future<int> saveCategory(Actor actor, Row payload, [int? category]) async {
    actor.require('admin');
    final name = text(payload, 'name', 80);
    if (category == null)
      return db.insert('INSERT INTO categories (name) VALUES (:name)', {
        'name': name,
      });
    if (await db.one('SELECT id FROM categories WHERE id=:id', {
          'id': category,
        }) ==
        null)
      missing();
    await db.execute('UPDATE categories SET name=:name WHERE id=:id', {
      'name': name,
      'id': category,
    });
    return category;
  }

  Future<void> deleteCategory(Actor actor, int category) async {
    actor.require('admin');
    final result = await db.execute('DELETE FROM categories WHERE id=:id', {
      'id': category,
    });
    if (result.affectedRows == BigInt.zero) missing();
  }

  Future<int> saveProduct(
    Actor actor,
    int store,
    Row payload, [
    int? product,
  ]) async {
    final values = {
      'name': text(payload, 'name', 100),
      'description': text(payload, 'description', 2000),
      'price': number(payload, 'price_minor'),
      'category': payload['category_id'] == null
          ? null
          : number(payload, 'category_id'),
      'photo': payload['photo_id'] == null ? null : number(payload, 'photo_id'),
      'store': store,
    };
    return db.transaction((sql) async {
      await verifyStore(sql, actor, store);
      final photo = values['photo'] as int?;
      final category = values['category'];
      if (photo != null)
        await media.validateReference(sql, actor, photo, 'product');
      if (category != null &&
          await sql.one('SELECT id FROM categories WHERE id=:id', {
                'id': category,
              }) ==
              null) {
        invalid('Choose an existing category.');
      }
      if (product != null) {
        await requireProduct(sql, store, product);
        await sql.execute(
          '''
          UPDATE products SET name=:name,description=:description,price_minor=:price,category_id=:category,photo_id=:photo
          WHERE id=:id AND store_id=:store
        ''',
          {...values, 'id': product},
        );
        return product;
      }
      final inserted = await sql.insert('''
        INSERT INTO products (name,description,price_minor,category_id,photo_id,store_id)
        VALUES (:name,:description,:price,:category,:photo,:store)
      ''', values);
      await sql.execute('INSERT INTO inventory (product_id) VALUES (:id)', {
        'id': inserted,
      });
      return inserted;
    });
  }

  Future<void> requireProduct(Sql sql, int store, int product) async {
    final existing = await sql.one(
      '''
      SELECT id FROM products WHERE id=:id AND store_id=:store AND archived_at IS NULL FOR UPDATE
    ''',
      {'id': product, 'store': store},
    );
    if (existing == null) missing();
  }

  Future<void> archive(Actor actor, int store, int product) async {
    await db.transaction((sql) async {
      await verifyStore(sql, actor, store);
      await requireProduct(sql, store, product);
      final pending = await sql.one(
        '''
        SELECT o.id FROM order_items i JOIN orders o ON o.id=i.order_id
        WHERE i.product_id=:id AND o.status='placed' LIMIT 1 FOR UPDATE
      ''',
        {'id': product},
      );
      if (pending != null)
        conflict('Confirm pending orders for this product before deleting it.');
      await sql.execute(
        'UPDATE products SET archived_at=UTC_TIMESTAMP(6) WHERE id=:id',
        {'id': product},
      );
    });
  }
}
