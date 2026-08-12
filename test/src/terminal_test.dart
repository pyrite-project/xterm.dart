import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Terminal cursor shape', () {
    test('uses the view fallback until DECSCUSR selects a shape', () {
      final terminal = Terminal();

      expect(terminal.cursorType, isNull);

      terminal.write('\x1b[2 q');
      expect(terminal.cursorType, TerminalCursorType.block);

      terminal.write('\x1b[4 q');
      expect(terminal.cursorType, TerminalCursorType.underline);

      terminal.write('\x1b[6 q');
      expect(terminal.cursorType, TerminalCursorType.verticalBar);

      terminal.write('\x1b[0 q');
      expect(terminal.cursorType, isNull);
    });

    test('ignores unsupported DECSCUSR values', () {
      final terminal = Terminal();

      terminal.write('\x1b[2 q\x1b[99 q');

      expect(terminal.cursorType, TerminalCursorType.block);
    });

    test('parses a DECSCUSR sequence split across writes', () {
      final terminal = Terminal();

      terminal.write('\x1b[2 ');
      terminal.write('q');

      expect(terminal.cursorType, TerminalCursorType.block);
    });
  });

  group('Terminal true color', () {
    test('stores RGB foreground and background on cells', () {
      final terminal = Terminal();

      terminal.write('\x1b[38;2;12;34;56;48:2::78:90:123mX');

      final line = terminal.buffer.lines[0];
      expect(line.getForeground(0) & CellColor.typeMask, CellColor.rgb);
      expect(line.getForeground(0) & CellColor.valueMask, 0x0c2238);
      expect(line.getBackground(0) & CellColor.typeMask, CellColor.rgb);
      expect(line.getBackground(0) & CellColor.valueMask, 0x4e5a7b);
    });

    test('resets RGB foreground and background independently', () {
      final terminal = Terminal();

      terminal.write(
        '\x1b[38;2;12;34;56;48;2;78;90;123mX'
        '\x1b[39mY\x1b[49mZ',
      );

      final line = terminal.buffer.lines[0];
      expect(line.getForeground(1) & CellColor.typeMask, CellColor.normal);
      expect(line.getBackground(1) & CellColor.typeMask, CellColor.rgb);
      expect(line.getForeground(2) & CellColor.typeMask, CellColor.normal);
      expect(line.getBackground(2) & CellColor.typeMask, CellColor.normal);
    });
  });

  group('Terminal.inputHandler', () {
    test('can be set to null', () {
      final terminal = Terminal(inputHandler: null);
      expect(() => terminal.keyInput(TerminalKey.keyA), returnsNormally);
    });

    test('can be changed', () {
      final handler1 = _TestInputHandler();
      final handler2 = _TestInputHandler();
      final terminal = Terminal(inputHandler: handler1);

      terminal.keyInput(TerminalKey.keyA);
      expect(handler1.events, isNotEmpty);

      terminal.inputHandler = handler2;

      terminal.keyInput(TerminalKey.keyA);
      expect(handler2.events, isNotEmpty);
    });
  });

  group('Terminal.mouseInput', () {
    test('can handle mouse events', () {
      final output = <String>[];

      final terminal = Terminal(onOutput: output.add);

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, isEmpty);

      // enable mouse reporting
      terminal.write('\x1b[?1000h');

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, ['\x1B[M +,']);
    });
  });

  group('Terminal.reflowEnabled', () {
    test('prevents reflow when set to false', () {
      final terminal = Terminal(reflowEnabled: false);

      terminal.write('Hello World');
      terminal.resize(5, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('preserves hidden cells when reflow is disabled', () {
      final terminal = Terminal(reflowEnabled: false);

      terminal.write('Hello World');
      terminal.resize(5, 5);
      terminal.resize(20, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello World');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('can be set at runtime', () {
      final terminal = Terminal(reflowEnabled: true);

      terminal.resize(5, 5);
      terminal.write('Hello World');
      terminal.reflowEnabled = false;
      terminal.resize(20, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello');
      expect(terminal.buffer.lines[1].toString(), ' Worl');
      expect(terminal.buffer.lines[2].toString(), 'd');
    });
  });

  group('Terminal.mouseInput', () {
    test('applys to the main buffer', () {
      final terminal = Terminal(
        wordSeparators: {
          'z'.codeUnitAt(0),
        },
      );

      expect(
        terminal.mainBuffer.wordSeparators,
        contains('z'.codeUnitAt(0)),
      );
    });

    test('applys to the alternate buffer', () {
      final terminal = Terminal(
        wordSeparators: {
          'z'.codeUnitAt(0),
        },
      );

      expect(
        terminal.altBuffer.wordSeparators,
        contains('z'.codeUnitAt(0)),
      );
    });
  });

  group('Terminal.onPrivateOSC', () {
    test(r'works with \a end', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]6\x07');

      expect(lastCode, '6');
      expect(lastData, []);

      terminal.write('\x1b]66;hello world\x07');

      expect(lastCode, '66');
      expect(lastData, ['hello world']);

      terminal.write('\x1b]666;hello;world\x07');

      expect(lastCode, '666');
      expect(lastData, ['hello', 'world']);

      terminal.write('\x1b]hello;world\x07');

      expect(lastCode, 'hello');
      expect(lastData, ['world']);
    });

    test(r'works with \x1b\ end', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]6\x1b\\');

      expect(lastCode, '6');
      expect(lastData, []);

      terminal.write('\x1b]66;hello world\x1b\\');

      expect(lastCode, '66');
      expect(lastData, ['hello world']);

      terminal.write('\x1b]666;hello;world\x1b\\');

      expect(lastCode, '666');
      expect(lastData, ['hello', 'world']);

      terminal.write('\x1b]hello;world\x1b\\');

      expect(lastCode, 'hello');
      expect(lastData, ['world']);
    });

    test('do not receive common osc', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]0;hello world\x07');

      expect(lastCode, isNull);
      expect(lastData, isNull);
    });
  });
}

class _TestInputHandler implements TerminalInputHandler {
  final events = <TerminalKeyboardEvent>[];

  @override
  String? call(TerminalKeyboardEvent event) {
    events.add(event);
    return null;
  }
}
