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

  OllamaDiscovery discoveryWith(Future<ProcessResult> Function() onList) =>
      OllamaDiscovery(
        processRunner: (executable, arguments, {environment}) {
          expect(executable, 'ollama');
          expect(arguments, const ['list']);
          return onList();
        },
      );

  ProcessResult bootOk() => ProcessResult(0, 0, 'NAME\nllama3\n', '');

  ProcessResult bootFails() => ProcessResult(0, 1, '', 'servidor nao subiu');

  setUp(() {
    fakeDataSource = FakeOllamaRemoteDataSource();
    // Boot sempre falha por padrao: os testes do auto-boot criam a propria
    // instancia com o comportamento desejado.
    repository = OllamaRepositoryImpl(
      fakeDataSource,
      discovery: discoveryWith(() async => bootFails()),
    );
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

  group('OllamaRepositoryImpl.autoBoot', () {
    test(
      'testConnection_whenConnectionFailsAndBootSucceeds_returnsOk',
      () async {
        fakeDataSource.exceptionToThrow = const SocketException('sem rede');
        fakeDataSource.failCount = 1;
        var bootCalls = 0;
        final repository = OllamaRepositoryImpl(
          fakeDataSource,
          discovery: discoveryWith(() async {
            bootCalls++;
            return bootOk();
          }),
        );

        final result = await repository.testConnection(host: host);

        expect(result.isOk, isTrue);
        expect(bootCalls, 1);
      },
    );

    test('testConnection_whenRemoteHostFails_doesNotBoot', () async {
      fakeDataSource.exceptionToThrow = const SocketException('sem rede');
      var bootCalls = 0;
      final repository = OllamaRepositoryImpl(
        fakeDataSource,
        discovery: discoveryWith(() async {
          bootCalls++;
          return bootOk();
        }),
      );
      final remoteHost = Uri.parse('http://192.168.0.10:11434');

      final result = await repository.testConnection(host: remoteHost);

      result.when(
        ok: (_) => fail('esperava erro'),
        error: (error) => expect(error, isA<NetworkException>()),
      );
      expect(bootCalls, 0);
    });

    test('testConnection_whenServerRespondsWithError_doesNotBoot', () async {
      fakeDataSource.exceptionToThrow = const OllamaException('falhou');
      var bootCalls = 0;
      final repository = OllamaRepositoryImpl(
        fakeDataSource,
        discovery: discoveryWith(() async {
          bootCalls++;
          return bootOk();
        }),
      );

      final result = await repository.testConnection(host: host);

      result.when(
        ok: (_) => fail('esperava erro'),
        error: (error) => expect(error, isA<OllamaServerException>()),
      );
      expect(bootCalls, 0);
    });

    test('testConnection_whenBootFails_keepsOriginalError', () async {
      fakeDataSource.exceptionToThrow = const SocketException('sem rede');

      final result = await repository.testConnection(host: host);

      result.when(
        ok: (_) => fail('esperava erro'),
        error: (error) => expect(error, isA<NetworkException>()),
      );
    });

    test('listModels_whenConnectionFailsAndBootSucceeds_returnsModels',
        () async {
      fakeDataSource.exceptionToThrow = const SocketException('sem rede');
      fakeDataSource.failCount = 1;
      fakeDataSource.models = const [OllamaModelInfo(name: 'llama3')];
      final repository = OllamaRepositoryImpl(
        fakeDataSource,
        discovery: discoveryWith(() async => bootOk()),
      );

      final result = await repository.listModels(host: host);

      result.when(
        ok: (models) => expect(models, hasLength(1)),
        error: (_) => fail('esperava sucesso'),
      );
    });
  });
}
