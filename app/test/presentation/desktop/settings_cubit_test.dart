import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/settings_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/settings_state.dart';

import 'fakes/fake_ollama_repository.dart';

void main() {
  late FakeOllamaRepository fakeRepository;

  SettingsEditing initialState() => const SettingsEditing(
    hostText: 'http://127.0.0.1:11434',
    temperature: 0.1,
    contextText: '',
    allowEdit: true,
    allowCommands: true,
  );

  setUp(() {
    fakeRepository = FakeOllamaRepository()
      ..models = const [OllamaModelInfo(name: 'llama3.2:3b')];
  });

  group('SettingsCubit field updates', () {
    blocTest<SettingsCubit, SettingsState>(
      'updateContextText_changesOnlyContextText',
      build: () => SettingsCubit(fakeRepository, initial: initialState()),
      act: (cubit) => cubit.updateContextText('2048'),
      expect: () => [
        isA<SettingsEditing>()
            .having((s) => s.contextText, 'contextText', '2048')
            .having((s) => s.hostText, 'hostText', 'http://127.0.0.1:11434'),
      ],
    );
  });

  group('SettingsCubit.testHost', () {
    blocTest<SettingsCubit, SettingsState>(
      'testHost_whenInvalidHost_emitsResultWithoutCallingRepository',
      build: () => SettingsCubit(
        fakeRepository,
        initial: initialState().copyWith(hostText: 'nao-e-url'),
      ),
      act: (cubit) => cubit.testHost(),
      expect: () => [
        isA<SettingsEditing>().having(
          (s) => s.testResult?.ok,
          'testResult.ok',
          false,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'testHost_whenConnectionFails_emitsFailureResult',
      build: () => SettingsCubit(fakeRepository, initial: initialState()),
      act: (cubit) {
        fakeRepository.failure = const NetworkException('sem rede');
        return cubit.testHost();
      },
      expect: () => [
        isA<SettingsEditing>().having((s) => s.testing, 'testing', true),
        isA<SettingsEditing>()
            .having((s) => s.testing, 'testing', false)
            .having((s) => s.testResult?.ok, 'testResult.ok', false),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'testHost_whenSucceeds_emitsOkResultWithModelCount',
      build: () => SettingsCubit(fakeRepository, initial: initialState()),
      act: (cubit) => cubit.testHost(),
      expect: () => [
        isA<SettingsEditing>().having((s) => s.testing, 'testing', true),
        isA<SettingsEditing>()
            .having((s) => s.testing, 'testing', false)
            .having((s) => s.testResult?.ok, 'testResult.ok', true)
            .having((s) => s.testResult?.modelCount, 'modelCount', 1),
      ],
    );
  });

  group('SettingsCubit.save', () {
    blocTest<SettingsCubit, SettingsState>(
      'save_whenInvalidHost_emitsErrorWithoutCallingOnSave',
      build: () => SettingsCubit(
        fakeRepository,
        initial: initialState().copyWith(hostText: 'nao-e-url'),
      ),
      act: (cubit) => cubit.save(
        onSave:
            ({
              required hostText,
              required temperature,
              required contextLength,
              required keepAlive,
              required timeout,
              required allowEdit,
              required allowCommands,
            }) async => fail('onSave nao deveria ser chamado'),
      ),
      expect: () => [
        isA<SettingsEditing>().having(
          (s) => s.errorKind,
          'errorKind',
          SettingsErrorKind.invalidHost,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'save_whenOnSaveSucceeds_emitsSaved',
      build: () => SettingsCubit(fakeRepository, initial: initialState()),
      act: (cubit) => cubit.save(
        onSave:
            ({
              required hostText,
              required temperature,
              required contextLength,
              required keepAlive,
              required timeout,
              required allowEdit,
              required allowCommands,
            }) async => true,
      ),
      expect: () => [
        isA<SettingsEditing>().having((s) => s.saving, 'saving', true),
        isA<SettingsEditing>()
            .having((s) => s.saving, 'saving', false)
            .having((s) => s.saved, 'saved', true),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'save_whenOnSaveFails_emitsSaveFailedKeepingEdits',
      build: () => SettingsCubit(fakeRepository, initial: initialState()),
      act: (cubit) => cubit.save(
        onSave:
            ({
              required hostText,
              required temperature,
              required contextLength,
              required keepAlive,
              required timeout,
              required allowEdit,
              required allowCommands,
            }) async => false,
      ),
      expect: () => [
        isA<SettingsEditing>().having((s) => s.saving, 'saving', true),
        isA<SettingsEditing>()
            .having((s) => s.saving, 'saving', false)
            .having((s) => s.saved, 'saved', false)
            .having(
              (s) => s.errorKind,
              'errorKind',
              SettingsErrorKind.saveFailed,
            ),
      ],
    );
  });
}
