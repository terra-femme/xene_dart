import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/dio_provider.dart';
import '../providers/game_provider.dart';
import '../theme/xene_theme.dart';

/// Shows a bottom sheet prompting the user to pick a username.
/// [onComplete] is called with the chosen username after a successful save.
Future<String?> showUsernameSetup(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _UsernameSetupSheet(ref: ref),
  );
}

class _UsernameSetupSheet extends StatefulWidget {
  const _UsernameSetupSheet({required this.ref});
  final WidgetRef ref;

  @override
  State<_UsernameSetupSheet> createState() => _UsernameSetupSheetState();
}

class _UsernameSetupSheetState extends State<_UsernameSetupSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _ctrl.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(raw)) {
      setState(
        () => _error = '3–20 characters, letters, numbers, underscores only',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = widget.ref.read(authenticatedDioProvider);
      await dio.put('/game/profile/username', data: {'username': raw});
      // Invalidate the cached username so providers re-fetch.
      widget.ref.invalidate(usernameProvider);
      if (mounted) Navigator.of(context).pop(raw);
    } on DioException catch (e) {
      final body = e.response?.data;
      String msg = 'Could not save username';
      if (body is Map && body['error'] != null) {
        msg = body['error'] as String;
      }
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHOOSE A USERNAME',
            style: GoogleFonts.teko(fontSize: 22, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          Text(
            'Other party members will see this name.',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              color: XeneTheme.mutedLight,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 20,
            style: GoogleFonts.dmMono(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. musichead42',
              hintStyle: GoogleFonts.dmMono(
                fontSize: 13,
                color: XeneTheme.mutedLight,
              ),
              counterText: '',
              enabledBorder: const UnderlineInputBorder(
                borderSide: const BorderSide(color: XeneTheme.borderHeavy),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.black),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.error),
            ),
          ],
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _loading ? null : _submit,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _loading ? XeneTheme.mutedLight : Colors.black,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _loading ? 'SAVING...' : 'SAVE USERNAME',
                textAlign: TextAlign.center,
                style: GoogleFonts.teko(
                  fontSize: 16,
                  letterSpacing: 1,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
