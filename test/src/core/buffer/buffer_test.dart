import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Buffer.getText()', () {
    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.getText(), startsWith('Hello World'));
    });

    test('can handle line wrap', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      final line1 = 'This is a long line that should wrap';
      final line2 = 'This is a short line';
      final line3 = 'This is a long long long long line that should wrap';
      final line4 = 'Short';

      terminal.write('$line1\r\n');
      terminal.write('$line2\r\n');
      terminal.write('$line3\r\n');
      terminal.write('$line4\r\n');

      final lines = terminal.buffer.getText().split('\n');
      expect(lines[0], line1);
      expect(lines[1], line2);
      expect(lines[2], line3);
      expect(lines[3], line4);
    });

    test('can handle negative start', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(-100, -100), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle invalid end', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(0, 0), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle reversed range', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(5, 5), CellOffset(0, 0)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle block range', () {
      final terminal = Terminal();

      terminal.write('Hello World\r\n');
      terminal.write('Nice to meet you\r\n');

      expect(
        terminal.buffer.getText(
          BufferRangeBlock(CellOffset(2, 0), CellOffset(5, 1)),
        ),
        startsWith('llo\nce '),
      );
    });
  });

  group('Buffer.resize()', () {
    test('should resize the buffer', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      expect(terminal.viewWidth, 10);
      expect(terminal.viewHeight, 10);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 10);
      }

      terminal.resize(20, 20);

      expect(terminal.viewWidth, 20);
      expect(terminal.viewHeight, 20);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 20);
      }
    });

    test('keeps the cursor valid when reflowing a trailing wide character', () {
      final terminal = Terminal(maxLines: 10000)..resize(64, 10);
      for (var i = 0; i < 30; i++) {
        terminal.write('line $i\r\n');
      }
      terminal.write('\x1b[10;64H');
      terminal.buffer.currentLine.setCodePoint(63, 0x754c);
      terminal.buffer
        ..index()
        ..setCursorX(1);
      terminal.buffer.currentLine.isWrapped = true;

      expect(() => terminal.resize(63, 16), returnsNormally);
      expect(terminal.viewWidth, 63);
      expect(terminal.viewHeight, 16);
      expect(terminal.buffer.cursorY, inInclusiveRange(0, 15));
      expect(terminal.buffer.absoluteCursorY, lessThan(terminal.buffer.height));
      expect(terminal.buffer.getText(), contains('\u754c'));
      expect(() => terminal.write('x'), returnsNormally);
    });

    test('rolls back height growth when width reflow fails', () {
      final terminal = Terminal()..resize(10, 10);
      terminal.buffer.lines[0] = _ThrowingBufferLine(10);

      expect(() => terminal.resize(9, 16), throwsStateError);
      expect(terminal.viewHeight, 10);
      expect(terminal.buffer.height, 10);
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.altBuffer.height, 10);
      expect(terminal.altBuffer.lines[0].length, 10);
      expect(() => terminal.write('x'), returnsNormally);
    });

    test('rolls back height shrink when width reflow fails', () {
      final terminal = Terminal()..resize(10, 10);
      terminal.buffer.lines[0] = _ThrowingBufferLine(10);

      expect(() => terminal.resize(9, 5), throwsStateError);
      expect(terminal.viewHeight, 10);
      expect(terminal.buffer.height, 10);
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.altBuffer.height, 10);
      expect(terminal.altBuffer.lines[0].length, 10);
      expect(() => terminal.write('x'), returnsNormally);
    });
  });

  group('Buffer.writeChar()', () {
    test('wraps a wide character before the final column', () {
      final terminal = Terminal()
        ..resize(4, 3)
        ..write('123\u754c');

      expect(terminal.buffer.lines[0].toString(), '123');
      expect(terminal.buffer.lines[1].toString(), '\u754c');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.lines[1].getWidth(0), 2);
    });

    test('does not split a wide character in a one-column viewport', () {
      final terminal = Terminal()
        ..resize(1, 2)
        ..write('\u754c');

      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.lines[0].getCodePoint(0), 0x754c);
      expect(terminal.buffer.lines[1].getCodePoint(0), 0);

      expect(() => terminal.resize(2, 2), returnsNormally);
      expect(terminal.buffer.getText(), contains('\u754c'));
    });
  });

  group('Buffer.restoreCursor()', () {
    test('clamps a DECSC cursor after the viewport shrinks', () {
      final terminal = Terminal()
        ..resize(80, 30)
        ..write('\x1b[30;1H\x1b7')
        ..resize(80, 25);

      expect(() => terminal.write('\x1b8x'), returnsNormally);
      expect(terminal.buffer.cursorY, terminal.viewHeight - 1);
      expect(terminal.buffer.currentLine.toString(), 'x');
    });

    test('clamps a DEC mode 1048 cursor after the viewport shrinks', () {
      final terminal = Terminal()
        ..resize(80, 30)
        ..write('\x1b[30;1H\x1b[?1048h')
        ..resize(80, 25);

      expect(() => terminal.write('\x1b[?1048lx'), returnsNormally);
      expect(terminal.buffer.cursorY, terminal.viewHeight - 1);
      expect(terminal.buffer.currentLine.toString(), 'x');
    });

    test('clamps a saved column after the viewport narrows', () {
      final content = List.filled(80, 'x').join();
      final terminal = Terminal()
        ..resize(80, 5)
        ..write('$content\x1b[1;80H\x1b7')
        ..resize(40, 5);

      expect(() => terminal.write('\x1b8\x1b[K'), returnsNormally);
      expect(terminal.buffer.cursorY, 0);
    });

    test('preserves pending wrap when width does not change', () {
      final terminal = Terminal()
        ..resize(5, 5)
        ..write('12345\x1b7')
        ..resize(5, 4)
        ..write('\r\x1b8x');

      expect(terminal.buffer.cursorY, 1);
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(
        terminal.buffer.lines[1].getCodePoint(0),
        'x'.codeUnitAt(0),
      );
    });
  });

  group('Buffer.deleteLines()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      for (var i = 1; i <= 10; i++) {
        terminal.write('line$i');

        if (i < 10) {
          terminal.write('\r\n');
        }
      }

      terminal.setMargins(3, 7);
      terminal.setCursor(0, 5);

      terminal.buffer.deleteLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line3');
      expect(terminal.buffer.lines[3].toString(), 'line4');
      expect(terminal.buffer.lines[4].toString(), 'line5');
      expect(terminal.buffer.lines[5].toString(), 'line7');
      expect(terminal.buffer.lines[6].toString(), 'line8');
      expect(terminal.buffer.lines[7].toString(), '');
      expect(terminal.buffer.lines[8].toString(), 'line9');
      expect(terminal.buffer.lines[9].toString(), 'line10');
    });
  });

  group('Buffer.insertLines()', () {
    test('works', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      print(terminal.buffer);

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 4);

      print(terminal.buffer.absoluteCursorY);

      terminal.buffer.insertLines(1);

      print(terminal.buffer);

      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), ''); // inserted
      expect(terminal.buffer.lines[5].toString(), 'line4'); // moved
      expect(terminal.buffer.lines[6].toString(), 'line5'); // moved
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });

    test('has no effect if cursor is out of scroll region', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 1);

      terminal.buffer.insertLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line2');
      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), 'line4');
      expect(terminal.buffer.lines[5].toString(), 'line5');
      expect(terminal.buffer.lines[6].toString(), 'line6');
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });
  });

  group('Buffer.getWordBoundary supports custom word separators', () {
    test('can set word separators', () {
      final terminal = Terminal(wordSeparators: {'o'.codeUnitAt(0)});

      terminal.write('Hello World');

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(0, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(4, 0)),
      );

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(5, 0)),
        BufferRangeLine(CellOffset(5, 0), CellOffset(7, 0)),
      );
    });
  });

  test('does not delete lines beyond the scroll region', () {
    final terminal = Terminal();
    terminal.resize(10, 10);

    for (var i = 1; i <= 10; i++) {
      terminal.write('line$i');

      if (i < 10) {
        terminal.write('\r\n');
      }
    }

    terminal.setMargins(3, 7);
    terminal.setCursor(0, 5);

    terminal.buffer.deleteLines(20);

    expect(terminal.buffer.lines[2].toString(), 'line3');
    expect(terminal.buffer.lines[3].toString(), 'line4');
    expect(terminal.buffer.lines[4].toString(), 'line5');
    expect(terminal.buffer.lines[5].toString(), '');
    expect(terminal.buffer.lines[6].toString(), '');
    expect(terminal.buffer.lines[7].toString(), '');
    expect(terminal.buffer.lines[8].toString(), 'line9');
    expect(terminal.buffer.lines[9].toString(), 'line10');
  });

  group('Buffer.eraseDisplayFromCursor()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(3, 3);
      terminal.write('123\r\n456\r\n789');

      terminal.setCursor(1, 1);
      terminal.buffer.eraseDisplayFromCursor();

      expect(terminal.buffer.lines[0].toString(), '123');
      expect(terminal.buffer.lines[1].toString(), '4');
      expect(terminal.buffer.lines[2].toString(), '');
    });
  });
}

class _ThrowingBufferLine extends BufferLine {
  _ThrowingBufferLine(int length) : super(length);

  @override
  int getTrimmedLength([int? cols]) {
    throw StateError('forced reflow failure');
  }
}
