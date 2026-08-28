import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';

void main() {
  test('parseFreePages extrai paginas livres do vm_stat', () {
    expect(
      SystemMemoryReader.parseFreePages(
        'Pages free:                            46338.\nPages active: 100.',
      ),
      46338,
    );
    expect(SystemMemoryReader.parseFreePages('sem paginas aqui'), isNull);
  });

  test('parseMemAvailableKilobytes extrai MemAvailable do meminfo', () {
    expect(
      SystemMemoryReader.parseMemAvailableKilobytes(
        'MemTotal: 16384000 kB\nMemAvailable: 8388608 kB\n',
      ),
      8388608,
    );
    expect(
      SystemMemoryReader.parseMemAvailableKilobytes('MemTotal: 1 kB'),
      isNull,
    );
  });

  test('parseFreePhysicalMemoryKilobytes aceita saida do PowerShell', () {
    expect(
      SystemMemoryReader.parseFreePhysicalMemoryKilobytes('1048576\n'),
      1048576,
    );
    expect(
      SystemMemoryReader.parseFreePhysicalMemoryKilobytes('nao-numero'),
      isNull,
    );
  });

  test('calcula memoria livre no macOS por sysctl + vm_stat', () async {
    final reader = SystemMemoryReader(
      platform: SystemMemoryPlatform.macOS,
      runner: (executable, arguments) async {
        if (executable == 'sysctl') {
          expect(arguments, ['-n', 'hw.pagesize']);
          return ProcessResult(1, 0, '16384', '');
        }
        expect(executable, 'vm_stat');
        return ProcessResult(1, 0, 'Pages free: 1000.', '');
      },
    );

    expect(await reader.availableBytes(), 16384 * 1000);
  });

  test('calcula memoria livre no Linux por /proc/meminfo', () async {
    final reader = SystemMemoryReader(
      platform: SystemMemoryPlatform.linux,
      runner: (executable, arguments) async {
        expect(executable, 'cat');
        expect(arguments, ['/proc/meminfo']);
        return ProcessResult(1, 0, 'MemAvailable:   2048 kB', '');
      },
    );

    expect(await reader.availableBytes(), 2048 * 1024);
  });

  test('calcula memoria livre no Windows por PowerShell/CIM', () async {
    final reader = SystemMemoryReader(
      platform: SystemMemoryPlatform.windows,
      runner: (executable, arguments) async {
        expect(executable, 'powershell');
        expect(arguments[2], contains('Get-CimInstance'));
        return ProcessResult(1, 0, '4096', '');
      },
    );

    expect(await reader.availableBytes(), 4096 * 1024);
  });

  test('retorna null quando a fonte falha, inexiste ou e ilegivel', () async {
    final failing = SystemMemoryReader(
      platform: SystemMemoryPlatform.linux,
      runner: (_, _) async => ProcessResult(1, 1, '', 'erro'),
    );
    expect(await failing.availableBytes(), isNull);

    final throwing = SystemMemoryReader(
      platform: SystemMemoryPlatform.linux,
      runner: (_, _) async => throw ProcessException('cat', const []),
    );
    expect(await throwing.availableBytes(), isNull);

    final garbage = SystemMemoryReader(
      platform: SystemMemoryPlatform.macOS,
      runner: (executable, _) async => ProcessResult(
        1,
        0,
        executable == 'sysctl' ? '16384' : 'nada legivel',
        '',
      ),
    );
    expect(await garbage.availableBytes(), isNull);
  });
}
