import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(textStyle.getTextStyle(textScaler: _textScaler));
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, offset.dy + _cellSize.height - 1),
          Offset(
            offset.dx + _cellSize.width,
            offset.dy + _cellSize.height - 1,
          ),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          offset,
          Offset(offset.dx, offset.dy + _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset = offset.translate(
      length * _cellSize.width,
      _cellSize.height,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromPoints(offset, endOffset), paint);
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(Canvas canvas, Offset offset, BufferLine line) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;

    // Backgrounds remain cell-based even when foreground glyphs are shaped
    // together as a run.
    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);
      final cellOffset = offset.translate(i * cellWidth, 0);
      paintCellBackground(canvas, cellOffset, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      if (charWidth == 2) i++;
    }

    if (!_textStyle.enableLigatures) {
      for (var i = 0; i < line.length; i++) {
        line.getCellData(i, cellData);
        paintCellForeground(
          canvas,
          offset.translate(i * cellWidth, 0),
          cellData,
        );
        if (cellData.content >> CellContent.widthShift == 2) i++;
      }
      return;
    }

    for (var i = 0; i < line.length;) {
      line.getCellData(i, cellData);
      final cellOffset = offset.translate(i * cellWidth, 0);
      final charWidth = cellData.content >> CellContent.widthShift;

      if (!_isLigatureCell(cellData, charWidth)) {
        paintCellForeground(canvas, cellOffset, cellData);
        i += charWidth == 2 ? 2 : 1;
        continue;
      }

      final runStart = i;
      final runStyle = _copyCellData(cellData);
      final text = StringBuffer();
      while (i < line.length) {
        line.getCellData(i, cellData);
        if (!_isLigatureCell(
              cellData,
              cellData.content >> CellContent.widthShift,
            ) ||
            !_sameShapingStyle(cellData, runStyle)) {
          break;
        }
        text.writeCharCode(cellData.content & CellContent.codepointMask);
        i++;
      }

      _paintTextRun(
        canvas,
        offset.translate(runStart * cellWidth, 0),
        text.toString(),
        runStyle,
        i - runStart,
      );
    }
  }

  /// Returns the adjacent printable runs that are eligible for shaping.
  ///
  /// This avoids platform-specific raster comparisons in rendering tests.
  List<String> debugLigatureRuns(BufferLine line) {
    if (!_textStyle.enableLigatures) return const [];

    final runs = <String>[];
    final cellData = CellData.empty();
    for (var i = 0; i < line.length;) {
      line.getCellData(i, cellData);
      final width = cellData.content >> CellContent.widthShift;
      if (!_isLigatureCell(cellData, width)) {
        i += width == 2 ? 2 : 1;
        continue;
      }

      final runStyle = _copyCellData(cellData);
      final text = StringBuffer();
      while (i < line.length) {
        line.getCellData(i, cellData);
        if (!_isLigatureCell(
              cellData,
              cellData.content >> CellContent.widthShift,
            ) ||
            !_sameShapingStyle(cellData, runStyle)) {
          break;
        }
        text.writeCharCode(cellData.content & CellContent.codepointMask);
        i++;
      }
      runs.add(text.toString());
    }
    return runs;
  }

  CellData _copyCellData(CellData value) => CellData(
        foreground: value.foreground,
        background: value.background,
        flags: value.flags,
        content: value.content,
      );

  bool _sameShapingStyle(CellData a, CellData b) =>
      a.foreground == b.foreground &&
      a.background == b.background &&
      a.flags == b.flags;

  bool _isLigatureCell(CellData cellData, int charWidth) {
    final charCode = cellData.content & CellContent.codepointMask;
    // Programming ligatures are visible ASCII punctuation sequences. Keeping
    // this path narrow preserves the existing behavior for CJK, combining
    // marks, spaces, and box-drawing glyphs.
    return charWidth == 1 && charCode >= 0x21 && charCode <= 0x7e;
  }

  void _paintTextRun(
    Canvas canvas,
    Offset offset,
    String text,
    CellData cellData,
    int cellCount,
  ) {
    final cellFlags = cellData.flags;
    final inverse = cellFlags & CellFlags.inverse != 0;
    var color = inverse
        ? resolveBackgroundColor(cellData.background)
        : resolveForegroundColor(cellData.foreground);
    final background = inverse
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);
    color = ensureTerminalContrast(
      color,
      background,
      _theme.minimumContrastRatio,
    );
    if (cellFlags & CellFlags.faint != 0) {
      color = color.withValues(alpha: 0.5);
    }

    final style = _textStyle.toTextStyle(
      color: color,
      bold: cellFlags & CellFlags.bold != 0,
      italic: cellFlags & CellFlags.italic != 0,
      underline: cellFlags & CellFlags.underline != 0,
    );
    final width = cellCount * _cellSize.width;
    final cacheKey = Object.hash(
      text,
      cellData.foreground,
      cellData.background,
      cellData.flags,
      width,
      _textScaler,
    );
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);
    paragraph ??= _paragraphCache.performAndCacheLayout(
      text,
      style,
      _textScaler,
      cacheKey,
      width: width,
    );

    canvas.save();
    canvas.clipRect(offset & Size(width, _cellSize.height));
    canvas.drawParagraph(paragraph, offset);
    canvas.restore();
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final cellFlags = cellData.flags;
    final inverse = cellFlags & CellFlags.inverse != 0;
    var color = inverse
        ? resolveBackgroundColor(cellData.background)
        : resolveForegroundColor(cellData.foreground);
    final background = inverse
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);
    color = ensureTerminalContrast(
      color,
      background,
      _theme.minimumContrastRatio,
    );

    if (cellFlags & CellFlags.faint != 0) {
      color = color.withValues(alpha: 0.5);
    }

    if (_paintGeneratedGlyph(canvas, offset, charCode, color)) return;

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final underline = cellFlags & CellFlags.underline != 0 &&
          !_skipUnderlineDecoration(charCode);

      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: underline,
      );

      var char = String.fromCharCode(charCode);

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  bool _paintGeneratedGlyph(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    return _paintPowerlineSymbol(canvas, offset, charCode, color) ||
        _paintBlockElement(canvas, offset, charCode, color) ||
        _paintBoxDrawing(canvas, offset, charCode, color);
  }

  bool _paintPowerlineSymbol(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    if (charCode < 0xe0b0 || charCode > 0xe0b3) return false;

    // Same rule as the block elements: a translucent separator must not be
    // bled into its neighbour, or the overlap doubles its alpha and leaves a
    // visible seam between two cells of the same separator run.
    final bleed = color.a >= 1.0 ? 0.75 : 0.0;
    final cellLeft = offset.dx;
    final cellRight = offset.dx + _cellSize.width;
    final cellTop = offset.dy;
    final cellBottom = offset.dy + _cellSize.height;
    final left = cellLeft - bleed;
    final right = cellRight + bleed;
    final top = cellTop - bleed;
    final bottom = cellBottom + bleed;
    final centerY = offset.dy + _cellSize.height / 2;
    final path = Path();

    switch (charCode) {
      case 0xe0b0: // powerline right separator
      case 0xe0b1: // powerline right separator thin
        path
          ..moveTo(left, top)
          ..lineTo(right, centerY)
          ..lineTo(left, bottom);
        break;
      case 0xe0b2: // powerline left separator
      case 0xe0b3: // powerline left separator thin
        path
          ..moveTo(right, top)
          ..lineTo(left, centerY)
          ..lineTo(right, bottom);
        break;
    }

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    if (charCode == 0xe0b0 || charCode == 0xe0b2) {
      path.close();
      paint.style = PaintingStyle.fill;
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter
        ..strokeWidth = (_cellSize.width / 8).clamp(1.0, 2.0).toDouble();
    }

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(left, cellTop, right, cellBottom),
      doAntiAlias: false,
    );
    canvas.drawPath(path, paint);
    canvas.restore();
    return true;
  }

  bool _paintBlockElement(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    if (charCode < 0x2580 || charCode > 0x259f) return false;

    // The half pixel bleed keeps neighbouring opaque blocks seamless, but it
    // makes adjacent translucent blocks overlap. Two 50% rects over each other
    // composite to 75%, so a faint (dimmed) block row came out as bright
    // stripes at every cell boundary — exactly what happens to the top row of
    // a block-art logo drawn with the faint attribute. Bleed only when the
    // colour is opaque; translucent blocks still meet on the exact same
    // fractional edge, so no gap opens up.
    final bleed = color.a >= 1.0 ? 0.5 : 0.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;

    // One path per cell: the pieces of a quadrant glyph overlap each other, and
    // separate draw calls would composite that overlap twice as well.
    final path = Path();

    void addRect(double left, double top, double right, double bottom) {
      var l = offset.dx + _cellSize.width * left;
      var t = offset.dy + _cellSize.height * top;
      var r = offset.dx + _cellSize.width * right;
      var b = offset.dy + _cellSize.height * bottom;
      if (left == 0) l -= bleed;
      if (top == 0) t -= bleed;
      if (right == 1) r += bleed;
      if (bottom == 1) b += bleed;
      path.addRect(Rect.fromLTRB(l, t, r, b));
    }

    switch (charCode) {
      case 0x2580: // upper half block
        addRect(0, 0, 1, 0.5);
        break;
      case 0x2581: // lower one eighth block
        addRect(0, 0.875, 1, 1);
        break;
      case 0x2582: // lower one quarter block
        addRect(0, 0.75, 1, 1);
        break;
      case 0x2583: // lower three eighths block
        addRect(0, 0.625, 1, 1);
        break;
      case 0x2584: // lower half block
        addRect(0, 0.5, 1, 1);
        break;
      case 0x2585: // lower five eighths block
        addRect(0, 0.375, 1, 1);
        break;
      case 0x2586: // lower three quarters block
        addRect(0, 0.25, 1, 1);
        break;
      case 0x2587: // lower seven eighths block
        addRect(0, 0.125, 1, 1);
        break;
      case 0x2588: // full block
        addRect(0, 0, 1, 1);
        break;
      case 0x2589: // left seven eighths block
        addRect(0, 0, 0.875, 1);
        break;
      case 0x258a: // left three quarters block
        addRect(0, 0, 0.75, 1);
        break;
      case 0x258b: // left five eighths block
        addRect(0, 0, 0.625, 1);
        break;
      case 0x258c: // left half block
        addRect(0, 0, 0.5, 1);
        break;
      case 0x258d: // left three eighths block
        addRect(0, 0, 0.375, 1);
        break;
      case 0x258e: // left one quarter block
        addRect(0, 0, 0.25, 1);
        break;
      case 0x258f: // left one eighth block
        addRect(0, 0, 0.125, 1);
        break;
      case 0x2590: // right half block
        addRect(0.5, 0, 1, 1);
        break;
      case 0x2591: // light shade
      case 0x2592: // medium shade
      case 0x2593: // dark shade
        paint.color = color.withValues(
          alpha: switch (charCode) {
            0x2591 => 0.25,
            0x2592 => 0.5,
            _ => 0.75,
          },
        );
        addRect(0, 0, 1, 1);
        break;
      case 0x2594: // upper one eighth block
        addRect(0, 0, 1, 0.125);
        break;
      case 0x2595: // right one eighth block
        addRect(0.875, 0, 1, 1);
        break;
      case 0x2596: // quadrant lower left
        addRect(0, 0.5, 0.5, 1);
        break;
      case 0x2597: // quadrant lower right
        addRect(0.5, 0.5, 1, 1);
        break;
      case 0x2598: // quadrant upper left
        addRect(0, 0, 0.5, 0.5);
        break;
      case 0x2599: // quadrant upper left and lower half
        addRect(0, 0, 0.5, 1);
        addRect(0.5, 0.5, 1, 1);
        break;
      case 0x259a: // quadrant upper left and lower right
        addRect(0, 0, 0.5, 0.5);
        addRect(0.5, 0.5, 1, 1);
        break;
      case 0x259b: // quadrant upper half and lower left
        addRect(0, 0, 1, 0.5);
        addRect(0, 0.5, 0.5, 1);
        break;
      case 0x259c: // quadrant upper half and lower right
        addRect(0, 0, 1, 0.5);
        addRect(0.5, 0.5, 1, 1);
        break;
      case 0x259d: // quadrant upper right
        addRect(0.5, 0, 1, 0.5);
        break;
      case 0x259e: // quadrant upper right and lower left
        addRect(0.5, 0, 1, 0.5);
        addRect(0, 0.5, 0.5, 1);
        break;
      case 0x259f: // quadrant upper right and lower half
        addRect(0.5, 0, 1, 1);
        addRect(0, 0.5, 0.5, 1);
        break;
      default:
        return false;
    }

    canvas.drawPath(path, paint);
    return true;
  }

  bool _paintBoxDrawing(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    if (_paintRoundedBoxDrawing(canvas, offset, charCode, color)) return true;

    final connections = _boxDrawingConnections(charCode);
    if (connections == 0) return false;

    final strokeWidth = (_cellSize.height / 12).clamp(1.0, 1.5).toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = false;

    // Butt-capped segments meet at the exact cell boundary without producing
    // the periodic overlap visible on long horizontal or vertical lines.
    final left = offset.dx;
    final right = offset.dx + _cellSize.width;
    final top = offset.dy;
    final bottom = offset.dy + _cellSize.height;
    final centerX = offset.dx + _cellSize.width / 2;
    final centerY = offset.dy + _cellSize.height / 2;

    if (connections & _boxLeft != 0) {
      canvas.drawLine(Offset(left, centerY), Offset(centerX, centerY), paint);
    }
    if (connections & _boxRight != 0) {
      canvas.drawLine(Offset(centerX, centerY), Offset(right, centerY), paint);
    }
    if (connections & _boxUp != 0) {
      canvas.drawLine(Offset(centerX, top), Offset(centerX, centerY), paint);
    }
    if (connections & _boxDown != 0) {
      canvas.drawLine(Offset(centerX, centerY), Offset(centerX, bottom), paint);
    }

    return true;
  }

  bool _paintRoundedBoxDrawing(
    Canvas canvas,
    Offset offset,
    int charCode,
    Color color,
  ) {
    if (charCode < 0x256d || charCode > 0x2570) return false;

    final strokeWidth = (_cellSize.height / 12).clamp(1.0, 1.5).toDouble();
    final edgeBleed = strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final left = offset.dx - edgeBleed;
    final right = offset.dx + _cellSize.width + edgeBleed;
    final top = offset.dy - edgeBleed;
    final bottom = offset.dy + _cellSize.height + edgeBleed;
    final centerX = offset.dx + _cellSize.width / 2;
    final centerY = offset.dy + _cellSize.height / 2;
    final cornerRadius = (_cellSize.width / 3).clamp(2.5, 4.0).toDouble();
    final halfStroke = strokeWidth / 2;

    Path ringQuarter(Offset center, double startAngle) {
      final outerRadius = cornerRadius + halfStroke;
      final innerRadius = cornerRadius - halfStroke;
      const sweepAngle = math.pi / 2;
      final endAngle = startAngle + sweepAngle;
      final path = Path()
        ..moveTo(
          center.dx + math.cos(startAngle) * outerRadius,
          center.dy + math.sin(startAngle) * outerRadius,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: outerRadius),
          startAngle,
          sweepAngle,
          false,
        )
        ..lineTo(
          center.dx + math.cos(endAngle) * innerRadius,
          center.dy + math.sin(endAngle) * innerRadius,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: innerRadius),
          endAngle,
          -sweepAngle,
          false,
        )
        ..close();
      return path;
    }

    Path combine(Path corner, Rect horizontal, Rect vertical) {
      return Path.combine(
        PathOperation.union,
        Path.combine(
          PathOperation.union,
          corner,
          Path()..addRect(horizontal),
        ),
        Path()..addRect(vertical),
      );
    }

    late final Path path;

    switch (charCode) {
      case 0x256d: // ╭
        final cornerCenter = Offset(
          centerX + cornerRadius,
          centerY + cornerRadius,
        );
        path = combine(
          ringQuarter(cornerCenter, math.pi),
          Rect.fromLTRB(
            cornerCenter.dx,
            centerY - halfStroke,
            right,
            centerY + halfStroke,
          ),
          Rect.fromLTRB(
            centerX - halfStroke,
            cornerCenter.dy,
            centerX + halfStroke,
            bottom,
          ),
        );
        break;
      case 0x256e: // ╮
        final cornerCenter = Offset(
          centerX - cornerRadius,
          centerY + cornerRadius,
        );
        path = combine(
          ringQuarter(cornerCenter, math.pi * 1.5),
          Rect.fromLTRB(
            left,
            centerY - halfStroke,
            cornerCenter.dx,
            centerY + halfStroke,
          ),
          Rect.fromLTRB(
            centerX - halfStroke,
            cornerCenter.dy,
            centerX + halfStroke,
            bottom,
          ),
        );
        break;
      case 0x256f: // ╯
        final cornerCenter = Offset(
          centerX - cornerRadius,
          centerY - cornerRadius,
        );
        path = combine(
          ringQuarter(cornerCenter, 0),
          Rect.fromLTRB(
            left,
            centerY - halfStroke,
            cornerCenter.dx,
            centerY + halfStroke,
          ),
          Rect.fromLTRB(
            centerX - halfStroke,
            top,
            centerX + halfStroke,
            cornerCenter.dy,
          ),
        );
        break;
      case 0x2570: // ╰
        final cornerCenter = Offset(
          centerX + cornerRadius,
          centerY - cornerRadius,
        );
        path = combine(
          ringQuarter(cornerCenter, math.pi / 2),
          Rect.fromLTRB(
            cornerCenter.dx,
            centerY - halfStroke,
            right,
            centerY + halfStroke,
          ),
          Rect.fromLTRB(
            centerX - halfStroke,
            top,
            centerX + halfStroke,
            cornerCenter.dy,
          ),
        );
        break;
    }

    canvas.drawPath(path, paint);
    return true;
  }

  static const _boxLeft = 1;
  static const _boxRight = 1 << 1;
  static const _boxUp = 1 << 2;
  static const _boxDown = 1 << 3;

  int _boxDrawingConnections(int charCode) {
    switch (charCode) {
      case 0x2500: // ─
      case 0x2550: // ═
        return _boxLeft | _boxRight;
      case 0x2574: // ╴
        return _boxLeft;
      case 0x2502: // │
      case 0x2551: // ║
        return _boxUp | _boxDown;
      case 0x250c: // ┌
      case 0x2554: // ╔
        return _boxRight | _boxDown;
      case 0x2510: // ┐
      case 0x2557: // ╗
        return _boxLeft | _boxDown;
      case 0x2514: // └
      case 0x255a: // ╚
        return _boxRight | _boxUp;
      case 0x2518: // ┘
      case 0x255d: // ╝
        return _boxLeft | _boxUp;
      case 0x251c: // ├
      case 0x2560: // ╠
        return _boxUp | _boxDown | _boxRight;
      case 0x2524: // ┤
      case 0x2563: // ╣
        return _boxUp | _boxDown | _boxLeft;
      case 0x252c: // ┬
      case 0x2566: // ╦
        return _boxLeft | _boxRight | _boxDown;
      case 0x2534: // ┴
      case 0x2569: // ╩
        return _boxLeft | _boxRight | _boxUp;
      case 0x253c: // ┼
      case 0x256c: // ╬
        return _boxLeft | _boxRight | _boxUp | _boxDown;
      default:
        return 0;
    }
  }

  bool _skipUnderlineDecoration(int charCode) {
    if (charCode == 0x20 || charCode == 0x3000) return true;

    // Box drawing glyphs already represent UI lines. Applying a text underline
    // creates a second line below Claude-style terminal panels.
    return charCode >= 0x2500 && charCode <= 0x257f;
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
