import 'dart:io';

import 'package:denial_flutter_sdk/applications.dart' show RuntimePaths;
import 'package:denial_flutter_sdk/theme.dart' show IconThemeRepository;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('denial-icon-themes');
  });

  tearDown(() {
    home.deleteSync(recursive: true);
  });

  test('reads each installed theme label from its index.theme', () async {
    final light = Directory('${dataHome(home)}/icons/Colloid-Light')
      ..createSync(recursive: true);
    File('${light.path}/index.theme').writeAsStringSync('''
[Icon Theme]
Name=Colloid Light
Comment=Flat clean style icon theme for linux.
''');
    final broken = Directory('${dataHome(home)}/icons/NotATheme')
      ..createSync(recursive: true);
    broken.createSync();

    final themes = await repository(home).discover();

    expect(themes.map((theme) => theme.id), <String>['Colloid-Light']);
    expect(themes.single.name, 'Colloid Light');
    expect(themes.single.path, light.path);
  });

  test('a missing Name falls back to no theme rather than a blank label', () async {
    final theme = Directory('${dataHome(home)}/icons/Unnamed')
      ..createSync(recursive: true);
    File('${theme.path}/index.theme').writeAsStringSync('[Icon Theme]\nComment=No name\n');

    expect(await repository(home).discover(), isEmpty);
  });

  test('lists themes from the system data directories after the user ones', () async {
    for (final entry in <String, String>{
      '${dataHome(home)}/icons/UserTheme': 'User Theme',
      '${home.path}/system/icons/SystemTheme': 'System Theme',
    }.entries) {
      final theme = Directory(entry.key)..createSync(recursive: true);
      File(
        '${theme.path}/index.theme',
      ).writeAsStringSync('[Icon Theme]\nName=${entry.value}\n');
    }

    final themes = await IconThemeRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': home.path,
          'XDG_DATA_DIRS': '${home.path}/system',
        },
      ),
    ).discover();

    expect(themes.map((theme) => theme.id), <String>[
      'SystemTheme',
      'UserTheme',
    ]);
  });
}

String dataHome(Directory home) => '${home.path}/.local/share';

IconThemeRepository repository(Directory home) {
  return IconThemeRepository(
    paths: RuntimePaths(
      environment: <String, String>{
        'HOME': home.path,
        'XDG_DATA_DIRS': '',
      },
    ),
  );
}
