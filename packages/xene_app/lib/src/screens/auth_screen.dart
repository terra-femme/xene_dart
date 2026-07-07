import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/capacity_check_provider.dart';
import '../theme/xene_theme.dart';

// Must match the URL scheme registered natively (AndroidManifest.xml +
// ios/Runner/Info.plist: io.supabase.xene) AND the Supabase redirect allowlist.
const _kMobileRedirectUrl = 'io.supabase.xene://login-callback';

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
  bool _showCapacitySlideUp = false;
  CapacityCheckResponse? _capacityCheckResult;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _checkEmailAndSendLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _showCapacitySlideUp = false;
    });

    try {
      // Check if this email can sign up
      // Existing users can always sign in; new users blocked if at capacity
      final checkResult = await ref.read(
        checkEmailSignupProvider(email).future,
      );

      setState(() => _capacityCheckResult = checkResult);

      // If can't sign up, show slide-up instead of sending link
      if (!checkResult.canSignUp) {
        setState(() => _showCapacitySlideUp = true);
        return;
      }

      // On web, redirect back to wherever the app is actually running
      // (Uri.base.origin = current scheme://host:port) so the magic link returns
      // to this exact origin regardless of the dev port. This origin must be in
      // Supabase → Authentication → URL Configuration → Redirect URLs.
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: kIsWeb ? Uri.base.origin : _kMobileRedirectUrl,
      );
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
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
    final capacityCheck = ref.watch(capacityCheckProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: capacityCheck.when(
                loading: () => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: XeneTheme.orange),
                      const SizedBox(height: 12),
                      Text(
                        'Loading...',
                        style: GoogleFonts.archivo(
                          fontSize: 14,
                          color: XeneTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                error: (_, __) => _buildAuthWithHealthBar(null),
                data: (capacity) => _buildAuthWithHealthBar(capacity),
              ),
            ),
          ),
        ),
      ),
      bottomSheet: _showCapacitySlideUp && _capacityCheckResult != null
          ? _CapacitySlideUp(
              capacity: _capacityCheckResult!,
              onDismiss: () => setState(() => _showCapacitySlideUp = false),
            )
          : null,
    );
  }

  Widget _buildAuthWithHealthBar(CapacityCheckResponse? capacity) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (capacity != null)
          _CapacityHealthBar(percent: capacity.userCapPercent)
        else
          const SizedBox.shrink(),
        if (capacity != null) const SizedBox(height: 24),
        if (_sent)
          _ConfirmationView(email: _emailController.text.trim())
        else
          _EmailForm(
            controller: _emailController,
            loading: _loading,
            error: _error,
            onSubmit: _checkEmailAndSendLink,
            onAnonSignIn: kDebugMode ? _signInAnonymously : null,
            anonLoading: _anonLoading,
          ),
      ],
    );
  }
}

class _CapacityHealthBar extends StatelessWidget {
  const _CapacityHealthBar({required this.percent});
  final double percent;

  Color _barColor() {
    if (percent >= 90) {
      return Color.lerp(
        Colors.red.shade700,
        Colors.red.shade400,
        ((percent - 90) / 10).clamp(0, 1),
      )!;
    }
    if (percent >= 80) {
      return Color.lerp(
        Colors.orange.shade600,
        Colors.red.shade700,
        ((percent - 80) / 10),
      )!;
    }
    if (percent >= 50) {
      return Color.lerp(
        Colors.yellow.shade700,
        Colors.orange.shade600,
        ((percent - 50) / 30),
      )!;
    }
    return Colors.green.shade500;
  }

  @override
  Widget build(BuildContext context) {
    final displayPercent = (percent / 100).clamp(0.0, 1.0);

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: XeneTheme.border, width: 1),
            color: const Color(0xFFF5F5F5),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: displayPercent,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(_barColor()),
                ),
              ),
              if (displayPercent > 0.02)
                Positioned(
                  left: (displayPercent * 100).clamp(6, double.infinity),
                  top: 0,
                  child: Container(
                    width: 2,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      boxShadow: [
                        BoxShadow(
                          color: _barColor().withValues(alpha: 0.4),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          percent >= 90
              ? 'Xene is reaching capacity'
              : percent >= 70
              ? 'Filling up...'
              : 'Room to grow',
          style: GoogleFonts.archivo(
            fontSize: 11,
            color: XeneTheme.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
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

class _CapacitySlideUp extends StatelessWidget {
  const _CapacitySlideUp({required this.capacity, required this.onDismiss});

  final CapacityCheckResponse capacity;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Xene at Capacity',
                style: GoogleFonts.teko(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  letterSpacing: 0.8,
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(
                  Icons.close,
                  size: 24,
                  color: XeneTheme.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'We\'re growing fast! New signups are temporarily paused.',
            style: GoogleFonts.archivo(
              fontSize: 14,
              color: const Color(0xFF666666),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE0D0), width: 1),
            ),
            child: Text(
              '${capacity.userCount} users are already enjoying Xene. Try again soon!',
              style: GoogleFonts.archivo(
                fontSize: 12,
                color: const Color(0xFF555555),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onDismiss,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: XeneTheme.border),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              child: Text(
                'GOT IT',
                style: GoogleFonts.teko(
                  fontSize: 14,
                  letterSpacing: 1,
                  color: XeneTheme.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
