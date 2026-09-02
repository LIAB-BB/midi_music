import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';

void main() {
  test('消息根必须是对象', () {
    expect(() => ScoreRendererMessage.parse('[]'), throwsFormatException);
    expect(() => ScoreRendererMessage.parse('"ready"'), throwsFormatException);
  });

  test('只接受已知消息与有限手势数据', () {
    final message = ScoreRendererMessage.parse(
      '{"type":"gestureEnd","x":120.5,"y":240,'
      '"travel":4,"durationMs":120,"pointerCount":1}',
    );

    expect(message.type, ScoreRendererMessageType.gestureEnd);
    expect(message.tapX, 120.5);
    expect(message.tapY, 240);
    expect(message.gestureTravel, 4);
    expect(message.gestureDurationMs, 120);
    expect(message.gesturePointerCount, 1);
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"gestureEnd","x":-1,"y":20,'
        '"travel":4,"durationMs":120,"pointerCount":1}',
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"gestureEnd","x":1e400,"y":20,'
        '"travel":4,"durationMs":120,"pointerCount":1}',
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"gestureEnd","x":20,"y":20,'
        '"travel":4,"durationMs":60001,"pointerCount":1}',
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"gestureEnd","x":20,"y":20,'
        '"travel":4,"durationMs":120,"pointerCount":0}',
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse('{"type":"navigate","url":"https://x"}'),
      throwsFormatException,
    );
  });

  test('整数槽拒绝 bool 与整数值 double', () {
    for (final invalid in ['true', '1.0']) {
      expect(
        () => ScoreRendererMessage.parse(
          '{"type":"gestureEnd","x":20,"y":20,"travel":4,'
          '"durationMs":$invalid,"pointerCount":1}',
        ),
        throwsFormatException,
      );
      expect(
        () => ScoreRendererMessage.parse(
          '{"type":"gestureEnd","x":20,"y":20,"travel":4,'
          '"durationMs":120,"pointerCount":$invalid}',
        ),
        throwsFormatException,
      );
      expect(
        () => ScoreRendererMessage.parse(
          '{"type":"layout","complete":true,"measures":['
          '{"ordinal":$invalid,"left":0,"top":0,'
          '"width":10,"height":10}]}',
        ),
        throwsFormatException,
      );
    }
  });

  test('布局消息返回经校验的小节矩形', () {
    final message = ScoreRendererMessage.parse(
      '{"type":"layout","complete":true,"measures":['
      '{"ordinal":1,"left":10,"top":20,"width":100,"height":80}] }',
    );

    expect(message.layoutComplete, isTrue);
    expect(message.measureRects, const [
      ScoreMeasureRect(ordinal: 1, left: 10, top: 20, width: 100, height: 80),
    ]);
  });

  test('布局消息拒绝重复、越界和超量矩形', () {
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"layout","complete":true,"measures":['
        '{"ordinal":1,"left":0,"top":0,"width":10,"height":10},'
        '{"ordinal":1,"left":10,"top":0,"width":10,"height":10}]}',
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"layout","complete":true,"measures":['
        '{"ordinal":1,"left":0,"top":0,"width":0,"height":10}]}',
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"layout","complete":true,"measures":['
        '{"ordinal":100001,"left":0,"top":0,"width":10,"height":10}]}',
      ),
      throwsFormatException,
    );
    final tooManyMeasures = List<Map<String, Object>>.generate(
      10001,
      (index) => {
        'ordinal': index + 1,
        'left': 0,
        'top': 0,
        'width': 10,
        'height': 10,
      },
    );
    expect(
      () => ScoreRendererMessage.parse(
        jsonEncode({
          'type': 'layout',
          'complete': true,
          'measures': tooManyMeasures,
        }),
      ),
      throwsFormatException,
    );
  });

  test('布局消息拒绝 NaN 等效无穷值与范围外有限值', () {
    for (final field in ['left', 'top', 'width', 'height']) {
      expect(
        () => ScoreRendererMessage.parse(
          '{"type":"layout","complete":true,"measures":['
          '{"ordinal":1,"left":1,"top":1,"width":10,"height":10,'
          '"$field":1e400}]}',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => ScoreRendererMessage.parse(
        '{"type":"layout","complete":true,"measures":['
        '{"ordinal":1,"left":10000001,"top":0,'
        '"width":10,"height":10}]}',
      ),
      throwsFormatException,
    );
  });

  test('错误消息长度与文本受限', () {
    final message = ScoreRendererMessage.parse(
      '{"type":"error","message":"bad score"}',
    );

    expect(message.errorMessage, 'bad score');
    expect(
      () => ScoreRendererMessage.parse(
        jsonEncode({
          'type': 'error',
          'message': List<String>.filled(501, 'x').join(),
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => ScoreRendererMessage.parse('{"type":"error","message":""}'),
      throwsFormatException,
    );
  });

  test('消息总字节数接受上限并拒绝多一个字节', () {
    const maximumBytes = 2 * 1024 * 1024;
    const prefix = '{"type":"ready","padding":"';
    const suffix = '"}';
    const paddingLength = maximumBytes - prefix.length - suffix.length;
    final atLimit = '$prefix${''.padRight(paddingLength, 'x')}$suffix';

    expect(utf8.encode(atLimit), hasLength(maximumBytes));
    expect(
      ScoreRendererMessage.parse(atLimit),
      const ScoreRendererMessage.ready(),
    );
    expect(
      () => ScoreRendererMessage.parse('$atLimit '),
      throwsFormatException,
    );
  });

  test('ready 与值对象相等性保持稳定', () {
    expect(
      ScoreRendererMessage.parse('{"type":"ready"}'),
      const ScoreRendererMessage.ready(),
    );
    expect(
      const ScoreMeasureRect(
        ordinal: 1,
        left: 0,
        top: 0,
        width: 10,
        height: 10,
      ).contains(10, 10),
      isTrue,
    );
  });
}
