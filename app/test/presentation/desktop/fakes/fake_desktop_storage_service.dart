import 'dart:io';

import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';

class FakeDesktopStorageService extends DesktopStorageService {
  FakeDesktopStorageService({DesktopPreferencesEntity? initial})
    : _state = initial ?? const DesktopPreferencesEntity(),
      super(file: File('/tmp/salvador_fake_storage_test.json'));

  DesktopPreferencesEntity _state;
  DesktopPreferencesEntity? lastSaved;
  int saveCallCount = 0;

  @override
  Future<DesktopPreferencesEntity> load() async => _state;

  @override
  Future<void> save(DesktopPreferencesEntity state) async {
    _state = state;
    lastSaved = state;
    saveCallCount++;
  }
}
