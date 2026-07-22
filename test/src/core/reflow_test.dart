import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/reflow.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/utils/circular_buffer.dart';

void main() {
  test('reflow() can reflow a single line', () {
    final terminal = Terminal();

    terminal.write('1234567890abcdefg');
    terminal.resize(10, 10);

    expect(terminal.buffer.lines[0].toString(), '1234567890');
    expect(terminal.buffer.lines[1].toString(), 'abcdefg');
    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);

    terminal.resize(13, 10);

    expect(terminal.buffer.lines[0].toString(), '1234567890abc');
    expect(terminal.buffer.lines[1].toString(), 'defg');
    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);

    terminal.resize(20, 10);

    expect(terminal.buffer.lines[0].toString(), '1234567890abcdefg');
    expect(terminal.buffer.lines[0].isWrapped, isFalse);
  });

  test('reflow() can reflow a single line to multiple lines', () {
    final terminal = Terminal();

    terminal.write('1234567890abcdefg');
    terminal.resize(5, 10);

    expect(terminal.buffer.lines[0].toString(), '12345');
    expect(terminal.buffer.lines[1].toString(), '67890');
    expect(terminal.buffer.lines[2].toString(), 'abcde');
    expect(terminal.buffer.lines[3].toString(), 'fg');

    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);
    expect(terminal.buffer.lines[2].isWrapped, isTrue);
    expect(terminal.buffer.lines[3].isWrapped, isTrue);

    terminal.resize(6, 10);

    expect(terminal.buffer.lines[0].toString(), '123456');
    expect(terminal.buffer.lines[1].toString(), '7890ab');
    expect(terminal.buffer.lines[2].toString(), 'cdefg');

    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);
    expect(terminal.buffer.lines[2].isWrapped, isTrue);
  });

  test('reflow() can reflow wide characters', () {
    final terminal = Terminal();

    terminal.write('床前明月光疑是地上霜');
    terminal.resize(10, 10);

    expect(terminal.buffer.lines[0].toString(), '床前明月光');
    expect(terminal.buffer.lines[1].toString(), '疑是地上霜');

    terminal.resize(9, 10);

    expect(terminal.buffer.lines[0].toString(), '床前明月');
    expect(terminal.buffer.lines[1].toString(), '光疑是地');
    expect(terminal.buffer.lines[2].toString(), '上霜');

    terminal.resize(11, 10);

    expect(terminal.buffer.lines[0].toString(), '床前明月光');
    expect(terminal.buffer.lines[1].toString(), '疑是地上霜');

    terminal.resize(13, 10);
    expect(terminal.buffer.lines[0].toString(), '床前明月光疑');
    expect(terminal.buffer.lines[1].toString(), '是地上霜');
  });

  test('reflow() handles a wide character in the final old column', () {
    final lines = IndexAwareCircularBuffer<BufferLine>(10);
    final line = BufferLine(64)..setCodePoint(63, 0x754c);
    final wrappedContinuation = BufferLine(64)..isWrapped = true;
    final continuationAnchor = wrappedContinuation.createAnchor(0);
    lines
      ..push(line)
      ..push(wrappedContinuation);

    final result = reflow(lines, 64, 63);

    expect(result, hasLength(2));
    expect(result[0].toString(), isEmpty);
    expect(result[1].toString(), '\u754c');
    expect(result[1].isWrapped, isTrue);
    expect(result[1].getWidth(0), 2);
    expect(continuationAnchor.line, same(result[1]));
    expect(continuationAnchor.x, 1);

    lines.replaceWith(result);
    expect(continuationAnchor.attached, isTrue);
    expect(continuationAnchor.y, 1);
  });

  test('reflow() makes progress when shrinking a wide character to one column',
      () {
    final lines = IndexAwareCircularBuffer<BufferLine>(10)
      ..push(BufferLine(2)..setCodePoint(0, 0x754c));

    final result = reflow(lines, 2, 1);

    expect(result, isNotEmpty);
    expect(result.every((line) => line.length == 1), isTrue);
    expect(result.any((line) => line.getCodePoint(0) == 0x754c), isTrue);
  });

  test('lines has correct length after reflow', () {
    final terminal = Terminal();

    terminal.write('1234567890abcdefg');
    terminal.resize(10, 10);

    for (var i = 0; i < 10; i++) {
      expect(terminal.buffer.lines[i].length, 10);
    }

    terminal.resize(13, 10);
    for (var i = 0; i < 10; i++) {
      expect(terminal.buffer.lines[i].length, 13);
    }
  });
}
