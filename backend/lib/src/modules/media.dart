import 'dart:convert';
import 'dart:io';

import '../infrastructure/database.dart';
import 'contracts.dart';

class Media {
  Media(this.db, this.root);
  final Database db;
  final Directory root;

  Future<int> upload(Actor actor, Row payload) async {
    actor.require('store_owner');
    final purpose = payload['purpose'];
    if (purpose != 'product' && purpose != 'license')
      invalid('Invalid file purpose.');
    final filename = text(
      payload,
      'filename',
      255,
    ).split(RegExp(r'[/\\]')).last;
    final encoded = text(payload, 'data', 7000000);
    final List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      invalid('Invalid file encoding.');
    }
    if (bytes.length > 5 * 1024 * 1024)
      invalid('The file must be 5 MB or smaller.');
    bool starts(List<int> prefix) =>
        bytes.length >= prefix.length &&
        List.generate(
          prefix.length,
          (index) => bytes[index] == prefix[index],
        ).every((match) => match);
    final mime = switch (true) {
      _ when starts([137, 80, 78, 71, 13, 10, 26, 10]) => 'image/png',
      _ when starts([255, 216, 255]) => 'image/jpeg',
      _ when purpose == 'license' && starts([37, 80, 68, 70, 45]) =>
        'application/pdf',
      _ => invalid('Upload a PNG or JPEG image, or a PDF for a license.'),
    };
    await root.create(recursive: true);
    final key = secretToken();
    final file = File('${root.path}/$key');
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await db.insert(
        '''
        INSERT INTO files (owner_id,purpose,storage_key,filename,mime_type)
        VALUES (:owner,:purpose,:key,:filename,:mime)
      ''',
        {
          'owner': actor.id,
          'purpose': purpose,
          'key': key,
          'filename': filename,
          'mime': mime,
        },
      );
    } catch (_) {
      await file.delete();
      rethrow;
    }
  }

  Future<Row> read(int id, Actor? actor) async {
    final record = await db.one(
      '''
      SELECT f.*,EXISTS (
        SELECT 1 FROM products p JOIN stores s ON s.id=p.store_id
        WHERE p.photo_id=f.id AND p.archived_at IS NULL AND s.status='approved'
      ) AS is_public FROM files f WHERE f.id=:id
    ''',
      {'id': id},
    );
    if (record == null) missing();
    if (record['is_public'] != 1 &&
        actor?.id != record['owner_id'] &&
        !(actor?.role == 'admin' && record['purpose'] == 'license'))
      missing();
    final file = File('${root.path}/${record['storage_key']}');
    if (!await file.exists()) missing();
    return {...record, 'file': file};
  }

  Future<void> validateReference(
    Sql sql,
    Actor actor,
    int id,
    String purpose,
  ) async {
    final file = await sql.one(
      'SELECT id FROM files WHERE id=:id AND owner_id=:owner AND purpose=:purpose',
      {'id': id, 'owner': actor.id, 'purpose': purpose},
    );
    if (file == null) invalid('Select a valid uploaded file.');
  }
}
