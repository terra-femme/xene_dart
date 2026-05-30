import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _orange = Color(0xFFFF5500);
  static const _teal = Color(0xFF00C5A5);
  static const _ink = Color(0xFF111111);
  static const _muted = Color(0xFF777777);
  static const _paper = Color(0xFFFAFAF7);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _paper,
      child: Stack(
        children: [
          const Positioned.fill(child: _AboutBackground()),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 40 : 20,
                  isWide ? 30 : 22,
                  isWide ? 40 : 20,
                  72,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _IssueBar(),
                        const SizedBox(height: 24),
                        _HeroBlock(isWide: isWide),
                        const SizedBox(height: 28),
                        _MissionBody(isWide: isWide),
                        const SizedBox(height: 28),
                        const _DividerRule(),
                        const SizedBox(height: 22),
                        const _ClosingLine(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AboutBackground extends StatelessWidget {
  const _AboutBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.16,
        child: Lottie.asset(
          'assets/animations/aboutBG.lottie',
          fit: BoxFit.cover,
          repeat: true,
        ),
      ),
    );
  }
}

class _IssueBar extends StatelessWidget {
  const _IssueBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AboutScreen._ink, width: 1.3),
          bottom: BorderSide(color: AboutScreen._ink, width: 1.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            'XENE',
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AboutScreen._ink,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: Color(0xFFD8D8D2), height: 1)),
          const SizedBox(width: 10),
          Text(
            'SCENE / XENE',
            style: GoogleFonts.dmMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AboutScreen._orange,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final masthead = Text(
      'A PLACE FOR THE SCENE TO FIND ITSELF.',
      style: GoogleFonts.teko(
        fontSize: isWide ? 78 : 48,
        height: 0.88,
        fontWeight: FontWeight.w600,
        color: AboutScreen._ink,
      ),
    );

    final deck = Text(
      'Xene is inspired by magazines, liner notes, local flyers, record shops, '
      'late-night links, and the stubborn feeling that small scenes deserve '
      'more than an algorithmic afterthought.',
      style: GoogleFonts.archivo(
        fontSize: isWide ? 17 : 14,
        height: 1.55,
        color: const Color(0xFF303030),
      ),
    );

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          masthead,
          const SizedBox(height: 18),
          const _AnimationWindow(),
          const SizedBox(height: 18),
          deck,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [masthead, const SizedBox(height: 18), deck],
          ),
        ),
        const SizedBox(width: 30),
        const Expanded(flex: 3, child: _AnimationWindow()),
      ],
    );
  }
}

class _AnimationWindow extends StatelessWidget {
  const _AnimationWindow();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.82,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AboutScreen._ink, width: 1.4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 0,
              offset: Offset(8, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4EF),
                    border: Border.all(color: const Color(0xFFE0E0DA)),
                  ),
                  child: Center(
                    child: Lottie.asset(
                      'assets/animations/aboutBG.lottie',
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              top: 10,
              child: Text(
                'ART SLOT',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AboutScreen._teal,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 10,
              child: Text(
                'LOTTIE READY',
                style: GoogleFonts.dmMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AboutScreen._muted,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionBody extends StatelessWidget {
  const _MissionBody({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final lead = _PullQuote(
      text:
          'Independent artists and small labels should not need a marketing '
          'budget to be legible, remembered, or passed along.',
      isWide: isWide,
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _BodyText(
          'The internet is full of brilliant fragments: a Bandcamp drop, a '
          'SoundCloud repost, a YouTube set, a flyer, a tiny interview, a cover '
          'artist, a label page, a friend who always knows what is next. Xene '
          'exists to gather those fragments without sanding off their edges.',
        ),
        SizedBox(height: 16),
        _BodyText(
          'It is a discovery feed, but the mission is bigger than aggregation. '
          'Xene is being built as a hub for independent music culture: a place '
          'where releases, mixes, labels, visual artists, collectives, and '
          'listeners can start to feel connected instead of scattered.',
        ),
        SizedBox(height: 16),
        _BodyText(
          'The long-term dream is simple: help passionate people get the right '
          'kind of exposure. Not empty virality. Not pay-to-be-seen campaigns. '
          'Just better context, better pathways, and more chances for the right '
          'person to find the work that would have moved them all along.',
        ),
      ],
    );

    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
          const SizedBox(height: 20),
          copy,
          const SizedBox(height: 24),
          const _PrinciplesGrid(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: lead),
        const SizedBox(width: 30),
        Expanded(flex: 5, child: copy),
        const SizedBox(width: 26),
        const Expanded(flex: 3, child: _PrinciplesGrid()),
      ],
    );
  }
}

class _PullQuote extends StatelessWidget {
  const _PullQuote({required this.text, required this.isWide});

  final String text;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isWide ? 18 : 16),
      decoration: const BoxDecoration(
        color: AboutScreen._ink,
        border: Border(left: BorderSide(color: AboutScreen._orange, width: 5)),
      ),
      child: Text(
        text,
        style: GoogleFonts.teko(
          fontSize: isWide ? 30 : 26,
          height: 1.02,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.archivo(
        fontSize: 14,
        height: 1.68,
        color: const Color(0xFF2E2E2E),
      ),
    );
  }
}

class _PrinciplesGrid extends StatelessWidget {
  const _PrinciplesGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _PrincipleCard(
          index: '01',
          title: 'SEE THE SMALLER SIGNALS',
          body:
              'Track the releases, reposts, interviews, and side channels that '
              'usually disappear between platforms.',
        ),
        SizedBox(height: 10),
        _PrincipleCard(
          index: '02',
          title: 'CONNECT THE MAKERS',
          body:
              'Make room for labels, producers, visual artists, writers, and '
              'listeners to find useful overlap.',
        ),
        SizedBox(height: 10),
        _PrincipleCard(
          index: '03',
          title: 'FEEL LIKE A MAGAZINE',
          body:
              'Treat discovery as culture, not inventory: edited, contextual, '
              'curious, and worth returning to.',
        ),
      ],
    );
  }
}

class _PrincipleCard extends StatelessWidget {
  const _PrincipleCard({
    required this.index,
    required this.title,
    required this.body,
  });

  final String index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCDCD5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                index,
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AboutScreen._orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.teko(
                    fontSize: 18,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: AboutScreen._ink,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.archivo(
              fontSize: 11,
              height: 1.5,
              color: AboutScreen._muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerRule extends StatelessWidget {
  const _DividerRule();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 42, height: 5, color: AboutScreen._orange),
        const SizedBox(width: 8),
        Container(width: 42, height: 5, color: AboutScreen._teal),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: AboutScreen._ink, height: 1)),
      ],
    );
  }
}

class _ClosingLine extends StatelessWidget {
  const _ClosingLine();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Xene is for the people making the work, the people documenting it, '
      'and the people who still believe scenes are built by attention.',
      style: GoogleFonts.teko(
        fontSize: 28,
        height: 1.08,
        fontWeight: FontWeight.w500,
        color: AboutScreen._ink,
      ),
    );
  }
}
