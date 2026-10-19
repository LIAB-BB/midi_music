import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/follow_phase.dart';

void main() {
  test('相位误差在死区内不修正', () {
    expect(correctFollowSpeed(1.0, 0.02), 1.0);
    expect(correctFollowSpeed(1.0, -0.02), 1.0);
  });

  test('伴奏超前时减速，落后时加速', () {
    expect(correctFollowSpeed(1.0, 0.2), lessThan(1.0));
    expect(correctFollowSpeed(1.0, -0.2), greaterThan(1.0));
  });

  test('修正幅度被限制在 ±4%', () {
    expect(correctFollowSpeed(1.0, 10), closeTo(0.96, 1e-9));
    expect(correctFollowSpeed(1.0, -10), closeTo(1.04, 1e-9));
  });

  test('修正后仍限制在播放器速度范围内', () {
    expect(correctFollowSpeed(2.0, -10), lessThanOrEqualTo(2.0));
    expect(correctFollowSpeed(0.25, 10), greaterThanOrEqualTo(0.25));
  });
}
