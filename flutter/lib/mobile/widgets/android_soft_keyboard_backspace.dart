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
  final before = value.text.substring(0, selection.start);
  final remaining = before.characters.skipLast(1).string;
  return TextEditingValue(
    text: remaining + value.text.substring(selection.end),
    selection: TextSelection.collapsed(offset: remaining.length),
  );
}

/// Intercepts raw Backspace events from the focused Android soft-keyboard
/// editor before they bubble to RawKeyFocusScope. Only the legacy text-change
/// path dispatches the resulting VK_BACK, so a deletion is never sent twice.
/// Other platforms and all other keys retain the existing path.
class AndroidSoftKeyboardBackspaceGuard extends StatefulWidget {
  const AndroidSoftKeyboardBackspaceGuard({
    super.key,
    required this.enabled,
    required this.controller,
    required this.canHandle,
    required this.onChanged,
    required this.child,
  });

  final bool enabled;
  final TextEditingController controller;
  final bool Function() canHandle;
  final ValueChanged<String> onChanged;
  final Widget child;

  @override
  State<AndroidSoftKeyboardBackspaceGuard> createState() =>
      _AndroidSoftKeyboardBackspaceGuardState();
}

class _AndroidSoftKeyboardBackspaceGuardState
    extends State<AndroidSoftKeyboardBackspaceGuard> {
  // Only consume the release of a key whose down event we consumed. Otherwise
  // a Backspace forwarded by the parent could be left pressed remotely.
  bool _ownsBackspace = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      final owned = _ownsBackspace;
      _ownsBackspace = false;
      return owned ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _ownsBackspace = false;
    } else if (event is! KeyRepeatEvent || !_ownsBackspace) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (!widget.canHandle() ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final corrected = androidSoftKeyboardBackspaceValue(widget.controller.value);
    if (corrected == null) {
      // Active composition, selection, or exhausted padding: preserve the
      // existing handling. Repeated events use the parent's press path.
      return KeyEventResult.ignored;
    }

    _ownsBackspace = true;
    // A programmatic controller write does not invoke TextField.onChanged.
    // Explicitly invoke the same callback exactly once, after local editing.
    widget.controller.value = corrected;
    widget.onChanged(corrected.text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: widget.child,
    );
  }
}
