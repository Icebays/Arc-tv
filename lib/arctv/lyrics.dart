// ArcTV 27 — synced lyrics (LRCLIB). GPL-3.0-or-later.
import 'dart:convert';

import 'package:http/http.dart' as http;

class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

class Lyrics {
  final List<LyricLine> lines;
  final String? plain;
  final bool instrumental;

  const Lyrics({this.lines = const [], this.plain, this.instrumental = false});

  bool get synced => lines.isNotEmpty;
  bool get isEmpty => lines.isEmpty && (plain == null || plain!.trim().isEmpty) && !instrumental;

  /// Index of the line being sung at [position], or -1 before the first line.
  int indexAt(Duration position) {
    if (lines.isEmpty || position < lines.first.time) return -1;
    int lo = 0, hi = lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lines[mid].time <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static final RegExp _tag = RegExp(r'\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]');

  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    for (final raw in const LineSplitter().convert(lrc)) {
      final matches = _tag.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final secStr = m.group(2)!.replaceAll(':', '.');
        final ms = (double.parse(secStr) * 1000).round();
        out.add(LyricLine(Duration(milliseconds: min * 60000 + ms), text));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}

class LyricsClient {
  static const _host = 'lrclib.net';
  static const _headers = {'User-Agent': 'ArcTV27 Launcher (https://github.com/meddouribadis/arclauncher fork)'};

  final Map<String, Lyrics> _cache = {};

  Future<Lyrics> fetch({required String title, required String artist, String album = '', int durationMs = 0}) async {
    final key = '${title.toLowerCase()}|${artist.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    Lyrics result = const Lyrics();
    try {
      final params = <String, String>{'track_name': title, 'artist_name': artist};
      if (album.isNotEmpty) params['album_name'] = album;
      if (durationMs > 0) params['duration'] = (durationMs / 1000).round().toString();
      final r = await http.get(Uri.https(_host, '/api/get', params), headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        result = _fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      }
      if (!result.synced) {
        final s = await http
            .get(Uri.https(_host, '/api/search', {'track_name': title, 'artist_name': artist}), headers: _headers)
            .timeout(const Duration(seconds: 8));
        if (s.statusCode == 200) {
          final list = (jsonDecode(utf8.decode(s.bodyBytes)) as List).cast<Map<String, dynamic>>();
          Map<String, dynamic>? best;
          for (final item in list) {
            if ((item['syncedLyrics'] as String?)?.isNotEmpty == true) {
              final d = (item['duration'] as num?)?.toDouble() ?? 0;
              if (durationMs <= 0 || d == 0 || (d * 1000 - durationMs).abs() < 4000) {
                best = item;
                break;
              }
              best ??= item;
            }
          }
          if (best != null) {
            result = _fromJson(best);
          } else if (result.isEmpty && list.isNotEmpty) {
            result = _fromJson(list.first);
          }
        }
      }
    } catch (_) {
      // offline / timeout: show "no lyrics"
    }
    _cache[key] = result;
    return result;
  }

  static Lyrics _fromJson(Map<String, dynamic> j) {
    final synced = j['syncedLyrics'] as String?;
    final plain = j['plainLyrics'] as String?;
    return Lyrics(
      lines: synced == null ? const [] : Lyrics.parseLrc(synced),
      plain: plain,
      instrumental: j['instrumental'] == true,
    );
  }
}
