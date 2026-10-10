import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:namer_app/ui/calorie_card.dart' show cardholderFromEmail;

/// Shared look for sign-in, sign-up, password reset and verification.
///
/// Phone: indigo backdrop with the calorie card at the top, form on a white
/// sheet below. Big screens: the outer frame already shows the brand panel
/// (with its own card), so only the form is shown.
class AuthColors {
  AuthColors._();

  /// Darker indigo for buttons and links: white text on it passes WCAG AA,
  /// which the lighter brand indigo doesn't quite.
  static const action = AppColors.primaryDark;
  static const actionPressed = AppColors.indigo700;
  static const backdropTop = AppColors.primaryDark;
  static const backdropBottom = AppColors.violet600;
  static Color get text => AppColors.ink;
  static Color get muted => AppColors.muted;
  static Color get field => AppColors.gray50;
  static Color get border => AppColors.border;
  static Color get errorText => AppText.red700;
  static Color get errorBg => AppColors.red50;
  static Color get errorBorder =>
      AppColors.dark ? const Color(0xFF5B2530) : const Color(0xFFFECACA);
  static Color get successText => AppText.emerald700;
  static Color get successBg => AppColors.emerald50;
  static Color get successBorder =>
      AppColors.dark ? const Color(0xFF1F5244) : const Color(0xFFA7F3D0);
  static Color get infoText => AppText.indigo800;
  static Color get infoBg => AppColors.indigo50;
  static Color get infoBorder =>
      AppColors.dark ? const Color(0xFF3A3F7A) : const Color(0xFFC7D2FE);
}

bool _brandPanelVisible(BuildContext context) {
  // The real window width (MediaQuery inside the frame is the panel's).
  final view = View.of(context);
  final width = view.physicalSize.width / view.devicePixelRatio;
  return width >= Breakpoints.desktop;
}

/// Page layout for every signed-out screen.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;

  /// Name shown on the card ("cardholder"). Null shows the brand name.
  final String? cardholder;
  final bool showCard;
  final VoidCallback? onBack;

  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.footer,
    this.cardholder,
    this.showCard = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final framed = _brandPanelVisible(context);

    final form = Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AuthColors.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: AuthColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 24),
          child,
          if (footer != null) ...[
            const SizedBox(height: 24),
            footer!,
          ],
        ],
      ),
    );

    if (framed) {
      // Desktop: the brand panel beside us already carries the identity.
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (onBack != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
                        child: _BackButton(onPressed: onBack!, dark: true),
                      ),
                    ),
                  form,
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Phone: indigo header with the card, white sheet below. The sheet is
    // pulled up over the header so its rounded corners sit on indigo, and
    // the page itself is white so the sheet always reaches the bottom.
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AuthColors.backdropTop, AuthColors.backdropBottom],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                      child: Row(
                        children: [
                          if (onBack != null)
                            _BackButton(onPressed: onBack!, dark: false)
                          else
                            const SizedBox(width: 16),
                          const Icon(Icons.credit_card,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'The Calorie Card',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showCard)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: CalorieCardPreview(cardholder: cardholder),
                        ),
                      ),
                    const SizedBox(height: 56),
                  ],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -28),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SafeArea(top: false, child: form),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool dark;

  const _BackButton({required this.onPressed, required this.dark});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      onPressed: onPressed,
      icon: Icon(
        Icons.arrow_back_rounded,
        color: dark ? AuthColors.text : Colors.white,
      ),
    );
  }
}

/// The product's own object: a payment-style card with a calorie balance.
/// The cardholder line updates as people type their email.
class CalorieCardPreview extends StatelessWidget {
  final String? cardholder;

  const CalorieCardPreview({super.key, this.cardholder});

  @override
  Widget build(BuildContext context) {
    // Card shape, but never so short on a small phone that it overflows.
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxWidth / 1.6 < 190 ? 190 : constraints.maxWidth / 1.6,
        child: CalorieCardFront(
        amount: 2000,
        holder: cardholder ?? '',
        macros: const [
          CardMacro(name: 'Protein', remaining: 150, color: CalorieCardColors.protein),
          CardMacro(name: 'Carbs', remaining: 220, color: CalorieCardColors.carbs),
          CardMacro(name: 'Fat', remaining: 65, color: CalorieCardColors.fat),
        ],
        ),
      ),
    );
  }
}

