import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/mobile/widgets/android_soft_keyboard_backspace.dart';
import 'package:flutter_hbb/mobile/widgets/android_soft_keyboard_input.dart';
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
      expect(
          androidSoftKeyboardBackspaceValue(editing('1111')), editing('111'));
    });

    test('removes a stale trailing space', () {
      expect(androidSoftKeyboardBackspaceValue(editing('111word ')),
          editing('111word'));
    });

    test('removes a grapheme instead of a UTF-16 code unit', () {
      expect(
          androidSoftKeyboardBackspaceValue(editing('111😀')), editing('111'));
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
      expect(
          androidSoftKeyboardBackspaceValue(editing('111', offset: 0)), isNull);
      expect(
          androidSoftKeyboardBackspaceValue(editing('111', offset: 9)), isNull);
      expect(androidSoftKeyboardBackspaceValue(editing('111', offset: -1)),
          isNull);
      expect(
          androidSoftKeyboardBackspaceValue(const TextEditingValue(
            text: '111abc',
            selection: TextSelection(baseOffset: 3, extentOffset: 6),
          )),
          isNull);
    });
  });

  testWidgets('mixed IME and raw deletions followed by typing send no old text',
      (tester) async {
    final controller = TextEditingController.fromValue(editing('111'));
    final focus = FocusNode();
    final input = AndroidSoftKeyboardInput()..reset(controller.value);
    final actions = <String>[];
    final forwarded = <KeyEvent>[];

    controller.addListener(() {
      final edit = input.update(controller.value, send: focus.hasPrimaryFocus);
      actions.addAll(List.filled(edit.backspaces, 'VK_BACK'));
      if (edit.text.isNotEmpty) actions.add(edit.text);
    });

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
            onEmptyBackspace: () => actions.add('VK_BACK'),
            child: TextFormField(
              controller: controller,
              focusNode: focus,
            ),
          ),
        ),
      ),
    ));
    focus.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(editing('111x  '));
    tester.testTextInput.updateEditingValue(editing('111x '));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    expect(controller.text, '111x');
    expect(actions, ['x  ', 'VK_BACK', 'VK_BACK']);
    expect(forwarded, isEmpty);

    tester.testTextInput.updateEditingValue(editing('111xa'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(editing('111xab'));
    await tester.pump();
    expect(actions, ['x  ', 'VK_BACK', 'VK_BACK', 'a', 'b']);
    expect(forwarded, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    controller.dispose();
  });

  testWidgets('held Backspace deletes once per repeat; key-up is not forwarded',
      (tester) async {
    final controller = TextEditingController.fromValue(editing('1'));
    final focus = FocusNode();
    final forwarded = <KeyEvent>[];
    final changes = <String>[];
    controller.addListener(() => changes.add(controller.text));
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
            onEmptyBackspace: () => changes.add('VK_BACK'),
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
    expect(changes, ['', 'VK_BACK']);
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
    controller.addListener(() => changes.add(controller.text));
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
            onEmptyBackspace: () => changes.add('VK_BACK'),
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

  testWidgets('modified, denied and disabled Backspaces use the parent path',
      (tester) async {
    final controller = TextEditingController.fromValue(editing('111'));
    final focus = FocusNode();
    final forwarded = <KeyEvent>[];
    var allowed = true;
    var enabled = true;

    Widget editor() => MaterialApp(
          home: Focus(
            onKeyEvent: (_, event) {
              forwarded.add(event);
              return KeyEventResult.handled;
            },
            child: AndroidSoftKeyboardBackspaceGuard(
              enabled: enabled,
              controller: controller,
              canHandle: () => allowed,
              onEmptyBackspace: () => fail('unexpected Backspace'),
              child: Focus(focusNode: focus, child: const SizedBox.shrink()),
            ),
          ),
        );

    Future<void> backspace() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    }

    await tester.pumpWidget(editor());
    focus.requestFocus();
    await tester.pump();
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await backspace();
      await tester.sendKeyUpEvent(modifier);
    }
    allowed = false;
    await backspace();
    allowed = true;
    enabled = false;
    await tester.pumpWidget(editor());
    focus.requestFocus();
    await tester.pump();
    await backspace();

    final allBackspaces = forwarded
        .where((event) => event.logicalKey == LogicalKeyboardKey.backspace);
    expect(allBackspaces.whereType<KeyDownEvent>().length, 6);
    expect(allBackspaces.whereType<KeyUpEvent>().length, 6);
    expect(controller.text, '111');
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    controller.dispose();
  });

  test('decodes literal digits separately from padding and handles reset', () {
    final input = AndroidSoftKeyboardInput()..reset(editing('1111'));
    expect(input.update(editing('111'), send: true).backspaces, 1);
    expect(input.update(editing('1111'), send: true).text, '1');
    expect(input.update(editing('11111 ñáéíóú €?'), send: true).text,
        '1 ñáéíóú €?');
    input.reset(editing('1111'));
    expect(input.update(editing('1111 '), send: true).text, ' ');
  });

  test('decodes multi-delete and composition changes by grapheme', () {
    final input = AndroidSoftKeyboardInput()..reset(editing('1111'));
    final interim = editing('1111😀👩‍💻a\u0301',
        composing: const TextRange(start: 6, end: 13));
    expect(input.update(interim, send: true).text, '😀👩‍💻a\u0301');
    expect(input.update(editing(interim.text), send: false).isEmpty, isTrue);
    final deletion = input.update(editing('1111😀'), send: true);
    expect(deletion.backspaces, 2);
    expect(deletion.text, isEmpty);
  });

  test('replays a short typed suffix for insertions and replacements', () {
    final input = AndroidSoftKeyboardInput()..reset(editing('1111'));
    expect(input.update(editing('1111csa'), send: true).text, 'csa');
    expect(input.update(editing('1111csa', offset: 5), send: true).isEmpty,
        isTrue);
    final insert = input.update(editing('1111casa', offset: 6), send: true);
    expect((insert.backspaces, insert.text), (2, 'asa'));
    final selection = const TextEditingValue(
      text: '1111casa',
      selection: TextSelection(baseOffset: 7, extentOffset: 5),
    );
    expect(input.update(selection, send: true).isEmpty, isTrue);
    final replace = input.update(editing('1111cáza', offset: 7), send: true);
    expect((replace.backspaces, replace.text), (3, 'áza'));
    final autocorrect = input.update(editing('1111caza '), send: true);
    expect((autocorrect.backspaces, autocorrect.text), (3, 'aza '));
  });

  test('select all and replace keeps a literal leading 1', () {
    final original = const TextEditingValue(
      text: '1111',
      selection: TextSelection(baseOffset: 0, extentOffset: 4),
    );
    final input = AndroidSoftKeyboardInput()..reset(original);
    final replace = input.update(editing('1a'), send: true);
    expect((replace.backspaces, replace.text), (0, '1a'));
  });

  test('a composition starting with a combining mark sends no padding', () {
    final input = AndroidSoftKeyboardInput()..reset(editing('1111'));
    final edit = input.update(editing('1111\u0301x'), send: true);
    expect((edit.backspaces, edit.text), (0, '\u0301x'));
  });

  test('invalidated cursor and modifiers block corrective Backspaces', () {
    final input = AndroidSoftKeyboardInput()..reset(editing('1111'));
    input.update(editing('1111abc'), send: true);
    input.invalidateReplay();
    final deleteInMiddle =
        input.update(editing('1111ac', offset: 5), send: true);
    expect(deleteInMiddle.isEmpty, isTrue);
    input.reset(editing('1111'));
    input.update(editing('1111abc def'), send: true);
    final correction =
        input.update(editing('1111abc Def'), send: true, allowReplay: false);
    expect(correction.isEmpty, isTrue);
    final modifiedDelete =
        input.update(editing('1111abc '), send: true, allowReplay: false);
    expect(modifiedDelete.backspaces, 1);
  });

  test('blocked edits do not replay when permission or focus returns', () {
    final input = AndroidSoftKeyboardInput()..reset(editing('1111'));
    expect(input.update(editing('1111blocked'), send: false).isEmpty, isTrue);
    expect(input.update(editing('1111blockedñ'), send: true).text, 'ñ');
    input.invalidateReplay();
    expect(input.update(editing('1111replaced'), send: true).isEmpty, isTrue);
  });

  test('dispatcher waits for every operation and skips work after close',
      () async {
    final dispatcher = AndroidSoftKeyboardDispatcher();
    final deletion = Completer<void>();
    final finish = Completer<void>();
    final calls = <String>[];
    dispatcher.send(() async {
      calls.add('backspace');
      await deletion.future;
    });
    dispatcher.send(() async {
      calls.add('ñ');
      finish.complete();
    });
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['backspace']);
    deletion.complete();
    await finish.future;
    expect(calls, ['backspace', 'ñ']);
    dispatcher.send(() async => calls.add('unexpected'));
    dispatcher.close();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['backspace', 'ñ']);
  });
}
