// ArcTV 27 — AirPlay / now playing / launcher-intent state. GPL-3.0-or-later.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lyrics.dart';

class NowPlaying {
  static const int statePlaying = 3;

  final bool active;
  final String package;
  final bool isAirPlay;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int state;
  final int positionMs;
  final double speed;
  final DateTime anchor;
  final Uint8List? artwork;

  NowPlaying({
    this.active = false,
    this.package = '',
    this.isAirPlay = false,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
    this.state = 0,
    this.positionMs = 0,
    this.speed = 0,
    DateTime? anchor,
    this.artwork,
  }) : anchor = anchor ?? DateTime.now();

  bool get isPlaying => active && state == statePlaying;
  String get trackKey => '$title|$artist|$album';
  Duration get duration => Duration(milliseconds: durationMs);

  Duration get position {
    if (!active) return Duration.zero;
    var ms = positionMs;
    if (isPlaying) {
      ms += (DateTime.now().difference(anchor).inMilliseconds * (speed == 0 ? 1.0 : speed)).round();
    }
    if (durationMs > 0) ms = ms.clamp(0, durationMs).toInt();
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  factory NowPlaying.fromMap(Map<dynamic, dynamic> m, NowPlaying? previous) {
    if (m['active'] != true) return NowPlaying();
    final now = DateTime.now();
    final nowElapsed = (m['nowElapsed'] as num?)?.toInt() ?? 0;
    final updateTime = (m['updateTime'] as num?)?.toInt() ?? 0;
    final anchor = updateTime > 0 && nowElapsed >= updateTime
        ? now.subtract(Duration(milliseconds: nowElapsed - updateTime))
        : now;
    final np = NowPlaying(
      active: true,
      package: m['package'] as String? ?? '',
      isAirPlay: m['isAirPlay'] == true,
      title: m['title'] as String? ?? '',
      artist: m['artist'] as String? ?? '',
      album: m['album'] as String? ?? '',
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      state: (m['state'] as num?)?.toInt() ?? 0,
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      speed: (m['speed'] as num?)?.toDouble() ?? 1.0,
      anchor: anchor,
      artwork: m['artwork'] as Uint8List?,
    );
    // Reuse the previous byte buffer for the same cover so Image.memory doesn't flicker.
    if (previous != null &&
        previous.trackKey == np.trackKey &&
        previous.artwork != null &&
        np.artwork != null &&
        previous.artwork!.length == np.artwork!.length) {
      return np._withArtwork(previous.artwork);
    }
    return np;
  }

  NowPlaying _withArtwork(Uint8List? art) => NowPlaying(
        active: active,
        package: package,
        isAirPlay: isAirPlay,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        state: state,
        positionMs: positionMs,
        speed: speed,
        anchor: anchor,
        artwork: art,
      );
}

typedef HomeAssistantConfigCallback = void Function(String? url, String? token);

class ArcTvService extends ChangeNotifier {
  static const _method = MethodChannel('com.omeda.arc/arctv');
  static const _events = EventChannel('com.omeda.arc/arctv_media');
  static const _kLyricsOffset = 'arctv_lyrics_offset_ms';
  static const _kAutoOpen = 'arctv_auto_open_now_playing';

  final SharedPreferences _prefs;
  final LyricsClient _lyricsClient = LyricsClient();
  final StreamController<String> _openRequests = StreamController.broadcast();
  StreamSubscription? _mediaSub;

  HomeAssistantConfigCallback? onHomeAssistantConfig;

  NowPlaying _nowPlaying = NowPlaying();
  Lyrics? _lyrics;
  bool _lyricsLoading = false;
  String _lyricsKey = '';
  bool _airPlayInstalled = false;
  bool _bundledAirPlay = false;
  bool _mediaListenerAccess = false;
  String? _pendingOpen;

  ArcTvService(this._prefs) {
    _method.setMethodCallHandler(_onNativeCall);
    _mediaSub = _events.receiveBroadcastStream().listen(
      (event) => _onMedia(event as Map<dynamic, dynamic>),
      onError: (_) {},
    );
    _init();
  }

