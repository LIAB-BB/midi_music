import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 主 Manifest 包含 release 下载 SoundFont 所需网络权限', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason: 'release 包首次运行需要下载 SoundFont，权限不能只存在于 debug/profile Manifest。',
    );
  });
}
