import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/mobile/widgets/android_soft_keyboard_backspace.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue editing(String text, {int? offset, TextRange? composing}) =>
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset ?? text.length),
      composing: composing ?? TextRange.empty,
    );

void main() {
  group('androidSoftKeyboardBackspaceValue', () {
    test('removes the sentinel before the first typed character', () {
      expect(androidSoftKeyboardBackspaceValue(editing('1111')), editing('111'));
    });

    test('removes a stale trailing space', () {
      expect(androidSoftKeyboardBackspaceValue(editing('111word ')),
          editing('111word'));
    });

    test('removes a grapheme instead of a UTF-16 code unit', () {
      expect(androidSoftKeyboardBackspaceValue(editing('111😀')), editing('111'));
      expect(androidSoftKeyboardBackspaceValue(editing('111a\u0301')),
          editing('111'));
    });

    test('retains the suffix if the local caret is not at the end', () {
      expect(androidSoftKeyboardBackspaceValue(editing('111xy', offset: 4)),
          editing('111y', offset: 3));
    });

    test('leaves active composition, selections and invalid carets alone', () {
      expect(
          androidSoftKeyboardBackspaceValue(
              editing('111a', composing: const TextRange(start: 3, end: 4))),
          isNull);
      expect(androidSoftKeyboardBackspaceValue(editing('111', offset: 0)), isNull);
      expect(androidSoftKeyboardBackspaceValue(editing('111', offset: 9)), isNull);
      expect(androidSoftKeyboardBackspaceValue(editing('111', offset: -1)), isNull);
      expect(
          androidSoftKeyboardBackspaceValue(const TextEditingValue(
            text: '111abc',
            selection: TextSelection(baseOffset: 3, extentOffset: 6),
          )),
          isNull);
    });
  });

  testWidgets('raw Backspace is mirrored once, then normal typing still works',
      (tester) async {
    final controller = TextEditingController.fromValue(editing('111x '));
    final focus = FocusNode();
    var old = controller.text;
    final actions = <String>[];
    final forwarded = <KeyEvent>[];

    // Reproduce the current remote page's append/delete diff, without FFI.
    void changed(String text) {
      if (text.length < old.length) {
        actions.add('VK_BACK');
      } else if (text.length > old.length) {
        actions.add(text.substring(old.length));
      }
      old = text;
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            forwarded.add(event);
            return KeyEventResult.handled;
          },
          child: AndroidSoftKeyboardBackspaceGuard(
            enabled: true,
            controller: controller,
            canHandle: () => true,
            onChanged: changed,
            child: TextField(
              controller: controller,
              focusNode: focus,
              onChanged: changed,
            ),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    expect(controller.text, '111x');
    expect(actions, ['VK_BACK']);
    expect(forwarded, isEmpty);

    tester.testTextInput.updateEditingValue(editing('111xa'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(editing('111xab'));
    await tester.pump();
    expect(actions, ['VK_BACK', 'a', 'b']);
    expect(forwarded, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    controller.dispose();
  });

  testWidgets('held Backspace deletes once per repeat; key-up is not forwarded',
      (tester) async {
    final controller = TextEditingController.fromValue(editing('1111'));
    final focus = FocusNode();
    final forwarded = <KeyEvent>[];
    final changes = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            forwarded.add(event);
            return KeyEventResult.handled;
          },
          child: AndroidSoftKeyboardBackspaceGuard(
            enabled: true,
            controller: controller,
            canHandle: () => true,
            onChanged: changes.add,
            child: Focus(focusNode: focus, child: const SizedBox.shrink()),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    expect(changes, ['111', '11']);
    expect(forwarded, isEmpty);

    // A normal key still bubbles to the parent's remote keyboard handler.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    expect(forwarded.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    controller.dispose();
  });

  testWidgets('composing Backspace down and up retain the parent key path',
      (tester) async {
    final controller = TextEditingController.fromValue(
        editing('111a', composing: const TextRange(start: 3, end: 4)));
    final focus = FocusNode();
    final forwarded = <KeyEvent>[];
    final changes = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            forwarded.add(event);
            return KeyEventResult.handled;
          },
          child: AndroidSoftKeyboardBackspaceGuard(
            enabled: true,
            controller: controller,
            canHandle: () => true,
            onChanged: changes.add,
            child: Focus(focusNode: focus, child: const SizedBox.shrink()),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    expect(changes, isEmpty);
    expect(forwarded.length, 2);
    expect(controller.text, '111a');
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    controller.dispose();
  });
}
