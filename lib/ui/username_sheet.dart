import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/username_service.dart';
import 'package:namer_app/ui/responsive.dart';

/// What [showUsernameSheet] returns when they tapped [skipLabel] instead of
/// picking one (null means they closed the sheet).
const usernameSkipped = '';

/// Lets the signed-in person pick (or change) their username. Returns the
/// saved handle (lower-case, no @), [usernameSkipped] if they chose
/// [skipLabel], or null if they backed out. Prefills a free suggestion
/// when they don't have one yet.
Future<String?> showUsernameSheet(
  BuildContext context, {
  String? current,
  String? title,
  String? intro,
  String? skipLabel,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _UsernameSheet(
      current: current,
      title: title ??
          (current == null ? 'Pick a username' : 'Change your username'),
      intro: intro,
      skipLabel: skipLabel,
    ),
  );
}

class _UsernameSheet extends StatefulWidget {
  final String? current;
  final String title;
  final String? intro;
  final String? skipLabel;

  const _UsernameSheet({
    required this.current,
    required this.title,
    required this.intro,
    required this.skipLabel,
  });

  @override
  State<_UsernameSheet> createState() => _UsernameSheetState();
}

class _UsernameSheetState extends State<_UsernameSheet> {
  final User? _user = FirebaseAuth.instance.currentUser;
  late final TextEditingController _handle =
      TextEditingController(text: widget.current ?? '');
  bool _saving = false;
  String? _error;

  /// Set once they type, so a late suggestion doesn't overwrite them.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.current == null) _prefill();
  }

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    final user = _user;
    if (user == null) return;
    try {
      final doc =
          await BalanceService.db.collection('users').doc(user.uid).get();
      final suggestion = await UsernameService.suggestAvailable(
        uid: user.uid,
        email: user.email,
        displayName: doc.data()?['display_name'] as String?,
      );
      if (!mounted || _touched) return;
      setState(() {
        _handle.text = suggestion;
        _handle.selection =
            TextSelection.collapsed(offset: suggestion.length);
      });
    } catch (_) {
      // No suggestion: they can still type one.
    }
  }

  Future<void> _save() async {
    final user = _user;
    if (user == null || _saving) return;
    final handle = UsernameService.normalise(_handle.text);
    if (handle == widget.current) {
      Navigator.pop(context, handle);
      return;
    }
    final problem = UsernameService.validate(handle);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await UsernameService.claim(user.uid, handle);
      if (mounted) Navigator.pop(context, saved);
    } on UsernameTakenException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } on UsernameInvalidException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save your username. Check your connection and "
              'try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = UsernameService.normalise(_handle.text);
    final preview = handle.isEmpty ? 'yourname' : handle;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.intro ??
                    'Friends can add you by your username, and it makes '
                        'your invite link easy to read.',
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _handle,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_saving,
                maxLength: UsernameService.maxLength,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  // Letters, numbers and _ only, always lower-case.
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toLowerCase()),
                  ),
                ],
                onChanged: (_) => setState(() {
                  _touched = true;
                  _error = null;
                }),
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  helperText: '3–20 letters, numbers or _',
                  errorText: _error,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link_rounded, size: 18, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${UsernameService.siteHost}/?add=$preview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || handle.isEmpty ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.current == null
                        ? 'Save username'
                        : 'Save new username'),
              ),
              if (widget.skipLabel != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, usernameSkipped),
                  child: Text(widget.skipLabel!),
                ),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
