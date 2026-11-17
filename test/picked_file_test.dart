import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_tracker/utils/picked_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.tempPath);
  final String tempPath;
  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

/// What Android's picker can return since file_picker 12: a `content://`
/// uri with no path on disk, readable only as bytes.
final class _ContentFile extends PlatformFile {
  _ContentFile(this.name, this.bytes);
  @override
  final String name;
  final Uint8List bytes;
  @override
  Uri get uri => Uri.parse('content://downloads/1');
  @override
  get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() async* {
    // In small chunks, so the size cap is exercised across chunk edges.
    for (var i = 0; i < bytes.length; i += 3) {
      yield bytes.sublist(i, i + 3 > bytes.length ? bytes.length : i + 3);
    }
  }
}

class _FakePicker extends FilePickerPlatform with MockPlatformInterfaceMixin {
  PlatformFile? next;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      next;
}

void main() {
  late Directory temp;
  late _FakePicker picker;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('picked_file_test');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    picker = _FakePicker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => temp.delete(recursive: true));

  test('a cancelled pick is null', () async {
    expect(await pickLocalFile(), isNull);
  });

  test('a file with no path is copied, so restore can read it', () async {
    picker.next = _ContentFile(
        'backup.json', Uint8List.fromList('{"version":7}'.codeUnits));
    final path = await pickLocalFile();
    expect(path, startsWith(temp.path));
    expect(await File(path!).readAsString(), '{"version":7}');
  });

  test('a copy stops one byte past the cap, so the size check still trips',
      () async {
    picker.next = _ContentFile('big.csv', Uint8List(100));
    final path = await pickLocalFile(maxBytes: 10);
    expect(await File(path!).length(), 11);
  });

  test('a name cannot write outside the temporary folder', () async {
    picker.next = _ContentFile('../../evil.csv', Uint8List(1));
    final path = await pickLocalFile();
    expect(File(path!).parent.path, temp.path);
  });
}
