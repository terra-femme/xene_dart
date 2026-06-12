import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/xene_theme.dart';

// Web: Supabase redirects back to this URL after the magic link is clicked.
// The browser loads it and supabase_flutter picks up the session from the
// URL hash automatically. Must match a URL in Supabase dashboard → Redirect URLs.
// Mobile: uses the custom URL scheme so the OS reopens the app.
const _kWebRedirectUrl = String.fromEnvironment(
  'AUTH_REDIRECT_URL',
  defaultValue: 'http://localhost:4000',
);
const _kMobileRedirectUrl = 'com.xene.app://auth/callback';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;
  bool _anonLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendMagicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: kIsWeb ? _kWebRedirectUrl : _kMobileRedirectUrl,
      );
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() => _anonLoading = true);
    try {
      await Supabase.instance.client.auth.signInAnonymously();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Anonymous sign-in failed.');
    } finally {
      if (mounted) setState(() => _anonLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _sent
                  ? _ConfirmationView(email: _emailController.text.trim())
                  : _EmailForm(
                      controller: _emailController,
                      loading: _loading,
                      anonLoading: _anonLoading,
                      error: _error,
                      onSubmit: _sendMagicLink,
                      onAnonSignIn: kDebugMode ? _signInAnonymously : null,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailForm extends StatelessWidget {
  const _EmailForm({
    required this.controller,
    required this.loading,
    required this.anonLoading,
    required this.error,
    required this.onSubmit,
    required this.onAnonSignIn,
  });

  final TextEditingController controller;
  final bool loading;
  final bool anonLoading;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback? onAnonSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'XENE',
          textAlign: TextAlign.center,
          style: GoogleFonts.teko(
            fontSize: 48,
            fontWeight: FontWeight.w600,
            color: XeneTheme.orange,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your email to sign in or create an account.',
          textAlign: TextAlign.center,
          style: GoogleFonts.archivo(fontSize: 14, color: XeneTheme.muted),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'your@email.com',
            hintStyle: GoogleFonts.archivo(color: const Color(0xFFCCCCCC)),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: const BorderSide(color: XeneTheme.border),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: const BorderSide(color: XeneTheme.border),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: const BorderSide(color: XeneTheme.orange),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: GoogleFonts.archivo(fontSize: 15, color: Colors.black),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: GoogleFonts.archivo(fontSize: 13, color: Colors.red),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: loading ? null : onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: XeneTheme.orange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFCCB3),
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'CONTINUE',
                    style: GoogleFonts.teko(
                      fontSize: 18,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        if (onAnonSignIn != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: anonLoading ? null : onAnonSignIn,
            child: anonLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'DEV: Continue without email',
                    style: GoogleFonts.archivo(
                      fontSize: 12,
                      color: const Color(0xFFAAAAAA),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

class _ConfirmationView extends StatelessWidget {
  const _ConfirmationView({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          size: 48,
          color: XeneTheme.orange,
        ),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: GoogleFonts.teko(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We sent a sign-in link to\n$email\n\nTap the link in your email to open Xene.',
          textAlign: TextAlign.center,
          style: GoogleFonts.archivo(
            fontSize: 14,
            color: const Color(0xFF666666),
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
