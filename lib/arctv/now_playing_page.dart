// ArcTV 27 — full-screen Now Playing with album art and synced lyrics. GPL-3.0-or-later.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'arctv_service.dart';
import 'liquid_glass.dart';
import 'lyrics.dart';

bool _nowPlayingOpen = false;

Future<void> openNowPlaying(BuildContext context) async {
  if (_nowPlayingOpen) return;
  _nowPlayingOpen = true;
  try {
    await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const NowPlayingPage(),
      transitionsBuilder: (_, anim, __, child) {
        final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(c), child: child),
        );
      },
    ));
  } finally {
    _nowPlayingOpen = false;
  }
}

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ArcTvService>();
    final np = svc.nowPlaying;
    final art = np.artwork;
    final pos = np.position;
    final lyricPos = pos + Duration(milliseconds: svc.lyricsOffsetMs);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background: the cover, hugely blurred — Apple Music on tvOS.
          if (art != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.decal),
              child: Transform.scale(scale: 1.3, child: Image.memory(art, fit: BoxFit.cover, gaplessPlayback: true)),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2B1D3C), Color(0xFF0E1A2B), Color(0xFF000000)],
                ),
              ),
            ),
          Container(color: Colors.black.withValues(alpha: 0.38)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(64, 40, 48, 36),
              child: !np.active
                  ? _idle(context)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 5, child: _left(context, svc, np, pos)),
                        const SizedBox(width: 56),
                        Expanded(flex: 6, child: _LyricsView(svc: svc, position: lyricPos)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _idle(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.airplay, size: 72, color: Colors.white70),
            const SizedBox(height: 18),
            const Text('Nothing playing', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            Text('Choose this TV from AirPlay on your iPhone, iPad or Mac.',
                style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.7))),
            const SizedBox(height: 26),
            GlassButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      );

  Widget _left(BuildContext context, ArcTvService svc, NowPlaying np, Duration pos) {
    final dur = np.duration;
    final progress = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0).toDouble() : 0.0;
    return LayoutBuilder(builder: (context, c) {
      final side = (c.maxHeight * 0.56).clamp(160.0, c.maxWidth).toDouble();
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedScale(
            scale: np.isPlaying ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 18))],
                color: Colors.white10,
              ),
              clipBehavior: Clip.antiAlias,
              child: np.artwork != null
                  ? Image.memory(np.artwork!, fit: BoxFit.cover, gaplessPlayback: true)
                  : const Icon(Icons.music_note, size: 96, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 26),
          Text(np.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text([np.artist, np.album].where((s) => s.isNotEmpty).join(' — '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 19, color: Colors.white.withValues(alpha: 0.72))),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(_fmt(pos), style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.65))),
              const Spacer(),
              Text(dur > Duration.zero ? '-${_fmt(dur - pos)}' : '',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.65))),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              GlassButton.icon(icon: Icons.skip_previous_rounded, size: 56, onPressed: () => svc.control('previous')),
              const SizedBox(width: 18),
              GlassButton.icon(
                icon: np.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 68,
                autofocus: true,
                onPressed: () => svc.control('toggle'),
              ),
              const SizedBox(width: 18),
              GlassButton.icon(icon: Icons.skip_next_rounded, size: 56, onPressed: () => svc.control('next')),
              const Spacer(),
              if (np.isAirPlay)
                Row(children: [
                  Icon(Icons.airplay, size: 18, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text('AirPlay', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                ]),
            ],
          ),
        ],
      );
    });
  }
}

class _LyricsView extends StatefulWidget {
  final ArcTvService svc;
  final Duration position;

  const _LyricsView({required this.svc, required this.position});

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = const [];
  Lyrics? _bound;
  int _current = -2;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys(Lyrics l) {
    if (identical(l, _bound)) return;
    _bound = l;
    _keys = List.generate(l.lines.length, (_) => GlobalKey());
    _current = -2;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _follow(int index) {
    if (index == _current) return;
    _current = index;
    if (index < 0 || index >= _keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          alignment: 0.32, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    final lyrics = svc.lyrics;
    final dim = TextStyle(fontSize: 22, color: Colors.white.withValues(alpha: 0.6));

    if (svc.lyricsLoading) return Center(child: Text('Loading lyrics…', style: dim));
    if (lyrics == null || lyrics.isEmpty) {
      return Center(child: Text('No lyrics available', style: dim));
    }
    if (lyrics.instrumental) return Center(child: Text('♪ Instrumental ♪', style: dim));
    if (!lyrics.synced) {
      return ShaderMask(
        shaderCallback: _fade,
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Text(lyrics.plain ?? '',
              style: const TextStyle(fontSize: 26, height: 1.5, fontWeight: FontWeight.w600, color: Colors.white70)),
        ),
      );
    }

    _syncKeys(lyrics);
    final idx = lyrics.indexAt(widget.position);
    _follow(idx);

    return ShaderMask(
      shaderCallback: _fade,
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(vertical: MediaQuery.of(context).size.height * 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lyrics.lines.length; i++)
              Padding(
                key: _keys[i],
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _LyricLineText(
                  text: lyrics.lines[i].text.isEmpty ? '♪' : lyrics.lines[i].text,
                  distance: idx < 0 ? i + 1 : (i - idx),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Shader _fade(Rect r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.18, 0.78, 1.0],
      ).createShader(r);
}

class _LyricLineText extends StatelessWidget {
  final String text;
  final int distance; // 0 = current line, negative = sung, positive = upcoming

  const _LyricLineText({required this.text, required this.distance});

  @override
  Widget build(BuildContext context) {
    final current = distance == 0;
    final alpha = current ? 1.0 : (distance < 0 ? 0.28 : (0.55 - 0.06 * distance).clamp(0.22, 0.55).toDouble());
    return AnimatedScale(
      scale: current ? 1.0 : 0.94,
      alignment: Alignment.centerLeft,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 360),
        style: TextStyle(
          fontSize: 36,
          height: 1.22,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: alpha),
          shadows: current ? const [Shadow(color: Color(0x66FFFFFF), blurRadius: 18)] : const [],
        ),
        child: Text(text),
      ),
    );
  }
}
