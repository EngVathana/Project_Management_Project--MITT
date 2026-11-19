import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'picked_file.dart';

Future<PickedFile?> pick(BuildContext context, String accept) {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  final result = Completer<PickedFile?>();
  void cancel(web.Event event) => result.complete(null);
  void change(web.Event event) => result.complete(read(input.files?.item(0)));
  input.addEventListener('cancel', cancel.toJS);
  input.addEventListener('change', change.toJS);
  input.click();
  return result.future;
}

Future<PickedFile?> read(web.File? file) async {
  if (file == null) return null;
  try {
    final buffer = (await file.arrayBuffer().toDart).toDart;
    return (name: file.name, bytes: buffer.asUint8List());
  } on Exception {
    return null;
  }
}

void openUrl(Uri url) => web.window.open(url.toString(), '_blank', 'noopener');
