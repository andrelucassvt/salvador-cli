import 'dart:io';

typedef MemoryProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

enum SystemMemoryPlatform { macOS, linux, windows }

/// Le a memoria disponivel do sistema com fontes especificas por plataforma:
/// `sysctl` + `vm_stat` no macOS, `/proc/meminfo` no Linux e PowerShell/CIM no
/// Windows. Retorna null quando a metrica nao puder ser obtida.
class SystemMemoryReader {
  SystemMemoryReader({
    MemoryProcessRunner? runner,
    SystemMemoryPlatform? platform,
  }) : _runner = runner ?? _defaultRunner,
       _platform = platform ?? _currentPlatform();

  static const _windowsCommand =
      'Get-CimInstance Win32_OperatingSystem | Select-Object '
      '-ExpandProperty FreePhysicalMemory';

  final MemoryProcessRunner _runner;
  final SystemMemoryPlatform _platform;

  Future<int?> availableBytes() async {
    try {
      return switch (_platform) {
        SystemMemoryPlatform.macOS => await _macOSAvailableBytes(),
        SystemMemoryPlatform.linux => await _linuxAvailableBytes(),
        SystemMemoryPlatform.windows => await _windowsAvailableBytes(),
      };
    } on ProcessException {
      return null;
    }
  }

  Future<int?> _macOSAvailableBytes() async {
    final pageSize = await _runner('sysctl', const ['-n', 'hw.pagesize']);
    final vmStat = await _runner('vm_stat', const []);
    if (pageSize.exitCode != 0 || vmStat.exitCode != 0) return null;
    final bytesPerPage = int.tryParse((pageSize.stdout as String).trim());
    final freePages = parseFreePages(vmStat.stdout as String);
    if (bytesPerPage == null || freePages == null) return null;
    return bytesPerPage * freePages;
  }

  Future<int?> _linuxAvailableBytes() async {
    final meminfo = await _runner('cat', const ['/proc/meminfo']);
    if (meminfo.exitCode != 0) return null;
    final kilobytes = parseMemAvailableKilobytes(meminfo.stdout as String);
    return kilobytes == null ? null : kilobytes * 1024;
  }

  Future<int?> _windowsAvailableBytes() async {
    final result = await _runner('powershell', const [
      '-NoProfile',
      '-Command',
      _windowsCommand,
    ]);
    if (result.exitCode != 0) return null;
    final kilobytes = parseFreePhysicalMemoryKilobytes(result.stdout as String);
    return kilobytes == null ? null : kilobytes * 1024;
  }

  static int? parseFreePages(String output) {
    final match = RegExp(r'Pages free:\s*(\d+)').firstMatch(output);
    final value = match?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  static int? parseMemAvailableKilobytes(String output) {
    final match = RegExp(r'MemAvailable:\s*(\d+)').firstMatch(output);
    final value = match?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  static int? parseFreePhysicalMemoryKilobytes(String output) =>
      int.tryParse(output.trim());

  static SystemMemoryPlatform _currentPlatform() {
    if (Platform.isWindows) return SystemMemoryPlatform.windows;
    if (Platform.isLinux) return SystemMemoryPlatform.linux;
    return SystemMemoryPlatform.macOS;
  }

  static Future<ProcessResult> _defaultRunner(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments);
}
