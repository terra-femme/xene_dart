import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xene_app/src/providers/auth_provider.dart';
import 'package:xene_app/src/widgets/auth_gate_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await Supabase.instance.client.auth.signOut();
      // Re-establish anonymous session so the feed keeps working
      // and all feature gates restore immediately.
      await Supabase.instance.client.auth.signInAnonymously();
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = ref.watch(isAnonymousProvider);
    final user = ref.watch(currentUserProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: isAnon ? _guestView() : _accountView(user?.email ?? ''),
        ),
      ),
    );
  }

  Widget _guestView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'BROWSING AS GUEST',
          style: GoogleFonts.teko(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Create a free account to access the custom preset, follow artists, and link your SoundCloud.',
          style: GoogleFonts.archivo(
            fontSize: 13,
            color: const Color(0xFF888888),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () =>
                showAuthGate(context, featureHint: 'to unlock all features'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5500),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: Text(
              'SIGN IN OR CREATE AN ACCOUNT',
              style: GoogleFonts.teko(
                fontSize: 16,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountView(String email) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ACCOUNT',
          style: GoogleFonts.teko(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: Colors.black,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'EMAIL',
          style: GoogleFonts.teko(
            fontSize: 11,
            color: const Color(0xFF888888),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: GoogleFonts.archivo(fontSize: 15, color: Colors.black),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Divider(color: Color(0xFFE0E0E0), height: 1),
        ),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _signingOut ? null : _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Color(0xFFE0E0E0)),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
            child: _signingOut
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    'SIGN OUT',
                    style: GoogleFonts.teko(
                      fontSize: 16,
                      letterSpacing: 1.5,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