/// Labelled text field used on every auth screen.
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool password;
  final String? errorText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.password = false,
    this.errorText,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AuthColors.text,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: widget.password && _hidden,
          enableSuggestions: !widget.password,
          autocorrect: false,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          textInputAction: widget.textInputAction,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          style: TextStyle(fontSize: 16, color: AuthColors.text),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: AppColors.gray400),
            prefixIcon: Icon(widget.icon, color: AuthColors.muted, size: 20),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AuthColors.muted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
            errorText: widget.errorText,
            errorMaxLines: 3,
            errorStyle: TextStyle(
              color: AuthColors.errorText,
              fontSize: 13,
            ),
            filled: true,
            fillColor: AuthColors.field,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            enabledBorder: border(AuthColors.border),
            disabledBorder: border(AuthColors.border),
            focusedBorder: border(AuthColors.action, 2),
            errorBorder: border(AuthColors.errorText),
            focusedErrorBorder: border(AuthColors.errorText, 2),
          ),
        ),
      ],
    );
  }
}

/// Full-width main action with a built-in loading state.
class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AuthColors.action,
          disabledBackgroundColor: AuthColors.action.withValues(alpha: 0.6),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.all(AuthColors.actionPressed),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// Secondary, outlined action (e.g. "Create an account").
class AuthSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppText.primaryDark,
          side: BorderSide(color: AuthColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Small text link (e.g. "Forgot password?").
class AuthLink extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AuthLink({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppText.primaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

enum AuthNoticeKind { error, success, info }

/// Inline message shown above the form, replacing pop-up dialogs.
class AuthNotice extends StatelessWidget {
  final AuthNoticeKind kind;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AuthNotice({
    super.key,
    required this.kind,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color edge, IconData icon) = switch (kind) {
      AuthNoticeKind.error => (
          AuthColors.errorText,
          AuthColors.errorBg,
          AuthColors.errorBorder,
          Icons.error_outline_rounded,
        ),
      AuthNoticeKind.success => (
          AuthColors.successText,
          AuthColors.successBg,
          AuthColors.successBorder,
          Icons.check_circle_outline_rounded,
        ),
      AuthNoticeKind.info => (
          AuthColors.infoText,
          AuthColors.infoBg,
          AuthColors.infoBorder,
          Icons.info_outline_rounded,
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: edge),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(color: fg, fontSize: 14, height: 1.4),
                  ),
                  if (actionLabel != null && onAction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: fg,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(
                          actionLabel!,
                          style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: fg,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "or" style divider with a short question, e.g. "New here?".
class AuthDivider extends StatelessWidget {
  final String text;

  const AuthDivider({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AuthColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(color: AuthColors.muted, fontSize: 14),
          ),
        ),
        Expanded(child: Divider(color: AuthColors.border)),
      ],
    );
  }
}

/// Full-width "Continue with Google", shown above the email form.
class GoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const GoogleButton({super.key, required this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AuthColors.text,
          side: BorderSide(color: AuthColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AuthColors.action,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _GoogleMark(),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'Continue with Google',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A simple "G" in Google's blue, so the button is recognisable without
/// shipping an image.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFDADCE0)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 14,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}

/// Opens one of the site's own pages (such as '/privacy.html') in a new
/// tab. Returns false if it couldn't.
Future<bool> openSitePage(String path) async {
  try {
    final uri = kIsWeb
        ? Uri.base.resolve(path)
        : Uri.parse('https://thecaloriecard.com$path');
    return await launchUrl(uri, webOnlyWindowName: '_blank');
  } catch (_) {
    return false;
  }
}

/// "By creating a card you agree to our Terms and Privacy Policy."
class LegalAgreement extends StatelessWidget {
  const LegalAgreement({super.key});

  Widget _link(String label, String path) {
    return TextButton(
      onPressed: () => openSitePage(path),
      style: TextButton.styleFrom(
        foregroundColor: AppText.primaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, color: AuthColors.muted);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By creating a card you agree to our', style: style),
        _link('Terms', '/terms.html'),
        Text('and', style: style),
        _link('Privacy Policy', '/privacy.html'),
      ],
    );
  }
}

/// Shown while we find out whether someone is signed in: the brand, not a
/// sign-in form that might flash past.
class AuthSplash extends StatelessWidget {
  const AuthSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      alignment: Alignment.center,
      child: Semantics(
        liveRegion: true,
        label: 'Loading your card',
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Loading your card…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              if (!reduceMotion)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numbered steps: only for things that really are done in order.
class AuthSteps extends StatelessWidget {
  final List<String> steps;

  const AuthSteps({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AuthColors.infoBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: AuthColors.infoText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        color: AuthColors.text,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Validation and error messages
// ---------------------------------------------------------------------------

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String email) {
  final e = email.trim();
  if (e.isEmpty) return 'Enter your email address';
  if (!_emailPattern.hasMatch(e)) return 'Enter a valid email, like name@example.com';
  return null;
}

/// Minimum Firebase accepts.
const minPasswordLength = 6;

String? validateNewPassword(String password) {
  if (password.isEmpty) return 'Choose a password';
  if (password.length < minPasswordLength) {
    return 'Use at least $minPasswordLength characters';
  }
  return null;
}

/// What went wrong, in plain words, plus which field it belongs to (if any).
class AuthProblem {
  final String message;
  final String? field; // 'email' | 'password' | null for a banner
  final String? actionLabel;
  final String? action; // 'reset' | 'signin' | null

  const AuthProblem(this.message, {this.field, this.actionLabel, this.action});
}

AuthProblem authProblemFor(Object error, {required String flow}) {
  final code = error is FirebaseAuthException ? error.code : '';
  switch (code) {
    case 'invalid-email':
      return const AuthProblem('Enter a valid email, like name@example.com',
          field: 'email');
    // Firebase reports wrong email and wrong password the same way on
    // purpose, so we don't claim to know which one it was.
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
    case 'INVALID_LOGIN_CREDENTIALS':
      if (flow == 'reset') {
        return const AuthProblem(
            "We couldn't find an account with that email. Check it, or create a new account.",
            field: 'email');
      }
      return const AuthProblem(
        "That email and password don't match an account. Check both and try again.",
        actionLabel: 'Reset your password',
        action: 'reset',
      );
    case 'email-already-in-use':
      return const AuthProblem(
        'There\'s already an account with this email.',
        actionLabel: 'Sign in instead',
        action: 'signin',
      );
    case 'weak-password':
      return AuthProblem(
          'Use at least $minPasswordLength characters, mixing letters and numbers',
          field: 'password');
    case 'user-disabled':
      return const AuthProblem(
          'This account has been turned off. Contact support to restore it.');
    case 'too-many-requests':
      return AuthProblem(
        flow == 'signin'
            ? 'Too many attempts. Wait a few minutes, or reset your password to sign in now.'
            : 'Too many attempts. Wait a few minutes and try again.',
        actionLabel: flow == 'signin' ? 'Reset your password' : null,
        action: flow == 'signin' ? 'reset' : null,
      );
    case 'network-request-failed':
      return const AuthProblem(
          "You're offline or the connection dropped. Check your internet and try again.");
    case 'channel-error':
      return const AuthProblem('Enter your email and password.');
    case 'popup-blocked':
      return const AuthProblem(
          'Your browser blocked the Google window. Allow pop-ups for this '
          'site and try again.');
    case 'account-exists-with-different-credential':
      return const AuthProblem(
          'This email already has a Calorie Card account. Sign in with your '
          'email and password instead.');
    case 'operation-not-allowed':
      return const AuthProblem(
          "That way of signing in isn't switched on yet. Use your email "
          'and password for now.');
    case 'unauthorized-domain':
      return const AuthProblem(
          "Google sign-in isn't available on this address yet. Use your "
          'email and password for now.');
    default:
      return AuthProblem(switch (flow) {
        'signup' => "Your account wasn't created. Try again in a moment.",
        'reset' => "The reset email wasn't sent. Try again in a moment.",
        _ => "Sign-in didn't go through. Try again in a moment.",
      });
  }
}
