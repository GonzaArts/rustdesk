import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show CharacterRange, StringCharacters;

class AndroidSoftKeyboardEdit {
  const AndroidSoftKeyboardEdit({this.backspaces = 0, this.text = ''});

  final int backspaces;
  final String text;

  bool get isEmpty => backspaces == 0 && text.isEmpty;
}

/// Interprets local Android IME edits while the remote caret is at the end of
/// the text typed in this editor. The leading padding exists only in Flutter.
class AndroidSoftKeyboardInput {
  static const _maxBackspaces = 64;

  TextEditingValue _previous = TextEditingValue.empty;
  int _padding = 0;
  int _replayStart = 0;

  void reset(TextEditingValue value) {
    _previous = value;
    _padding = _replayStart = value.text.characters.length;
  }

  void invalidateReplay() {
    _replayStart = _previous.text.characters.length;
  }

  AndroidSoftKeyboardEdit update(TextEditingValue value,
      {required bool send, bool allowReplay = true}) {
    final previous = _previous;
    _previous = value;
    // Flutter also clears composition on blur, without changing the text.
    // Android IMEs can mark ordinary typing as composing, so mirror live text.
    if (previous.text == value.text) return const AndroidSoftKeyboardEdit();

    final oldText = previous.text.characters.toList();
    final newText = value.text.characters.toList();
    if (oldText.isNotEmpty &&
        oldText.length == _padding &&
        newText.length >= _padding &&
        newText[_padding - 1] != oldText.last &&
        value.text.startsWith(previous.text)) {
      // A leading combining mark can join the last padding grapheme.
      invalidateReplay();
      return send
          ? AndroidSoftKeyboardEdit(
              text: value.text.substring(previous.text.length))
          : const AndroidSoftKeyboardEdit();
    }
    final (start, suffix) = _changedSpan(previous, value, oldText, newText);
    final removedEnd = oldText.length - suffix;
    final inserted = newText.sublist(start, newText.length - suffix).join();
    final oldPadding = _padding;
    final inPadding = start < oldPadding;
    if (inPadding) _padding = start;
    if (!send) {
      invalidateReplay();
      return const AndroidSoftKeyboardEdit();
    }
    if (!allowReplay) invalidateReplay();

    if (start == oldText.length) {
      return AndroidSoftKeyboardEdit(text: inserted);
    }
    if (suffix == 0 && inserted.isEmpty) {
      final count = oldText.length - (inPadding ? oldPadding : start);
      // The IME asked to delete past the text we typed. One Backspace still
      // lets the user continue deleting pre-existing text on the host.
      final backspaces = allowReplay ? count + (inPadding ? 1 : 0) : 1;
      if (allowReplay) {
        _replayStart = backspaces > _maxBackspaces
            ? newText.length
            : math.min(_replayStart, start);
      }
      return AndroidSoftKeyboardEdit(
          backspaces: math.min(backspaces, _maxBackspaces));
    }

    final tailLength = oldText.length - start;
    if (allowReplay &&
        start >= _replayStart &&
        tailLength <= _maxBackspaces &&
        oldText.skip(start).every(_canReplay)) {
      return AndroidSoftKeyboardEdit(
        backspaces: tailLength,
        text: inserted + newText.skip(newText.length - suffix).join(),
      );
    }

    // The remote protocol cannot target a local selection or an arbitrary
    // caret. Avoid deleting unknown text or replaying padding/control keys.
    _replayStart = newText.length;
    if (removedEnd == start || inPadding) {
      return AndroidSoftKeyboardEdit(text: inserted);
    }
    return const AndroidSoftKeyboardEdit();
  }

  static bool _canReplay(String grapheme) =>
      grapheme.runes.length == 1 && grapheme.codeUnitAt(0) >= 0x20;

  static (int, int) _changedSpan(
    TextEditingValue previous,
    TextEditingValue value,
    List<String> oldText,
    List<String> newText,
  ) {
    final oldSelection = previous.selection;
    final newSelection = value.selection;
    var start = oldSelection.start;
    final end = oldSelection.end;
    if (oldSelection.isCollapsed &&
        newSelection.isCollapsed &&
        newSelection.start < start &&
        previous.text.length - value.text.length ==
            start - newSelection.start) {
      start = newSelection.start;
    }
    if (start >= 0 &&
        start <= end &&
        end <= previous.text.length &&
        CharacterRange.at(previous.text, start).stringBeforeLength == start &&
        CharacterRange.at(previous.text, end).stringBeforeLength == end) {
      final before = previous.text.substring(0, start);
      final after = previous.text.substring(end);
      if (before.length + after.length <= value.text.length &&
          value.text.startsWith(before) &&
          value.text.endsWith(after)) {
        final prefix = before.characters.length;
        final suffix = after.characters.length;
        if (prefix + suffix <= newText.length &&
            newText.take(prefix).join() == before &&
            newText.skip(newText.length - suffix).join() == after) {
          return (prefix, suffix);
        }
      }
    }

    var prefix = 0;
    var suffix = 0;
    final limit = math.min(oldText.length, newText.length);
    while (prefix < limit && oldText[prefix] == newText[prefix]) {
      prefix++;
    }
    while (prefix + suffix < limit &&
        oldText[oldText.length - 1 - suffix] ==
            newText[newText.length - 1 - suffix]) {
      suffix++;
    }
    return (prefix, suffix);
  }
}

/// Flutter Rust Bridge workers may execute calls out of order. Await each
/// call before dispatching the next one to the connection.
class AndroidSoftKeyboardDispatcher {
  Future<void> _pending = Future<void>.value();
  bool _closed = false;

  void send(Future<void> Function() operation) {
    if (_closed) return;
    _pending = _pending.then((_) async {
      if (_closed) return;
      try {
        await operation();
      } catch (error) {
        debugPrint('Android soft keyboard send failed (${error.runtimeType})');
      }
    });
  }

  void close() => _closed = true;
}
