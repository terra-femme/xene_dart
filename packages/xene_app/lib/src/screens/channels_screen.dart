import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/preset_sources_provider.dart';
import '../providers/preset_templates_provider.dart';
import '../theme/xene_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Root screen
// ─────────────────────────────────────────────────────────────────────────────

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  final _searchCtrl = TextEditingController();
  int _selectedIndex = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(presetTemplatesProvider);
    final templates =
        (templatesAsync.valueOrNull ?? []).where((t) => t.enabled).toList()
          ..sort((a, b) => a.notchIndex.compareTo(b.notchIndex));

    final selected = templates.isNotEmpty && _selectedIndex < templates.length
        ? templates[_selectedIndex]
        : null;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final carousel = _CarouselSection(
      templates: templates,
      selectedIndex: _selectedIndex,
      onSelectionChanged: (i) => setState(() => _selectedIndex = i),
      fillHeight: isLandscape,
    );

    final sources = selected != null
        ? _SourcesSection(
            key: ValueKey(selected.slug),
            template: selected,
            query: _query,
            searchCtrl: _searchCtrl,
          )
        : const SizedBox.shrink();

    // ── Landscape: carousel left column | sources right column ────────────
    if (isLandscape) {
      final padding = MediaQuery.paddingOf(context);
      return ColoredBox(
        // Dark outer covers the left safe-area strip with no widget boundary —
        // eliminates the hairline seam that appears when two separate dark widgets
        // sit on a white outer background.
        color: const Color(0xFF080808),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: padding.left),
            Expanded(flex: 2, child: carousel),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0xFF1C1C1C),
            ),
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: Colors.white,
                // Right safe-area SizedBox lives INSIDE this white box so it is
                // seamlessly white — no separate ColoredBox boundary on the right.
                child: Row(
                  children: [
                    Expanded(child: sources),
                    SizedBox(width: padding.right),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Portrait: stacked layout with arch divider ────────────────────────
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          carousel,
          _ArchDivider(
            accentColor: selected != null
                ? _hexColor(selected.themeColor)
                : const Color(0xFF00C5A5),
          ),
          Expanded(child: sources),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carousel section — custom Stack carousel with correct z-ordering
// ─────────────────────────────────────────────────────────────────────────────
//
// Cards are sorted by distance from center before being added to the Stack:
//   furthest → first child (painted behind everything)
//   center   → last child  (painted on top of everything)
// This is the only correct way to keep the focused card visually in front.

class _CarouselSection extends StatefulWidget {
  const _CarouselSection({
    required this.templates,
    required this.selectedIndex,
    required this.onSelectionChanged,
    this.fillHeight = false,
  });

  final List<PresetTemplate> templates;
  final int selectedIndex;
  final ValueChanged<int> onSelectionChanged;
  // When true the widget expands to fill its parent (landscape side-by-side).
  final bool fillHeight;

  @override
  State<_CarouselSection> createState() => _CarouselSectionState();
}

class _CarouselSectionState extends State<_CarouselSection>
    with SingleTickerProviderStateMixin {
  static const _darkBg = Color(0xFF080808);

  late final AnimationController _snapCtrl;
  late Animation<double> _snapAnim;
  double _page = 0; // fractional — drives all transforms

  @override
  void initState() {
    super.initState();
    _page = widget.selectedIndex.toDouble();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _snapAnim = AlwaysStoppedAnimation(_page);
  }

  @override
  void didUpdateWidget(_CarouselSection old) {
    super.didUpdateWidget(old);
    // Snap when parent sets selectedIndex (e.g. dot tap)
    if (old.selectedIndex != widget.selectedIndex) {
      _animateTo(widget.selectedIndex, notify: false);
    }
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _animateTo(int target, {bool notify = true}) {
    _snapCtrl.stop();
    final start = _page;
    _snapAnim = Tween<double>(begin: start, end: target.toDouble()).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic),
    )..addListener(() => setState(() => _page = _snapAnim.value));
    _snapCtrl
      ..reset()
      ..forward();
    if (notify) widget.onSelectionChanged(target);
  }

  void _onDragUpdate(DragUpdateDetails d, {required double stride}) {
    _snapCtrl.stop();
    setState(() {
      _page = (_page - d.delta.dy / stride).clamp(
        0.0,
        (widget.templates.length - 1).toDouble(),
      );
    });
    final nearest = _page.round().clamp(0, widget.templates.length - 1);
    if (nearest != widget.selectedIndex) widget.onSelectionChanged(nearest);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    int target;
    if (v.abs() > 350) {
      target = v < 0
          ? (_page + 1).ceil().clamp(0, widget.templates.length - 1)
          : (_page - 1).floor().clamp(0, widget.templates.length - 1);
    } else {
      target = _page.round().clamp(0, widget.templates.length - 1);
    }
    _animateTo(target);
  }

  // Cards and stride are computed from an available Size.
  //
  // Portrait (fill: false):
  //   viewportH = 25% of screen height, clamped [140, 240]
  //   cardH     = 56% of viewportH
  //   stride    = 44% of viewportH
  //   cardW     = 60% of screen width, clamped [160, 300]
  //
  // Landscape side-by-side (fill: true):
  //   viewportH = full available column height
  //   cardH     = 50% of viewportH — leaves clear peek above/below
  //   stride    = 30% of viewportH
  //   cardW     = 84% of column width, clamped [120, 280]
  static ({double cardW, double cardH, double stride, double viewportH}) _dims(
    Size size, {
    bool fill = false,
  }) {
    if (fill) {
      final viewportH = size.height;
      final cardH = (viewportH * 0.50).clamp(60.0, 220.0);
      final stride = viewportH * 0.30;
      final cardW = (size.width * 0.84).clamp(120.0, 280.0);
      return (cardW: cardW, cardH: cardH, stride: stride, viewportH: viewportH);
    }
    final viewportH = (size.height * 0.25).clamp(140.0, 240.0);
    final cardH = viewportH * 0.56;
    final stride = viewportH * 0.44;
    final cardW = (size.width * 0.60).clamp(160.0, 300.0);
    return (cardW: cardW, cardH: cardH, stride: stride, viewportH: viewportH);
  }

  // Build cards sorted so the center card is the last child of the Stack
  // (painted on top). Cards are only rendered if within ±2 of center.
  List<Widget> _buildCards({
    required double cardW,
    required double cardH,
    required double stride,
  }) {
    final count = widget.templates.length;
    final indices = List.generate(count, (i) => i)
      ..sort((a, b) {
        final da = (a - _page).abs();
        final db = (b - _page).abs();
        return db.compareTo(da); // furthest first → painted behind
      });

    return indices.where((i) => (i - _page).abs() < 2.6).map((i) {
      final offset = i - _page;
      final dist = offset.abs().clamp(0.0, 2.5);
      final scale = (1.0 - dist * 0.12).clamp(0.74, 1.0);
      final tiltX = (offset * 0.38).clamp(-0.95, 0.95);
      final translateY = offset * stride;
      final translateX = dist * 6.0;
      final isSelected = i == _page.round();

      return Transform.translate(
        offset: Offset(translateX, translateY),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(tiltX),
          child: Transform.scale(
            scale: scale,
            child: GestureDetector(
              onTap: () => _animateTo(i),
              child: SizedBox(
                width: cardW,
                height: cardH,
                child: _PresetCard(
                  key: ValueKey('card_${widget.templates[i].slug}'),
                  template: widget.templates[i],
                  isSelected: isSelected,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final templates = widget.templates;
    final selectedIndex = widget.selectedIndex;

    // ── landscape side-by-side: fill the left column ──────────────────────
    if (widget.fillHeight) {
      return Container(
        color: _darkBg,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final d = _dims(constraints.biggest, fill: true);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        'CHANNELS',
                        style: GoogleFonts.teko(
                          fontSize: 11,
                          letterSpacing: 3,
                          color: const Color(0xFF555555),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (templates.isNotEmpty)
                        Text(
                          '${selectedIndex + 1} / ${templates.length}',
                          style: GoogleFonts.dmMono(
                            fontSize: 10,
                            color: const Color(0xFF444444),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (templates.isEmpty)
                  const Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.2,
                          color: Color(0xFF444444),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ClipRect(
                      clipper: const _VerticalOnlyClipper(),
                      child: GestureDetector(
                        onVerticalDragUpdate: (u) =>
                            _onDragUpdate(u, stride: d.stride),
                        onVerticalDragEnd: _onDragEnd,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: _buildCards(
                            cardW: d.cardW,
                            cardH: d.cardH,
                            stride: d.stride,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (templates.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(templates.length, (i) {
                        final active = i == selectedIndex;
                        final accent = _hexColor(templates[i].themeColor);
                        return GestureDetector(
                          onTap: () => _animateTo(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 22 : 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: active ? accent : const Color(0xFF2E2E2E),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }),
                    ),
                  )
                else
                  const SizedBox(height: 14),
              ],
            );
          },
        ),
      );
    }

    // ── portrait: proportional sizing off screen dimensions ───────────────
    final d = _dims(MediaQuery.sizeOf(context));

    return Container(
      color: _darkBg,
      child: Column(
        children: [
          // Label row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Text(
                  'CHANNELS',
                  style: GoogleFonts.teko(
                    fontSize: 11,
                    letterSpacing: 3,
                    color: const Color(0xFF555555),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (templates.isNotEmpty)
                  Text(
                    '${selectedIndex + 1} / ${templates.length}',
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: const Color(0xFF444444),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Carousel
          if (templates.isEmpty)
            SizedBox(
              height: d.viewportH,
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.2,
                    color: Color(0xFF444444),
                  ),
                ),
              ),
            )
          else
            ClipRect(
              clipper: const _VerticalOnlyClipper(),
              child: GestureDetector(
                onVerticalDragUpdate: (u) => _onDragUpdate(u, stride: d.stride),
                onVerticalDragEnd: _onDragEnd,
                child: SizedBox(
                  height: d.viewportH,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: _buildCards(
                      cardW: d.cardW,
                      cardH: d.cardH,
                      stride: d.stride,
                    ),
                  ),
                ),
              ),
            ),

          // Pill indicators
          if (templates.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(templates.length, (i) {
                  final active = i == selectedIndex;
                  final accent = _hexColor(templates[i].themeColor);
                  return GestureDetector(
                    onTap: () => _animateTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 22 : 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: active ? accent : const Color(0xFF2E2E2E),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              ),
            )
          else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preset card
// ─────────────────────────────────────────────────────────────────────────────

// Each card owns an AnimationController that drives a CustomPainter.
// The painter draws two opaque radial-gradient blobs that drift via sin/cos,
// giving every card a unique movement pattern based on its notchIndex seed.
// This is fully pixel-opaque — no third-party shader blending issues.
class _PresetCard extends StatefulWidget {
  const _PresetCard({
    super.key,
    required this.template,
    required this.isSelected,
  });

  final PresetTemplate template;
  final bool isSelected;

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  double get _seed => widget.template.notchIndex.toDouble();

  @override
  void initState() {
    super.initState();
    // Each card loops at a slightly different speed (9–14 s) so they drift
    // out of phase with each other across the carousel.
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 9000 + (_seed.toInt() % 6) * 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _hexColor(widget.template.themeColor);
    final isSelected = widget.isSelected;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isSelected ? 1.10 : 1.0),
      duration: const Duration(milliseconds: 420),
      // easeOutBack overshoots slightly on the way up → balloon pop feel
      // easeInCubic on the way down → quick, clean deflation
      curve: isSelected ? Curves.easeOutBack : Curves.easeInCubic,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.55)
                : const Color(0xFF252525),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 14,
              spreadRadius: -5,
              offset: const Offset(0, 7),
            ),
            if (isSelected)
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 30,
                spreadRadius: -4,
                offset: const Offset(0, 12),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => CustomPaint(
                painter: _CardGradientPainter(
                  t: _ctrl.value * (_ctrl.duration!.inMilliseconds / 1000.0),
                  seed: _seed,
                  baseColor: accent,
                  style: widget.template.notchIndex % 4,
                ),
                child: child,
              ),
              child: Stack(
                children: [
                  // Corner accent glow
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            accent.withValues(alpha: isSelected ? 0.20 : 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Card content — LayoutBuilder lets the column detect tight
                  // landscape height (<90px) and switch to a compact layout that
                  // drops the description and reduces padding/font so nothing overflows.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxHeight < 90;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          compact ? 8 : 14,
                          16,
                          compact ? 8 : 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _Badge(
                                  label: '${widget.template.notchIndex + 1}',
                                  accent: accent,
                                  filled: false,
                                ),
                                if (widget.template.isDefault) ...[
                                  const SizedBox(width: 6),
                                  const _Badge(
                                    label: 'DEFAULT',
                                    accent: Color(0xFF555555),
                                    filled: false,
                                  ),
                                ],
                              ],
                            ),
                            compact
                                ? const SizedBox(height: 4)
                                : const Spacer(),
                            Text(
                              widget.template.name.toUpperCase(),
                              style: GoogleFonts.teko(
                                fontSize: compact ? 20 : 28,
                                height: 0.92,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!compact &&
                                widget.template.description != null &&
                                widget.template.description!.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                widget.template.description!,
                                style: GoogleFonts.dmMono(
                                  fontSize: 9,
                                  color: const Color(0xFF888888),
                                  height: 1.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Four distinct gradient styles, each using a colour palette derived from the

// card's themeColor so every card looks like it belongs to its own colour world.
//
// Style assignment: notchIndex % 4
//   0 → mesh   — two radial blobs drifting in Lissajous orbits
//   1 → wave   — three fluid sine-wave bands undulating top-to-bottom
//   2 → spot   — a sweeping directional spotlight cone
//   3 → plasma — three overlapping circles of different sizes
//
// Palette (all fully opaque — derived from baseColor):
//   _base  = baseColor darkened 82% → very dark tint of the hue
//   _mid   = baseColor darkened 50% → visible coloured shadow
//   _hi    = baseColor lightened 20% → saturated highlight
class _CardGradientPainter extends CustomPainter {
  const _CardGradientPainter({
    required this.t,
    required this.seed,
    required this.baseColor,
    required this.style,
  });

  final double t;
  final double seed;
  final Color baseColor;
  final int style;

  static const _black = Color(0xFF000000);
  static const _white = Color(0xFFFFFFFF);

  Color get _base => Color.lerp(baseColor, _black, 0.82)!;
  Color get _mid => Color.lerp(baseColor, _black, 0.50)!;
  Color get _hi => Color.lerp(baseColor, _white, 0.20)!;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Always start with a fully opaque base fill in the darkest hue tone
    canvas.drawRect(Offset.zero & size, Paint()..color = _base);

    switch (style % 4) {
      case 0:
        _paintMesh(canvas, size);
      case 1:
        _paintWave(canvas, size);
      case 2:
        _paintSpot(canvas, size);
      case _:
        _paintPlasma(canvas, size);
    }
  }

  // ── Style 0: Mesh ──────────────────────────────────────────────────────────
  // Two radial blobs of the card's palette drifting on independent Lissajous
  // orbits.  Seed offsets each card's phase by ~π/4.
  void _paintMesh(Canvas canvas, Size size) {
    final s = seed * 0.785;
    final x1 =
        size.width * ((math.sin(t * 0.38 + s) * 0.5 + 0.5) * 0.70 + 0.15);
    final y1 =
        size.height *
        ((math.cos(t * 0.29 + s + 1.0) * 0.5 + 0.5) * 0.70 + 0.15);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader =
            RadialGradient(
              colors: [_hi, _mid, _base],
              stops: const [0.0, 0.42, 1.0],
            ).createShader(
              Rect.fromCenter(
                center: Offset(x1, y1),
                width: size.width * 1.9,
                height: size.height * 1.9,
              ),
            ),
    );
    final x2 =
        size.width *
        ((math.cos(t * 0.51 + s + 2.09) * 0.5 + 0.5) * 0.65 + 0.17);
    final y2 =
        size.height *
        ((math.sin(t * 0.43 + s + 0.78) * 0.5 + 0.5) * 0.65 + 0.17);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader =
            RadialGradient(
              colors: [_mid, _base],
              stops: const [0.0, 1.0],
            ).createShader(
              Rect.fromCenter(
                center: Offset(x2, y2),
                width: size.width * 1.3,
                height: size.height * 1.3,
              ),
            ),
    );
  }

  // ── Style 1: Fluid wave ────────────────────────────────────────────────────
  // Three sinusoidal horizontal bands that undulate at different speeds,
  // creating a liquid surface effect in the card's colour.
  void _paintWave(Canvas canvas, Size size) {
    final s = seed * 0.785;
    const bandCount = 3;
    for (var i = 0; i < bandCount; i++) {
      final phase = i * (math.pi * 2 / bandCount);
      final bandY =
          size.height *
          (i / (bandCount - 1.0) +
              math.sin(t * (0.28 + i * 0.07) + s + phase) * 0.12);
      final bandH = size.height * 0.55;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader =
              LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _base.withValues(alpha: 0.0),
                  (i == 1 ? _hi : _mid).withValues(alpha: 0.75),
                  _base.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(
                Rect.fromCenter(
                  center: Offset(size.width / 2, bandY),
                  width: size.width,
                  height: bandH,
                ),
              ),
      );
    }
  }

  // ── Style 2: Spotlight ─────────────────────────────────────────────────────
  // A single light source that sweeps slowly across the top of the card,
  // casting a coloured cone downward.
  void _paintSpot(Canvas canvas, Size size) {
    final s = seed * 0.785;
    final sx =
        size.width * (0.25 + 0.55 * (math.sin(t * 0.22 + s) * 0.5 + 0.5));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment((sx / size.width) * 2 - 1, -1),
          radius: 1.4,
          colors: [_hi, _mid, _base],
          stops: const [0.0, 0.38, 1.0],
        ).createShader(Offset.zero & size),
    );
    // Soft underside — makes the cone feel volumetric
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_base.withValues(alpha: 0.0), _base.withValues(alpha: 0.55)],
        ).createShader(Offset.zero & size),
    );
  }

  // ── Style 3: Plasma ────────────────────────────────────────────────────────
  // Three overlapping radial circles of different sizes and speeds,
  // blending into each other for an organic cellular look.
  void _paintPlasma(Canvas canvas, Size size) {
    final s = seed * 0.785;

    final circles = [
      (
        cx: (math.sin(t * 0.31 + s) * 0.5 + 0.5) * 0.8 + 0.1,
        cy: (math.cos(t * 0.24 + s + 1.0) * 0.5 + 0.5) * 0.8 + 0.1,
        r: 1.55,
        c: _hi,
      ),
      (
        cx: (math.cos(t * 0.47 + s + 2.1) * 0.5 + 0.5) * 0.7 + 0.15,
        cy: (math.sin(t * 0.36 + s + 0.8) * 0.5 + 0.5) * 0.7 + 0.15,
        r: 1.1,
        c: _mid,
      ),
      (
        cx: (math.sin(t * 0.59 + s + 4.2) * 0.5 + 0.5) * 0.6 + 0.2,
        cy: (math.cos(t * 0.41 + s + 3.1) * 0.5 + 0.5) * 0.6 + 0.2,
        r: 0.85,
        c: _hi,
      ),
    ];

    for (final c in circles) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader =
              RadialGradient(
                colors: [c.c, _mid, _base],
                stops: const [0.0, 0.4, 1.0],
              ).createShader(
                Rect.fromCenter(
                  center: Offset(c.cx * size.width, c.cy * size.height),
                  width: size.width * c.r,
                  height: size.height * c.r,
                ),
              ),
      );
    }
  }

  @override
  bool shouldRepaint(_CardGradientPainter old) =>
      old.t != t ||
      old.seed != seed ||
      old.baseColor != baseColor ||
      old.style != style;
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.accent,
    required this.filled,
  });

  final String label;
  final Color accent;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? accent : accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: filled
            ? null
            : Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : accent,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arch divider — dark-to-white transition with a soft convex arc + accent line
// ─────────────────────────────────────────────────────────────────────────────

class _ArchDivider extends StatelessWidget {
  const _ArchDivider({required this.accentColor});
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: AnimatedCustomPaint(accentColor: accentColor),
    );
  }
}

class AnimatedCustomPaint extends StatelessWidget {
  const AnimatedCustomPaint({super.key, required this.accentColor});
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArchPainter(accentColor: accentColor),
      child: const SizedBox.expand(),
    );
  }
}

class _ArchPainter extends CustomPainter {
  const _ArchPainter({required this.accentColor});
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Dark fill (top half — extending from the carousel background)
    final darkPaint = Paint()..color = const Color(0xFF080808);
    final darkPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.5)
      ..quadraticBezierTo(
        size.width / 2,
        size.height * 1.4,
        0,
        size.height * 0.5,
      )
      ..close();
    canvas.drawPath(darkPath, darkPaint);

    // Accent arc line
    final linePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final linePath = Path()
      ..moveTo(0, size.height * 0.5)
      ..quadraticBezierTo(
        size.width / 2,
        size.height * 1.4,
        size.width,
        size.height * 0.5,
      );
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(_ArchPainter old) => old.accentColor != accentColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sources section
// ─────────────────────────────────────────────────────────────────────────────

class _SourcesSection extends ConsumerStatefulWidget {
  const _SourcesSection({
    super.key,
    required this.template,
    required this.query,
    required this.searchCtrl,
  });

  final PresetTemplate template;
  final String query;
  final TextEditingController searchCtrl;

  @override
  ConsumerState<_SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends ConsumerState<_SourcesSection> {
  final _scrollCtrl = ScrollController();
  bool _showTopBtn = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.hasClients && _scrollCtrl.offset > 180;
      if (show != _showTopBtn) setState(() => _showTopBtn = show);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final accent = _hexColor(widget.template.themeColor);
    final sourcesAsync = ref.watch(
      channelSourcesProvider(widget.template.slug),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SOURCES',
                  style: GoogleFonts.teko(
                    fontSize: 15,
                    letterSpacing: 2,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _InlineSearch(controller: widget.searchCtrl, accent: accent),
            ],
          ),
        ),
        const Divider(color: Color(0xFFEEEEEE), height: 1),

        // Source list + back-to-top FAB overlay
        Expanded(
          child: sourcesAsync.when(
            loading: () => Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: accent,
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (sources) {
              var visible = sources.where((s) => s.enabled).toList();
              if (widget.query.isNotEmpty) {
                visible = visible
                    .where(
                      (s) => s.displayName.toLowerCase().contains(widget.query),
                    )
                    .toList();
              }
              visible.sort(
                (a, b) => a.displayName.toLowerCase().compareTo(
                  b.displayName.toLowerCase(),
                ),
              );

              if (visible.isEmpty) {
                return Center(
                  child: Text(
                    widget.query.isNotEmpty
                        ? 'No sources match "${widget.query}"'
                        : 'No sources in this channel yet',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: const Color(0xFFAAAAAA),
                    ),
                  ),
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 72),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _SourceRow(
                      source: visible[i],
                      accent: accent,
                      index: i,
                    ),
                  ),
                  // Back-to-top FAB
                  Positioned(
                    bottom: 16,
                    right: isLandscape ? -25 : 16,
                    child: AnimatedOpacity(
                      opacity: _showTopBtn ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: !_showTopBtn,
                        child: GestureDetector(
                          onTap: _scrollToTop,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0A0A),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent.withValues(alpha: 0.6),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline search
// ─────────────────────────────────────────────────────────────────────────────

class _InlineSearch extends StatelessWidget {
  const _InlineSearch({required this.controller, required this.accent});
  final TextEditingController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 30,
      child: TextField(
        controller: controller,
        style: GoogleFonts.dmMono(fontSize: 11, color: Colors.black),
        decoration: InputDecoration(
          hintText: 'Search sources…',
          hintStyle: GoogleFonts.dmMono(
            fontSize: 11,
            color: const Color(0xFFBBBBBB),
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 14,
            color: Color(0xFF999999),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? GestureDetector(
                  onTap: controller.clear,
                  child: const Icon(
                    Icons.close,
                    size: 13,
                    color: Color(0xFF999999),
                  ),
                )
              : null,
          contentPadding: EdgeInsets.zero,
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF4F4F4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: accent, width: 1),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source row — redesigned card with 3D-aware entrance offset
// ─────────────────────────────────────────────────────────────────────────────

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.accent,
    required this.index,
  });

  final PresetSource source;
  final Color accent;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFECECEC), width: 1),
      ),
      child: Row(
        children: [
          // Avatar with accent left bar
          Stack(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F4F4),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  source.displayName.isNotEmpty
                      ? source.displayName[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.teko(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF555555),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 6,
                bottom: 6,
                child: Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // Name + handles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        source.displayName,
                        style: GoogleFonts.archivo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (source.manuallyVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 12, color: accent),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    if (source.soundcloudUsername != null)
                      _HandleChip(
                        icon: Icons.headphones_rounded,
                        label: '@${source.soundcloudUsername}',
                        color: const Color(0xFFFF5500),
                        url: source.soundcloudUrl,
                      ),
                    if (source.bandcampUrl != null)
                      _HandleChip(
                        icon: Icons.album_rounded,
                        label: 'Bandcamp',
                        color: const Color(0xFF4E9A06),
                        url: source.bandcampUrl,
                      ),
                    if (source.youtubeUrl != null)
                      _HandleChip(
                        icon: Icons.play_circle_outline_rounded,
                        label: 'YouTube',
                        color: const Color(0xFFFF4444),
                        url: source.youtubeUrl,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Handle chip (unchanged contract, rounded icons)
// ─────────────────────────────────────────────────────────────────────────────

class _HandleChip extends StatelessWidget {
  const _HandleChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.url,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return GestureDetector(
      onTap: hasUrl
          ? () =>
                launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 9,
              color: hasUrl ? color : const Color(0xFFAAAAAA),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (hasUrl) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.open_in_new,
              size: 9,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility
// ─────────────────────────────────────────────────────────────────────────────
// Clips only the top and bottom edges of the carousel viewport.
// The horizontal bounds are extended far beyond the screen so scaled/tilted
// cards are never clipped on their left or right sides.
class _VerticalOnlyClipper extends CustomClipper<Rect> {
  const _VerticalOnlyClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(-9999, 0, size.width + 9999 * 2, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────

Color _hexColor(String hex) {
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length != 6) return XeneTheme.teal;
  final value = int.tryParse('FF$h', radix: 16);
  return value != null ? Color(value) : XeneTheme.teal;
}
