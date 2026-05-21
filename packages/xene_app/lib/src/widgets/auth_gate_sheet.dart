import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kWebRedirectUrl = String.fromEnvironment(
  'AUTH_REDIRECT_URL',
  defaultValue: 'http://localhost:4000',
);
const _kMobileRedirectUrl = 'com.xene.app://auth/callback';

/// Shows a bottom sheet prompting the user to sign in or create an account.
/// [featureHint] is appended after "Sign in or create an account " — keep it
/// short and lowercase, e.g. "to access editorial picks".
void showAuthGate(BuildContext context, {required String featureHint}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AuthGateSheet(featureHint: featureHint),
  );
}

class _AuthGateSheet extends StatefulWidget {
  const _AuthGateSheet({required this.featureHint});
  final String featureHint;

  @override
  State<_AuthGateSheet> createState() => _AuthGateSheetState();
}

class _AuthGateSheetState extends State<_AuthGateSheet> {
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        child: _sent
            ? _SentView(email: _emailController.text.trim())
            : _formView(),
      ),
    );
  }

  Widget _formView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'SIGN IN OR CREATE AN ACCOUNT',
          style: GoogleFonts.teko(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.featureHint,
          style: GoogleFonts.archivo(
            fontSize: 13,
            color: const Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendLink(),
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'your@email.com',
            hintStyle: GoogleFonts.archivo(color: const Color(0xFFCCCCCC)),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: BorderSide(color: Color(0xFFE0E0E0)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: BorderSide(color: Color(0xFFE0E0E0)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              borderSide: BorderSide(color: Color(0xFFFF5500)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: GoogleFonts.archivo(fontSize: 15, color: Colors.black),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: GoogleFonts.archivo(fontSize: 13, color: Colors.red),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _loading ? null : _sendLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5500),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFFCCB3),
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: _loading
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
      ],
    );
  }
}

class _SentView extends StatelessWidget {
  const _SentView({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_unread_outlined,
          size: 40,
          color: Color(0xFFFF5500),
        ),
        const SizedBox(height: 16),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: GoogleFonts.teko(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a sign-in link to $email.\nTap the link to open Xene.',
          textAlign: TextAlign.center,
          style: GoogleFonts.archivo(
            fontSize: 13,
            color: const Color(0xFF666666),
            height: 1.6,
          ),
        ),
      ],
    );
  }
}
