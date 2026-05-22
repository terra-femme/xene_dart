import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xene_domain/xene_domain.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/auth_gate_sheet.dart';
import '../widgets/username_setup_sheet.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAnon = ref.watch(isAnonymousProvider);

    if (isAnon) {
      return _AnonGate(
        onSignIn: () => showAuthGate(
          context,
          featureHint: 'to create or join a party and play the weekly game',
        ),
      );
    }

    final partiesAsync = ref.watch(gamePartiesProvider);

    return partiesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text(
          'Could not load parties',
          style: GoogleFonts.teko(color: const Color(0xFFA3A3A3), fontSize: 16),
        ),
      ),
      data: (parties) => _GameBody(parties: parties),
    );
  }
}

// ── Anon gate ─────────────────────────────────────────────────────────────────

class _AnonGate extends StatelessWidget {
  const _AnonGate({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PARTY GAME',
            style: GoogleFonts.teko(
              fontSize: 28,
              letterSpacing: 2,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to create or join a party',
            style: GoogleFonts.dmMono(
              fontSize: 12,
              color: const Color(0xFFA3A3A3),
            ),
          ),
          const SizedBox(height: 24),
          _ActionButton(label: 'SIGN IN', onTap: onSignIn),
        ],
      ),
    );
  }
}

// ── Main game body ────────────────────────────────────────────────────────────

class _GameBody extends ConsumerWidget {
  const _GameBody({required this.parties});
  final List<PartyPreview> parties;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      children: [
        _SectionHeader(
          title: 'YOUR PARTIES',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallButton(
                label: '+ CREATE',
                onTap: () => _showCreateSheet(context, ref),
              ),
              const SizedBox(width: 8),
              _SmallButton(
                label: 'JOIN',
                onTap: () => _showJoinSheet(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (parties.isEmpty)
          _EmptyState(
            onCreate: () => _showCreateSheet(context, ref),
            onJoin: () => _showJoinSheet(context, ref),
          )
        else
          ...parties.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PartyCard(party: p),
            ),
          ),
      ],
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final username = await ref.read(usernameProvider.future);
    if (!context.mounted) return;
    if (username == null || username.isEmpty) {
      final chosen = await showUsernameSetup(context, ref);
      if (chosen == null || !context.mounted) return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _CreatePartySheet(notifier: ref.read(gamePartiesProvider.notifier)),
    );
  }

  Future<void> _showJoinSheet(BuildContext context, WidgetRef ref) async {
    final username = await ref.read(usernameProvider.future);
    if (!context.mounted) return;
    if (username == null || username.isEmpty) {
      final chosen = await showUsernameSetup(context, ref);
      if (chosen == null || !context.mounted) return;
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _JoinPartySheet(notifier: ref.read(gamePartiesProvider.notifier)),
    );
  }
}

// ── Party card ────────────────────────────────────────────────────────────────

class _PartyCard extends StatelessWidget {
  const _PartyCard({required this.party});
  final PartyPreview party;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/game/party/${party.id}'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E5E5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    party.name.toUpperCase(),
                    style: GoogleFonts.teko(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${party.memberCount} member${party.memberCount == 1 ? '' : 's'}',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: const Color(0xFFA3A3A3),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${party.myTrackCountThisWeek}/5',
                  style: GoogleFonts.teko(
                    fontSize: 22,
                    color: party.myTrackCountThisWeek >= 5
                        ? const Color(0xFF4CAF50)
                        : Colors.black,
                  ),
                ),
                Text(
                  'tracks this week',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    color: const Color(0xFFA3A3A3),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA3A3A3)),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate, required this.onJoin});
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            'NO PARTIES YET',
            style: GoogleFonts.teko(
              fontSize: 22,
              color: const Color(0xFFA3A3A3),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a crew or enter a code from a friend',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: const Color(0xFFA3A3A3),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionButton(label: 'CREATE PARTY', onTap: onCreate),
              const SizedBox(width: 12),
              _ActionButton(
                label: 'JOIN WITH CODE',
                onTap: onJoin,
                outlined: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Create party sheet ────────────────────────────────────────────────────────

class _CreatePartySheet extends StatefulWidget {
  const _CreatePartySheet({required this.notifier});
  final GamePartiesNotifier notifier;

  @override
  State<_CreatePartySheet> createState() => _CreatePartySheetState();
}

class _CreatePartySheetState extends State<_CreatePartySheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a party name');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.notifier.createParty(name);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle('CREATE PARTY'),
          const SizedBox(height: 16),
          _GameTextField(
            controller: _ctrl,
            hint: 'Party name (e.g. THE CREW)',
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ErrorText(_error!),
          ],
          const SizedBox(height: 16),
          _ActionButton(
            label: _loading ? 'CREATING...' : 'CREATE',
            onTap: _loading ? null : _submit,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

// ── Join party sheet ──────────────────────────────────────────────────────────

class _JoinPartySheet extends StatefulWidget {
  const _JoinPartySheet({required this.notifier});
  final GamePartiesNotifier notifier;

  @override
  State<_JoinPartySheet> createState() => _JoinPartySheetState();
}

class _JoinPartySheetState extends State<_JoinPartySheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-character invite code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.notifier.joinParty(code);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _extractError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle('JOIN PARTY'),
          const SizedBox(height: 16),
          _GameTextField(
            controller: _ctrl,
            hint: 'Invite code (e.g. XENE42)',
            onSubmitted: (_) => _submit(),
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ErrorText(_error!),
          ],
          const SizedBox(height: 16),
          _ActionButton(
            label: _loading ? 'JOINING...' : 'JOIN',
            onTap: _loading ? null : _submit,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

// ── Shared sheet widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.teko(
            fontSize: 14,
            letterSpacing: 1.5,
            color: const Color(0xFFA3A3A3),
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

class _SheetContainer extends StatelessWidget {
  const _SheetContainer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPad),
      child: child,
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: GoogleFonts.teko(fontSize: 22, letterSpacing: 1));
  }
}

class _GameTextField extends StatelessWidget {
  const _GameTextField({
    required this.controller,
    required this.hint,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.words,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      maxLength: maxLength,
      onSubmitted: onSubmitted,
      style: GoogleFonts.dmMono(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmMono(
          fontSize: 13,
          color: const Color(0xFFA3A3A3),
        ),
        counterText: '',
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE5E5E5)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: GoogleFonts.teko(
          fontSize: 14,
          letterSpacing: 0.5,
          color: Colors.black,
          decoration: TextDecoration.underline,
          decorationColor: Colors.black,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    this.onTap,
    this.outlined = false,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool outlined;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: outlined
              ? Colors.white
              : (enabled ? Colors.black : const Color(0xFFA3A3A3)),
          border: outlined ? Border.all(color: Colors.black) : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.teko(
            fontSize: 15,
            letterSpacing: 1,
            color: outlined ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFFD32F2F)),
    );
  }
}

String _extractError(Object e) {
  final s = e.toString();
  if (s.contains('Maximum of')) return s.split('Maximum of').last.trim();
  if (s.contains('"error"')) {
    final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(s);
    if (match != null) return match.group(1)!;
  }
  return 'Something went wrong, please try again';
}
