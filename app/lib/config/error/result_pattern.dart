import 'package:salvador_desktop/config/error/app_exception.dart';

sealed class Result<T> {
  const Result();

  factory Result.ok(T value) = Ok<T>;

  factory Result.error(AppException error) = Error<T>;

  bool get isOk => this is Ok<T>;

  bool get isError => this is Error<T>;

  R when<R>({
    required R Function(T value) ok,
    required R Function(AppException error) error,
  });
}

class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppException error) error,
  }) => ok(value);
}

class Error<T> extends Result<T> {
  const Error(this.error);

  final AppException error;

  @override
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppException error) error,
  }) => error(this.error);
}
