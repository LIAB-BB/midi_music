import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/k478_practice.dart';
import 'package:k478_practice/src/core/follow_mode_controller.dart';

void main() {
  testWidgets('候选 host 显示 K.478 入口', (tester) async {
    await tester.pumpWidget(const K478PracticeApp());
    expect(find.text('K.478 排练'), findsOneWidget);
    expect(find.textContaining('钢琴四重奏'), findsOneWidget);
  });

  testWidgets('可从首页进入 21 页钢琴分谱阅读', (tester) async {
    await tester.pumpWidget(const K478PracticeApp());
    await tester.pump();

    await tester.tap(find.text('查看钢琴声部版面'));
    await tester.pumpAndSettle();

    expect(find.text('钢琴声部 · 1/21'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('三倍文本缩放下候选首页仍可构建', (tester) async {
    await tester.pumpWidget(
      const K478PracticeApp(textScalerOverride: TextScaler.linear(3)),
    );
    await tester.pump();

    // 导航栏标题会被 Cupertino 按系统规则限制缩放；验证首页正文确实
    // 收到了三倍 Dynamic Type，而不是仅靠页面可构建来声称覆盖。
    final displayTitle = find.text('钢琴四重奏\nK.478');
    expect(displayTitle, findsOneWidget);
    final textScaler = MediaQuery.textScalerOf(tester.element(displayTitle));
    expect(textScaler.scale(10), 30);
    expect(tester.takeException(), isNull);
  });

  test('USB 状态随拔出和重连更新，不把会话存在误作已连接', () {
    final disconnected = midiConnectionPresentation(
      sessionActive: true,
      isConnected: false,
      followState: FollowModeState.following,
    );
    final reconnected = midiConnectionPresentation(
      sessionActive: true,
      isConnected: true,
      primaryDeviceName: 'Digital Piano',
      followState: FollowModeState.following,
    );

    expect(disconnected.healthy, isFalse);
    expect(disconnected.label, 'CoreMIDI · 未检测到设备');
    expect(reconnected.healthy, isTrue);
    expect(reconnected.label, 'Digital Piano · 跟随中');
  });

  test('MIDI Session 启动中即锁住手动 transport', () {
    expect(
      isFollowTransportLocked(isStartingFollow: true, sessionActive: false),
      isTrue,
    );
    expect(
      isFollowTransportLocked(isStartingFollow: false, sessionActive: true),
      isTrue,
    );
    expect(
      isFollowTransportLocked(isStartingFollow: false, sessionActive: false),
      isFalse,
    );
  });
}
