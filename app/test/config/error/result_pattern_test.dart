import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';

void main() {
  group('Result', () {
    test('ok_whenCalled_runsOkBranchWithValue', () {
      final result = Result<int>.ok(42);

      final output = result.when(
        ok: (value) => 'ok:$value',
        error: (error) => 'error:${error.message}',
      );

      expect(output, 'ok:42');
    });

    test('ok_isOkAndIsError_reflectState', () {
      final result = Result<int>.ok(42);

      expect(result.isOk, isTrue);
      expect(result.isError, isFalse);
    });

    test('error_whenCalled_runsErrorBranchWithOriginalException', () {
      const exception = UnknownException('falhou');
      final result = Result<int>.error(exception);

      final output = result.when(
        ok: (value) => 'ok:$value',
        error: (error) => error,
      );

      expect(output, same(exception));
    });

    test('error_isOkAndIsError_reflectState', () {
      final result = Result<int>.error(const UnknownException('falhou'));

      expect(result.isOk, isFalse);
      expect(result.isError, isTrue);
    });
  });
}
