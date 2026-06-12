import 'package:dio/dio.dart' hide Response;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/accessibility_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/dio_provider.dart';
import '../theme/xene_theme.dart';
import '../providers/soundcloud_connection_provider.dart';
import '../widgets/auth_gate_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── game username ──
  String? _username;
  bool _loadingUsername = true;
  bool _savingUsername = false;
  bool _editingUsername = false;
  String? _usernameError;
  final _usernameController = TextEditingController();

  // ── email change ──
  bool _editingEmail = false;
  bool _savingEmail = false;
  String? _emailMessage;
  final _emailController = TextEditingController();

  // ── password reset ──
  bool _sendingReset = false;
  String? _resetMessage;

  // ── account deletion ──
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    try {
      final dio = ref.read(authenticatedDioProvider);
      final resp = await dio.get<Map<String, dynamic>>(
        '/game/profile/username',
      );
      final name = resp.data?['username'] as String?;
      if (mounted) {
        setState(() {
          _username = name;
          _usernameController.text = name ?? '';
          _loadingUsername = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsername = false);
    }
  }

  Future<void> _saveUsername() async {
    final value = _usernameController.text.trim();
    if (value.isEmpty) {
      setState(() => _usernameError = 'Username cannot be empty');
      return;
    }
    setState(() {
      _savingUsername = true;
      _usernameError = null;
    });
    try {
      final dio = ref.read(authenticatedDioProvider);
      final resp = await dio.put<Map<String, dynamic>>(
        '/game/profile/username',
        data: {'username': value},
      );
      final saved = resp.data?['username'] as String?;
      if (mounted) {
        setState(() {
          _username = saved;
          _editingUsername = false;
          _savingUsername = false;
        });
      }
    } catch (e) {
      String? msg;
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map) msg = data['error'] as String?;
      }
      if (mounted) {
        setState(() {
          _usernameError = msg ?? 'Failed to save username';
          _savingUsername = false;
        });
      }
    }
  }

  Future<void> _changeEmail() async {
    final newEmail = _emailController.text.trim();
    if (newEmail.isEmpty) return;
    setState(() {
      _savingEmail = true;
      _emailMessage = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
      );
      if (mounted) {
        setState(() {
          _emailMessage = 'Confirmation sent to $newEmail';
          _editingEmail = false;
          _savingEmail = false;
          _emailController.clear();
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Confirmation sent to $newEmail',
          TextDirection.ltr,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _emailMessage = 'Failed to update email';
          _savingEmail = false;
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;
    setState(() {
      _sendingReset = true;
      _resetMessage = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _resetMessage = 'Reset link sent to $email';
          _sendingReset = false;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Reset link sent to $email',
          TextDirection.ltr,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _resetMessage = 'Failed to send reset link';
          _sendingReset = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete account?',
          style: GoogleFonts.teko(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        content: Text(
          'This permanently deletes your account, saved items, and game history. It cannot be undone.',
          style: GoogleFonts.dmMono(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.teko(fontSize: 15, letterSpacing: 1),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              'DELETE',
              style: GoogleFonts.teko(fontSize: 15, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final dio = ref.read(authenticatedDioProvider);
      await dio.delete('/user/account');
      await Supabase.instance.client.auth.signOut();
      await Supabase.instance.client.auth.signInAnonymously();
      if (mounted) context.go('/');
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = ref.watch(isAnonymousProvider);
    final user = ref.watch(currentUserProvider);
    final scState = ref.watch(soundcloudConnectionProvider);

    if (isAnon) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'SETTINGS',
                  style: GoogleFonts.teko(fontSize: 24, letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to manage your account settings.',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    color: XeneTheme.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: () => showAuthGate(
                      context,
                      featureHint: 'to manage your account settings',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    child: Text(
                      'SIGN IN',
                      style: GoogleFonts.teko(fontSize: 16, letterSpacing: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel('CONNECTED ACCOUNTS'),
            const Divider(color: XeneTheme.border, height: 1),
            _soundcloudRow(scState),

            const SizedBox(height: 4),
            _sectionLabel('GAME PROFILE'),
            const Divider(color: XeneTheme.border, height: 1),
            _usernameRow(),

            const SizedBox(height: 4),
            _sectionLabel('ACCESSIBILITY'),
            const Divider(color: XeneTheme.border, height: 1),
            _accessibilitySection(),

            const SizedBox(height: 4),
            _sectionLabel('ACCOUNT'),
            const Divider(color: XeneTheme.border, height: 1),
            _emailRow(user?.email ?? ''),
            const Divider(color: XeneTheme.border, height: 1),
            _passwordResetRow(),
            const Divider(color: XeneTheme.border, height: 1),
            _deleteAccountRow(),

            const SizedBox(height: 4),
            _sectionLabel('APP'),
            const Divider(color: XeneTheme.border, height: 1),
            _infoRow('Version', '0.1.0'),
          ],
        ),
      ),
    );
  }

  // ── section label ────────────────────────────────────────────────────────

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title,
        style: GoogleFonts.teko(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF888888),
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  // ── soundcloud row ────────────────────────────────────────────────────────

  Widget _soundcloudRow(ScConnectionState scState) {
    final connected = scState.connected;
    final polling = scState.isPolling;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Image.asset('assets/soundcloud_logo.png', width: 18, height: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SoundCloud',
                  style: GoogleFonts.archivo(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  connected
                      ? 'Connected'
                      : (polling ? 'Connecting…' : 'Not connected'),
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: connected ? XeneTheme.success : XeneTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: polling
                  ? null
                  : () {
                      if (connected) {
                        ref
                            .read(soundcloudConnectionProvider.notifier)
                            .disconnect();
                      } else {
                        ref
                            .read(soundcloudConnectionProvider.notifier)
                            .connect();
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: connected ? Colors.red : Colors.black,
                side: BorderSide(
                  color: connected ? Colors.red : const Color(0xFFE0E0E0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              child: polling
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF888888),
                      ),
                    )
                  : Text(
                      connected ? 'DISCONNECT' : 'CONNECT',
                      style: GoogleFonts.teko(
                        fontSize: 13,
                        letterSpacing: 1,
                        color: connected ? Colors.red : Colors.black,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── game username row ─────────────────────────────────────────────────────

  Widget _usernameRow() {
    if (_loadingUsername) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    if (_editingUsername) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Game username',
              style: GoogleFonts.archivo(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    autofocus: true,
                    style: GoogleFonts.dmMono(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      errorText: _usernameError,
                    ),
                    onSubmitted: (_) => _saveUsername(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: _savingUsername ? null : _saveUsername,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    child: _savingUsername
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            'SAVE',
                            style: GoogleFonts.teko(
                              fontSize: 14,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _editingUsername = false;
                      _usernameError = null;
                      _usernameController.text = _username ?? '';
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF888888),
                      side: const BorderSide(color: XeneTheme.border),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    child: Text(
                      'CANCEL',
                      style: GoogleFonts.teko(fontSize: 14, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Game username',
                  style: GoogleFonts.archivo(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _username ?? 'Not set',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: _username != null
                        ? const Color(0xFF444444)
                        : const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: () => setState(() => _editingUsername = true),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: XeneTheme.border),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              child: Text(
                _username != null ? 'EDIT' : 'SET',
                style: GoogleFonts.teko(fontSize: 13, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── email row ─────────────────────────────────────────────────────────────

  Widget _emailRow(String currentEmail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email',
                      style: GoogleFonts.archivo(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      currentEmail,
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        color: XeneTheme.muted,
                      ),
                    ),
                    if (_emailMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _emailMessage!,
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: _emailMessage!.startsWith('Failed')
                                ? Colors.red
                                : XeneTheme.success,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _editingEmail = !_editingEmail;
                    _emailMessage = null;
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: XeneTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                  child: Text(
                    _editingEmail ? 'CANCEL' : 'CHANGE',
                    style: GoogleFonts.teko(fontSize: 13, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_editingEmail)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.dmMono(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'New email address',
                      hintStyle: GoogleFonts.dmMono(
                        fontSize: 12,
                        color: XeneTheme.mutedLight,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                    ),
                    onSubmitted: (_) => _changeEmail(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: _savingEmail ? null : _changeEmail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                      ),
                    ),
                    child: _savingEmail
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            'SEND',
                            style: GoogleFonts.teko(
                              fontSize: 14,
                              letterSpacing: 1,
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

  // ── password reset row ────────────────────────────────────────────────────

  Widget _passwordResetRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Password',
                  style: GoogleFonts.archivo(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _resetMessage ?? 'Send a reset link to your email',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: _resetMessage == null
                        ? const Color(0xFF888888)
                        : (_resetMessage!.startsWith('Failed')
                              ? Colors.red
                              : XeneTheme.success),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: _sendingReset ? null : _sendPasswordReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: XeneTheme.border),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              child: _sendingReset
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'RESET',
                      style: GoogleFonts.teko(fontSize: 13, letterSpacing: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── delete account row ────────────────────────────────────────────────────

  Widget _deleteAccountRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete account',
                  style: GoogleFonts.archivo(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                Text(
                  'Permanently deletes all your data',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: XeneTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: _deleting ? null : _deleteAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
              child: _deleting
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.red,
                      ),
                    )
                  : Text(
                      'DELETE',
                      style: GoogleFonts.teko(
                        fontSize: 13,
                        letterSpacing: 1,
                        color: Colors.red,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── accessibility section ─────────────────────────────────────────────────

  Widget _accessibilitySection() {
    final a11y = ref.watch(accessibilityProvider);
    final notifier = ref.read(accessibilityProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Text size',
                style: GoogleFonts.archivo(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${(a11y.textScaleOverride * 100).round()}%',
                style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Slider(
            value: a11y.textScaleOverride,
            min: 1.0,
            max: 2.0,
            divisions: 4,
            activeColor: Colors.black,
            inactiveColor: XeneTheme.border,
            onChanged: notifier.setTextScale,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'The quick brown fox jumps over the lazy dog',
            style: GoogleFonts.dmMono(fontSize: 12, color: XeneTheme.muted),
          ),
        ),
        const Divider(color: XeneTheme.border, height: 1),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 2,
          ),
          title: Text(
            'Reduce motion',
            style: GoogleFonts.archivo(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Stops slide animations and auto-scrolling',
            style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.muted),
          ),
          value: a11y.reduceMotion,
          activeThumbColor: Colors.black,
          onChanged: notifier.setReduceMotion,
        ),
        const Divider(color: XeneTheme.border, height: 1),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 2,
          ),
          title: Text(
            'High contrast',
            style: GoogleFonts.archivo(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Increases text and border contrast',
            style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.muted),
          ),
          value: a11y.highContrast,
          activeThumbColor: Colors.black,
          onChanged: notifier.setHighContrast,
        ),
      ],
    );
  }

  // ── info row ──────────────────────────────────────────────────────────────

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.archivo(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.dmMono(fontSize: 12, color: XeneTheme.muted),
          ),
        ],
      ),
    );
  }
}