  NowPlaying get nowPlaying => _nowPlaying;
  Lyrics? get lyrics => _lyrics;
  bool get lyricsLoading => _lyricsLoading;
  bool get airPlayInstalled => _airPlayInstalled;
  bool get bundledAirPlay => _bundledAirPlay;
  bool get mediaListenerAccess => _mediaListenerAccess;
  Stream<String> get openRequests => _openRequests.stream;
  int get lyricsOffsetMs => _prefs.getInt(_kLyricsOffset) ?? 0;
  bool get autoOpenNowPlaying => _prefs.getBool(_kAutoOpen) ?? true;

  Future<void> _init() async {
    await refreshStatus();
    try {
      final pending = await _method.invokeMethod<Map<dynamic, dynamic>>('consumePendingIntent');
      if (pending != null) _handleIntent(pending);
    } catch (_) {}
  }

  Future<void> refreshStatus() async {
    try {
      _airPlayInstalled = await _method.invokeMethod<bool>('isAirPlayInstalled') ?? false;
      _bundledAirPlay = await _method.invokeMethod<bool>('hasBundledAirPlay') ?? false;
      _mediaListenerAccess = await _method.invokeMethod<bool>('hasMediaListenerAccess') ?? false;
      final np = await _method.invokeMethod<Map<dynamic, dynamic>>('getNowPlaying');
      if (np != null) _onMedia(np, notify: false);
    } catch (_) {}
    notifyListeners();
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onArcIntent') {
      _handleIntent(call.arguments as Map<dynamic, dynamic>);
    }
    return null;
  }

  void _handleIntent(Map<dynamic, dynamic> m) {
    final haUrl = m['haUrl'] as String?;
    final haToken = m['haToken'] as String?;
    if (haUrl != null || haToken != null) onHomeAssistantConfig?.call(haUrl, haToken);
    final open = m['open'] as String?;
    if (open == 'now_playing' && autoOpenNowPlaying) {
      if (_openRequests.hasListener) {
        _openRequests.add('now_playing');
      } else {
        _pendingOpen = 'now_playing';
      }
    }
  }

  /// An open request that arrived before the home screen subscribed (cold start).
  String? takePendingOpen() {
    final p = _pendingOpen;
    _pendingOpen = null;
    return p;
  }

  void requestOpen(String what) => _openRequests.add(what);

  void _onMedia(Map<dynamic, dynamic> m, {bool notify = true}) {
    _nowPlaying = NowPlaying.fromMap(m, _nowPlaying);
    if (_nowPlaying.active && _nowPlaying.title.isNotEmpty && _nowPlaying.trackKey != _lyricsKey) {
      _loadLyrics(_nowPlaying);
    } else if (!_nowPlaying.active) {
      _lyricsKey = '';
      _lyrics = null;
    }
    if (notify) notifyListeners();
  }

  Future<void> _loadLyrics(NowPlaying np) async {
    _lyricsKey = np.trackKey;
    _lyrics = null;
    _lyricsLoading = true;
    notifyListeners();
    final result = await _lyricsClient.fetch(
      title: np.title,
      artist: np.artist,
      album: np.album,
      durationMs: np.durationMs,
    );
    if (_lyricsKey != np.trackKey) return; // track changed meanwhile
    _lyrics = result;
    _lyricsLoading = false;
    notifyListeners();
  }

  Future<void> control(String action, {int positionMs = 0}) async {
    try {
      await _method.invokeMethod('mediaControl', {'action': action, 'positionMs': positionMs});
    } catch (_) {}
  }

  Future<String> installAirPlay() async {
    try {
      return await _method.invokeMethod<String>('installAirPlay') ?? 'error';
    } catch (_) {
      return 'error';
    }
  }

  Future<bool> openAirPlay() async {
    try {
      return await _method.invokeMethod<bool>('openAirPlay') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openMediaListenerSettings() async {
    try {
      return await _method.invokeMethod<bool>('openMediaListenerSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> deviceName() async {
    try {
      return await _method.invokeMethod<String>('getDeviceName') ?? 'Android TV';
    } catch (_) {
      return 'Android TV';
    }
  }

  Future<void> setLyricsOffsetMs(int v) async {
    await _prefs.setInt(_kLyricsOffset, v.clamp(-5000, 5000).toInt());
    notifyListeners();
  }

  Future<void> setAutoOpenNowPlaying(bool v) async {
    await _prefs.setBool(_kAutoOpen, v);
    notifyListeners();
  }

  @override
  void dispose() {
    _mediaSub?.cancel();
    _openRequests.close();
    super.dispose();
  }
}
