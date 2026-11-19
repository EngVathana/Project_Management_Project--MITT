import 'package:mitt_backend/src/modules/contracts.dart';
import 'package:mitt_backend/src/modules/orders.dart';
import 'package:test/test.dart';

void main() {
  test(
    'checkout requires distinct product IDs and whole positive quantities',
    () {
      expect(() => parseCart([]), throwsA(isA<ApiError>()));
      expect(
        () => parseCart([
          {'product_id': 1, 'quantity': 0},
        ]),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => parseCart([
          {'product_id': 1, 'quantity': 1.5},
        ]),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => parseCart([
          {'product_id': 1, 'quantity': 2},
          {'product_id': 1, 'quantity': 1},
        ]),
        throwsA(isA<ApiError>()),
      );
      final valid = parseCart([
        {'product_id': 3, 'quantity': 1},
        {'product_id': 1, 'quantity': 2},
      ]);
      expect(valid.keys.toList(), [1, 3]);
      expect(valid.values.toList(), [2, 1]);
    },
  );

  test('phone validation normalizes formatted numbers and rejects letters', () {
    expect(phoneNumber({'phone': '080 000 0101'}), '0800000101');
    expect(
      () => phoneNumber({'phone': '080-kit-0101'}),
      throwsA(isA<ApiError>()),
    );
  });
}
