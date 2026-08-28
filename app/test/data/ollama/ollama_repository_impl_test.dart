import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/data/repositories/ollama_repository_impl.dart';

import 'fakes/fake_ollama_remote_datasource.dart';

void main() {
  late FakeOllamaRemoteDataSource fakeDataSource;
  late OllamaRepositoryImpl repository;
  final host = Uri.parse('http://127.0.0.1:11434');

  setUp(() {
    fakeDataSource = FakeOllamaRemoteDataSource();
    repository = OllamaRepositoryImpl(fakeDataSource);
  });

  group('OllamaRepositoryImpl.testConnection', () {
    test('testConnection_whenDataSourceSucceeds_returnsOk', () async {
      final result = await repository.testConnection(host: host);

      expect(result.isOk, isTrue);
    });

    test(
      'testConnection_whenSocketExceptionThrown_returnsNetworkException',
      () async {
        fakeDataSource.exceptionToThrow = const SocketException('sem rede');

        final result = await repository.testConnection(host: host);

        expect(result.isError, isTrue);
        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) => expect(error, isA<NetworkException>()),
        );
      },
    );
  });

  group('OllamaRepositoryImpl.listModels', () {
    test('listModels_whenDataSourceSucceeds_returnsOk', () async {
      fakeDataSource.models = const [OllamaModelInfo(name: 'llama3')];

      final result = await repository.listModels(host: host);

      result.when(
        ok: (models) => expect(models, hasLength(1)),
        error: (_) => fail('esperava sucesso'),
      );
    });

    test(
      'listModels_whenNoModelsInstalled_returnsOllamaServerException',
      () async {
        fakeDataSource.models = const [];

        final result = await repository.listModels(host: host);

        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) => expect(error, isA<OllamaServerException>()),
        );
      },
    );

    test(
      'listModels_whenOllamaExceptionThrown_returnsOllamaServerException',
      () async {
        fakeDataSource.exceptionToThrow = const OllamaException('falhou');

        final result = await repository.listModels(host: host);

        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) => expect(error, isA<OllamaServerException>()),
        );
      },
    );
  });
}
