import 'package:flutter_test/flutter_test.dart';
import 'package:slay_flutter/core/supabase/supabase_retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('Supabase Retry & Transient Error Detection', () {
    test('isTransientPostgrestError detects PGRST303 clock skew', () {
      const err1 = PostgrestException(
        message: 'JWT issued at future',
        code: 'PGRST303',
        details: 'Unauthorized',
      );
      expect(isTransientPostgrestError(err1), isTrue);

      const err2 = PostgrestException(
        message: 'JWT not yet valid',
        code: 'PGRST301',
      );
      expect(isTransientPostgrestError(err2), isTrue);

      final err3 = Exception('PostgrestException: JWT issued at future');
      expect(isTransientPostgrestError(err3), isTrue);
    });

    test('isTransientPostgrestError ignores regular PostgREST errors', () {
      const err = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      expect(isTransientPostgrestError(err), isFalse);
    });

    test('retrySupabaseOperation retries and succeeds after transient error', () async {
      int calls = 0;
      final result = await retrySupabaseOperation<String>(
        () async {
          calls++;
          if (calls < 2) {
            throw const PostgrestException(
              message: 'JWT issued at future',
              code: 'PGRST303',
            );
          }
          return 'ok';
        },
        maxRetries: 2,
        initialDelay: const Duration(milliseconds: 10),
      );

      expect(calls, equals(2));
      expect(result, equals('ok'));
    });

    test('retrySupabaseOperation rethrows non-transient error immediately', () async {
      int calls = 0;
      expect(
        () => retrySupabaseOperation<String>(
          () async {
            calls++;
            throw const PostgrestException(
              message: 'Invalid column',
              code: '42703',
            );
          },
          maxRetries: 3,
          initialDelay: const Duration(milliseconds: 10),
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, equals(1));
    });
  });
}
