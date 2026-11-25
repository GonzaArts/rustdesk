import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The local edit corresponding to one non-composing Backspace key event.
///
/// Samsung Keyboard and some other Android IMEs sometimes send Backspace as
/// a key event rather than an InputConnection text edit. Forwarding that event
/// without editing the hidden field leaves stale characters at its end. The
/// legacy length-based diff then forwards those characters instead of new text.
/// See rustdesk/rustdesk#17066 and the device traces in #14495.
TextEditingValue? androidSoftKeyboardBackspaceValue(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.start <= 0 ||
      selection.end > value.text.length ||
      !value.composing.isCollapsed) {
    return null;
  }
  final caret = CharacterRange.at(value.text, selection.start);
  if (caret.stringBeforeLength != selection.start) return null;
  final remaining = caret.stringBefore.characters.skipLast(1).string;
  return TextEditingValue(
    text: remaining + value.text.substring(selection.end),
    selection: TextSelection.collapsed(offset: remaining.length),
  );
}

/// Intercepts raw Backspace events from the focused Android soft-keyboard
/// editor before they bubble to RawKeyFocusScope. Mirrored edits go through the
/// same controller listener as edits from the IME.
class AndroidSoftKeyboardBackspaceGuard extends StatefulWidget {
  const AndroidSoftKeyboardBackspaceGuard({
    super.key,
    required this.enabled,
    required this.controller,
    required this.canHandle,
    required this.onEmptyBackspace,
    required this.child,
  });

  final bool enabled;
  final TextEditingController controller;
  final bool Function() canHandle;
  final VoidCallback onEmptyBackspace;
  final Widget child;

  @override
  State<AndroidSoftKeyboardBackspaceGuard> createState() =>
      _AndroidSoftKeyboardBackspaceGuardState();
}

class _AndroidSoftKeyboardBackspaceGuardState
    extends State<AndroidSoftKeyboardBackspaceGuard> {
  // Only consume the release of a key whose down event we consumed. Otherwise
  // a Backspace forwarded by the parent could be left pressed remotely.
  PhysicalKeyboardKey? _ownedBackspace;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      if (_ownedBackspace != event.physicalKey) return KeyEventResult.ignored;
      _ownedBackspace = null;
      return KeyEventResult.handled;
    }
    final repeat = event is KeyRepeatEvent;
    if (repeat && _ownedBackspace != event.physicalKey) {
      return KeyEventResult.ignored;
    }
    if (!repeat) _ownedBackspace = null;

    final keyboard = HardwareKeyboard.instance;
    if (!widget.canHandle() ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed ||
        event.synthesized) {
      return repeat ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    final value = widget.controller.value;
    final corrected = androidSoftKeyboardBackspaceValue(value);
    final empty = value.text.isEmpty &&
        value.selection == const TextSelection.collapsed(offset: 0) &&
        value.composing.isCollapsed;
    if (corrected == null && !empty) {
      return repeat ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    _ownedBackspace = event.physicalKey;
    if (corrected != null) {
      widget.controller.value = corrected;
    } else {
      widget.onEmptyBackspace();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) _ownedBackspace = null;
      },
      onKeyEvent: _handleKey,
      child: widget.child,
    );
  }
}
