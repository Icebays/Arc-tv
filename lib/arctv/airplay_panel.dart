// ArcTV 27 — AirPlay setup sheet + top-bar controls. GPL-3.0-or-later.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/launcher_state.dart';
import 'arctv_service.dart';
import 'liquid_glass.dart';
import 'now_playing_page.dart';
import 'smart_home_panel.dart';

Future<void> showAirPlayPanel(BuildContext context) {
  context.read<ArcTvService>().refreshStatus();
  return showDialog(context: context, builder: (_) => const AirPlayPanel());
}

class AirPlayPanel extends StatefulWidget {
  const AirPlayPanel({super.key});

  @override
  State<AirPlayPanel> createState() => _AirPlayPanelState();
}

class _AirPlayPanelState extends State<AirPlayPanel> with WidgetsBindingObserver {
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the package installer / system settings: re-check.
    if (state == AppLifecycleState.resumed) context.read<ArcTvService>().refreshStatus();
  }

  Future<void> _install(ArcTvService svc) async {
    final r = await svc.installAirPlay();
    if (!mounted) return;
    setState(() {
      _note = switch (r) {
        'started' => 'Confirm the installation, then come back here and press “Open AirPlay receiver” once.',
        'permission' => 'Allow “Install unknown apps” for ArcTV 27, then press Install again.',
        'missing' => 'This build has no bundled receiver. Install the AirPlay Receiver APK manually.',
        _ => 'Installation could not start.',
      };
    });
  }

  Future<void> _mediaAccess(ArcTvService svc) async {
    final ok = await svc.openMediaListenerSettings();
    if (!mounted || ok) return;
    setState(() => _note = 'This TV hides that setting. From a computer run:\n'
        'adb shell cmd notification allow_listener com.omeda.arc/com.omeda.arc.ArcMediaListenerService');
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<ArcTvService>();
    final np = svc.nowPlaying;
    final sub = TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15);

    Widget statusRow(IconData icon, Color color, String title, String body) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body, style: sub),
              ]),
            ),
          ],
        );

    final buttons = <Widget>[
      if (np.active)
        GlassButton(
          autofocus: true,
          onPressed: () {
            final nav = Navigator.of(context, rootNavigator: true);
            nav.pop();
            openNowPlaying(nav.context);
          },
          child: const Text('Now Playing', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      if (!svc.airPlayInstalled)
        GlassButton(
          autofocus: !np.active,
          onPressed: () => _install(svc),
          child: const Text('Install AirPlay receiver', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        )
      else
        GlassButton(
          autofocus: !np.active,
          onPressed: svc.openAirPlay,
          child: const Text('Open AirPlay receiver', style: TextStyle(fontSize: 17)),
        ),
      GlassButton(
        onPressed: () => _mediaAccess(svc),
        child: Text(svc.mediaListenerAccess ? 'Other apps: allowed' : 'Show other apps’ music',
            style: const TextStyle(fontSize: 17)),
      ),
    ];

    return GlassDialog(
      title: 'AirPlay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          svc.airPlayInstalled
              ? statusRow(Icons.check_circle, Colors.greenAccent, 'Receiver installed',
                  'Pick this TV from Control Center → Screen Mirroring, or the AirPlay button in Music. '
                  'Open the receiver once and allow “Display over other apps” so mirroring can take over the screen.')
              : statusRow(Icons.airplay, Colors.white, 'AirPlay receiver not installed',
                  'The launcher bundles an open-source AirPlay 2 receiver (UxPlay engine) for mirroring and music.'),
          const SizedBox(height: 14),
          statusRow(Icons.music_note, Colors.white, 'Music & lyrics',
              'Album art, controls and time-synced lyrics open automatically when music is AirPlayed here.'),
          const SizedBox(height: 22),
          Wrap(spacing: 14, runSpacing: 14, children: buttons),
          const SizedBox(height: 22),
          Row(
            children: [
              Text('Lyrics timing', style: sub),
              const SizedBox(width: 14),
              GlassButton.icon(
                  icon: Icons.remove, size: 38, onPressed: () => svc.setLyricsOffsetMs(svc.lyricsOffsetMs - 250)),
              const SizedBox(width: 10),
              SizedBox(
                width: 72,
                child: Text('${svc.lyricsOffsetMs >= 0 ? '+' : ''}${(svc.lyricsOffsetMs / 1000).toStringAsFixed(2)}s',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              GlassButton.icon(
                  icon: Icons.add, size: 38, onPressed: () => svc.setLyricsOffsetMs(svc.lyricsOffsetMs + 250)),
              const SizedBox(width: 24),
              Text('Auto-open', style: sub),
              Switch(value: svc.autoOpenNowPlaying, onChanged: svc.setAutoOpenNowPlaying),
            ],
          ),
          if (_note != null) ...[
            const SizedBox(height: 16),
            Text(_note!, style: const TextStyle(color: Colors.amberAccent, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

/// Top-bar AirPlay control: an icon, or a glass "now playing" capsule while music plays.
class AirPlayStatusButton extends StatelessWidget {
  const AirPlayStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ArcTvService, (bool, String, String, bool)>(
      selector: (_, s) => (s.nowPlaying.active, s.nowPlaying.title, s.nowPlaying.artist, s.nowPlaying.isPlaying),
      builder: (context, d, _) {
        final (active, title, artist, playing) = d;
        void onFocus(bool f) {
          if (f) context.read<LauncherState>().setAppGridFocused(false);
        }

        if (!active) {
          return GlassButton.icon(
            icon: Icons.airplay,
            onFocusChange: onFocus,
            onPressed: () => showAirPlayPanel(context),
          );
        }
        return GlassButton(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          borderRadius: BorderRadius.circular(22),
          focusScale: 1.1,
          onFocusChange: onFocus,
          onPressed: () => openNowPlaying(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(playing ? Icons.graphic_eq : Icons.pause, size: 20),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  artist.isEmpty ? title : '$title · $artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Top-bar Home button.
class SmartHomeStatusButton extends StatelessWidget {
  const SmartHomeStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassButton.icon(
      icon: Icons.home_outlined,
      onFocusChange: (f) {
        if (f) context.read<LauncherState>().setAppGridFocused(false);
      },
      onPressed: () => showSmartHomePanel(context),
    );
  }
}
