import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/dio_provider.dart';
import '../theme/xene_theme.dart';

void showBugReportSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BugReportSheet(),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _BugReportSheet extends ConsumerStatefulWidget {
  const _BugReportSheet();

  @override
  ConsumerState<_BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends ConsumerState<_BugReportSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dio = ref.read(authenticatedDioProvider);
      await dio.post<void>(
        '/bug_report',
        data: {'message': message, 'platform': 'flutter'},
      );
      if (mounted) setState(() => _submitted = true);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error =
              e.response?.data?['error']?.toString() ??
              'Something went wrong. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: _submitted
          ? _SuccessBody(onClose: () => Navigator.pop(context))
          : _FormBody(
              controller: _controller,
              loading: _loading,
              error: _error,
              onSubmit: _submit,
            ),
    );
  }
}

// ── Form state ────────────────────────────────────────────────────────────────

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.controller,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Handle
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: XeneTheme.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        Text(
          'SUBMIT BUG',
          style: GoogleFonts.teko(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Describe what happened — we read every report.',
          style: GoogleFonts.dmMono(
            fontSize: 11,
            color: XeneTheme.mutedLight,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: controller,
          minLines: 4,
          maxLines: 8,
          maxLength: 1000,
          autofocus: true,
          style: GoogleFonts.dmMono(fontSize: 12, color: Colors.black),
          decoration: InputDecoration(
            hintText: 'e.g. "The digest showed tracks from 3 months ago…"',
            hintStyle: GoogleFonts.dmMono(
              fontSize: 12,
              color: XeneTheme.mutedLight,
            ),
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(14),
            counterStyle: GoogleFonts.dmMono(
              fontSize: 10,
              color: XeneTheme.mutedLight,
            ),
          ),
        ),

        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: GoogleFonts.dmMono(fontSize: 11, color: XeneTheme.orange),
          ),
        ],

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: _SubmitButton(loading: loading, onTap: onSubmit),
        ),
      ],
    );
  }
}

// ── Submit button ─────────────────────────────────────────────────────────────

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _hovered && !widget.loading
                ? Colors.black
                : const Color(0xFF111111),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'SEND REPORT',
                  style: GoogleFonts.teko(
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Success state ─────────────────────────────────────────────────────────────

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 28),
            decoration: BoxDecoration(
              color: XeneTheme.muted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const Icon(
          Icons.check_circle_outline,
          size: 40,
          color: XeneTheme.success,
        ),
        const SizedBox(height: 16),
        Text(
          'Report received.',
          style: GoogleFonts.teko(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Thanks for helping us improve xene.',
          style: GoogleFonts.dmMono(
            fontSize: 11,
            color: XeneTheme.mutedLight,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onClose,
          child: Text(
            'CLOSE',
            style: GoogleFonts.teko(
              fontSize: 16,
              color: XeneTheme.mutedLight,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
