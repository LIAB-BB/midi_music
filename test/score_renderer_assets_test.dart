import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OSMD 与许可证随 Flutter asset bundle 打包', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/opensheetmusicdisplay.min.js',
    );
    final license = await rootBundle.loadString(
      'assets/score_renderer/LICENSE',
    );

    expect(script, contains('OpenSheetMusicDisplay'));
    expect(license, contains('Copyright 2019 PhonicScore'));
    expect(license, contains('Redistribution and use'));
  });
}
