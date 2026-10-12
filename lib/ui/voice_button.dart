import 'package:flutter/material.dart';
import 'package:namer_app/services/voice_text.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/responsive.dart';

/// A 🎤 button that types what you say into [controller], live, using the
/// browser's own speech recognition. Hidden where the browser can't do it
/// (e.g. Firefox), so it never appears and then fails.
///
/// What you say is added after anything already typed, and nothing is sent
/// or looked up automatically: you can check and fix it first.
class VoiceButton extends StatefulWidget {
  final TextEditingController controller;

  /// Tidies the final words (e.g. [VoiceText.foodsFromSpeech] turns
  /// "eggs and toast" into "eggs, toast"). Interim words show as heard.
  final String Function(String spoken)? tidy;

  /// Put between what was already typed and what's said (", " for foods).
  final String joiner;

  /// Called once listening ends and the text is in place.
  final VoidCallback? onDone;

  /// Called after [onDone] with what was said (tidied), when anything was
  /// heard: e.g. to turn spoken foods straight into items.
  final ValueChanged<String>? onHeard;

  final String tooltip;
  final double iconSize;

  /// Greyed out (e.g. while Coach is replying).
  final bool enabled;

  const VoiceButton({
    super.key,
    required this.controller,
    this.tidy,
    this.joiner = ' ',
    this.onDone,
    this.onHeard,
    this.tooltip = 'Speak instead of typing',
    this.iconSize = 24,
    this.enabled = true,
  });

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  web.SpeechSession? _session;
  String _before = '';

  /// The latest words heard, and whether they've been tidied (final).
  String _heard = '';
  bool _tidied = false;

  bool get _listening => _session != null;

  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _listening) _stop();
  }

  @override
  void dispose() {
    _session?.stop();
    _session = null;
    super.dispose();
  }

  void _write(String spoken) {
    final before = _before;
    final String text;
    if (before.isEmpty) {
      text = spoken;
    } else if (spoken.isEmpty) {
      text = before;
    } else {
      final sep = before.endsWith(',') ? ' ' : widget.joiner;
      text = '$before$sep$spoken';
    }
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _start() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    _before = widget.controller.text.trimRight();
    _heard = '';
    _tidied = false;
    final session = web.startSpeech(
      onText: (text, done) {
        if (!mounted) return;
        final tidy = widget.tidy;
        _heard = done && tidy != null ? tidy(text) : text;
        _tidied = done || tidy == null;
        _write(_heard);
      },
      onEnd: (error) {
        if (!mounted) return;
        // Stopped before the browser called it final: tidy what we have.
        final tidy = widget.tidy;
        if (!_tidied && tidy != null && _heard.isNotEmpty) {
          _heard = tidy(_heard);
          _tidied = true;
          _write(_heard);
        }
        setState(() => _session = null);
        final message = VoiceText.errorMessage(error);
        if (message != null) {
          messenger?.showSnackBar(SnackBar(content: Text(message)));
        }
        widget.onDone?.call();
        final heard = _heard.trim();
        if (heard.isNotEmpty) widget.onHeard?.call(heard);
      },
    );
    if (session == null) {
      messenger?.showSnackBar(const SnackBar(
          content: Text("Voice input isn't available in this browser.")));
      return;
    }
    setState(() => _session = session);
  }

  void _stop() => _session?.stop();

  @override
  Widget build(BuildContext context) {
    if (!web.speechSupported) return const SizedBox.shrink();
    final listening = _listening;
    return IconButton(
      tooltip: listening ? 'Stop listening' : widget.tooltip,
      onPressed: listening ? _stop : (widget.enabled ? _start : null),
      isSelected: listening,
      icon: Icon(Icons.mic_none_rounded,
          size: widget.iconSize,
          color: widget.enabled ? AppText.primary : null),
      selectedIcon: Icon(Icons.stop_circle_rounded,
          size: widget.iconSize, color: AppText.red600),
    );
  }
}
