import 'dart:convert';
import 'dart:math';

import '../infrastructure/database.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);
  final int status;
  final String code, message;
}

Never invalid(String message) => throw ApiError(422, 'validation', message);
Never forbidden() => throw const ApiError(
  403,
  'forbidden',
  'You do not have access to this action.',
);
Never missing() =>
    throw const ApiError(404, 'not_found', 'This item was not found.');
Never conflict(String message, [String code = 'conflict']) =>
    throw ApiError(409, code, message);

String text(Row body, String key, int max, {int min = 1}) {
  final value = body[key];
  if (value is! String ||
      value.trim().length < min ||
      value.trim().length > max) {
    invalid('Enter a valid $key ($min–$max characters).');
  }
  return value.trim();
}

int number(Row body, String key, {int min = 1, int max = 1000000000}) {
  final value = body[key];
  if (value is! int || value < min || value > max)
    invalid('Enter a valid whole number for $key.');
  return value;
}

int id(String value) =>
    number({'id': int.tryParse(value)}, 'id', max: 9007199254740991);

String phoneNumber(Row body) {
  final raw = text(body, 'phone', 40);
  if (!RegExp(r'^\+?[\d() .-]+$').hasMatch(raw))
    invalid('Enter a valid phone number.');
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 7 || digits.length > 15)
    invalid('Enter a valid phone number.');
  return digits;
}

String password(Row body, [String key = 'password']) {
  final value = body[key];
  if (value is! String || value.length < 8 || utf8.encode(value).length > 72) {
    invalid(
      'Enter a password with at least 8 characters and at most 72 UTF-8 bytes.',
    );
  }
  return value;
}

final _random = Random.secure();
String secretToken() => List.generate(
  32,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class Actor {
  Actor(this.user);
  final Row user;
  int get id => user['id'] as int;
  String get role => user['role'] as String;
  void require(String expected) {
    if (role != expected) forbidden();
  }
}
