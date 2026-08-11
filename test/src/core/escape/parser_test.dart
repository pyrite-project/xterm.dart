import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

@GenerateNiceMocks([MockSpec<EscapeHandler>()])
import 'parser_test.mocks.dart';

void main() {
  group('EscapeParser', () {
    test('can parse window manipulation', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[8;24;80t');
      verify(parser.handler.resize(80, 24));
    });

    test('parses semicolon true color for foreground and background', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[38;2;12;34;56;48;2;78;90;123m');

      verify(handler.setForegroundColorRgb(12, 34, 56)).called(1);
      verify(handler.setBackgroundColorRgb(78, 90, 123)).called(1);
    });

    test('parses colon true color with optional color-space slot', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[38:2::12:34:56;48:2:0:78:90:123m');

      verify(handler.setForegroundColorRgb(12, 34, 56)).called(1);
      verify(handler.setBackgroundColorRgb(78, 90, 123)).called(1);
    });

    test('parses compact colon true color and palette color', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[38:2:12:34:56;48:5:123m');

      verify(handler.setForegroundColorRgb(12, 34, 56)).called(1);
      verify(handler.setBackgroundColor256(123)).called(1);
    });

    test('ignores incomplete and out-of-range extended colors', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      expect(
        () => parser.write(
          '\x1b[38m\x1b[48;2;1m\x1b[38;2;256;0;0m'
          '\x1b[48:2::0:0:999m',
        ),
        returnsNormally,
      );
      verifyNever(handler.setForegroundColorRgb(any, any, any));
      verifyNever(handler.setBackgroundColorRgb(any, any, any));
    });
  });
}
