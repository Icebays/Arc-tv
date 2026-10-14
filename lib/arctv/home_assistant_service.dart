// ArcTV 27 — Home Assistant (incl. HomeKit devices bridged via HA) client. GPL-3.0-or-later.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HaEntity {
  final String id;
  final String state;
  final Map<String, dynamic> attributes;

  const HaEntity(this.id, this.state, this.attributes);

  String get domain => id.split('.').first;
  String get name => (attributes['friendly_name'] as String?) ?? id;
  String? get deviceClass => attributes['device_class'] as String?;
  bool get unavailable => state == 'unavailable' || state == 'unknown';

  bool get isOn => const {
        'on', 'open', 'opening', 'unlocked', 'playing', 'heat', 'cool', 'heat_cool', 'auto', 'dry', 'fan_only', 'home'
      }.contains(state);

  bool get actionable => !const {'sensor', 'binary_sensor'}.contains(domain) && !unavailable;

  String get displayState {
    if (unavailable) return 'Unavailable';
    switch (domain) {
      case 'light':
        final b = attributes['brightness'];
        if (state == 'on' && b is num) return '${(b / 255 * 100).round()}%';
        return state == 'on' ? 'On' : 'Off';
      case 'climate':
        final cur = attributes['current_temperature'];
        final target = attributes['temperature'];
        final unit = attributes['temperature_unit'] ?? '°';
        final mode = state == 'off' ? 'Off' : _cap(state.replaceAll('_', ' '));
        if (cur != null) return '$mode · $cur$unit${target != null ? ' → $target' : ''}';
        return mode;
      case 'sensor':
        final unit = attributes['unit_of_measurement'] ?? '';
        return '$state$unit';
      case 'scene':
      case 'script':
        return 'Run';
      case 'lock':
        return _cap(state);
      case 'cover':
        final p = attributes['current_position'];
        return p is num && state == 'open' ? 'Open $p%' : _cap(state);
      default:
        return _cap(state.replaceAll('_', ' '));
    }
  }

  IconData get icon {
    switch (domain) {
      case 'light':
        return isOn ? Icons.lightbulb : Icons.lightbulb_outline;
      case 'switch':
      case 'input_boolean':
        return isOn ? Icons.toggle_on : Icons.toggle_off_outlined;
      case 'fan':
        return Icons.air;
      case 'cover':
        return isOn ? Icons.blinds : Icons.blinds_closed;
      case 'lock':
        return state == 'locked' ? Icons.lock : Icons.lock_open;
      case 'climate':
        return Icons.thermostat;
      case 'media_player':
        return Icons.speaker;
      case 'scene':
        return Icons.auto_awesome;
      case 'script':
        return Icons.play_circle_outline;
      case 'sensor':
        return deviceClass == 'humidity' ? Icons.water_drop_outlined : Icons.device_thermostat;
      case 'binary_sensor':
        if (deviceClass == 'motion' || deviceClass == 'occupancy') return Icons.directions_walk;
        return isOn ? Icons.sensor_door : Icons.sensor_door_outlined;
      default:
        return Icons.devices_other;
    }
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class HaSection {
  final String title;
  final List<HaEntity> entities;
  const HaSection(this.title, this.entities);
}

class HomeAssistantService extends ChangeNotifier {
  static const _kUrl = 'arctv_ha_url';
  static const _kToken = 'arctv_ha_token';
  static const _kFilter = 'arctv_ha_filter';

  static const Map<String, String> _sectionTitles = {
    'scene': 'Scenes',
    'script': 'Scripts',
    'light': 'Lights',
    'switch': 'Switches',
    'input_boolean': 'Switches',
    'fan': 'Fans',
    'cover': 'Blinds & Doors',
    'lock': 'Locks',
    'climate': 'Climate',
    'media_player': 'Speakers & TVs',
    'sensor': 'Sensors',
    'binary_sensor': 'Sensors',
  };
  static const _sensorClasses = {'temperature', 'humidity'};
  static const _binaryClasses = {'door', 'window', 'garage_door', 'opening', 'motion', 'occupancy'};

  final SharedPreferences _prefs;
  List<HaEntity> _entities = const [];
  bool _loading = false;
  String? _error;
  Timer? _poll;
  int _pollers = 0;

  HomeAssistantService(this._prefs);

  String get url => _prefs.getString(_kUrl) ?? '';
  String get token => _prefs.getString(_kToken) ?? '';
  String get filter => _prefs.getString(_kFilter) ?? '';
  bool get configured => url.isNotEmpty && token.isNotEmpty;
  bool get loading => _loading;
  String? get error => _error;
  List<HaEntity> get entities => _entities;

  List<HaSection> get sections {
    final map = <String, List<HaEntity>>{};
    for (final e in _entities) {
      final title = _sectionTitles[e.domain];
      if (title == null) continue;
      map.putIfAbsent(title, () => []).add(e);
    }
    final order = _sectionTitles.values.toSet().toList();
    return [
      for (final t in order)
        if (map[t] != null) HaSection(t, map[t]!..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())))
    ];
  }

  Future<void> configure({String? url, String? token, String? filter}) async {
    if (url != null) await _prefs.setString(_kUrl, _normalizeUrl(url));
    if (token != null) await _prefs.setString(_kToken, token.trim());
    if (filter != null) await _prefs.setString(_kFilter, filter.trim());
    _entities = const [];
    _error = null;
    notifyListeners();
    if (configured) await refresh();
  }

  static String _normalizeUrl(String u) {
    var s = u.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Returns null on success or an error message.
  Future<String?> testConnection() async {
    if (!configured) return 'Enter the Home Assistant URL and a long-lived access token.';
    try {
      final r = await http.get(Uri.parse('$url/api/'), headers: _headers).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) return null;
      if (r.statusCode == 401) return 'Token rejected (401). Create a new long-lived access token.';
      return 'Home Assistant answered HTTP ${r.statusCode}.';
    } catch (e) {
      return 'Cannot reach $url ($e)';
    }
  }

  Future<void> refresh() async {
    if (!configured) return;
    _loading = _entities.isEmpty;
    if (_loading) notifyListeners();
    try {
      final r = await http.get(Uri.parse('$url/api/states'), headers: _headers).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) {
        _error = r.statusCode == 401 ? 'Access token rejected.' : 'Home Assistant error ${r.statusCode}.';
      } else {
        final list = (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
        final tokens = filter.split(',').map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toList();
        _entities = [
          for (final j in list)
            if (_include(j, tokens))
              HaEntity(j['entity_id'] as String, j['state'] as String? ?? 'unknown',
                  (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {})
        ];
        _error = null;
      }
    } catch (e) {
      _error = 'Cannot reach Home Assistant.';
    }
    _loading = false;
    notifyListeners();
  }

  bool _include(Map<String, dynamic> j, List<String> tokens) {
    final id = (j['entity_id'] as String? ?? '').toLowerCase();
    final domain = id.split('.').first;
    if (!_sectionTitles.containsKey(domain)) return false;
    final attrs = (j['attributes'] as Map?) ?? const {};
    if (domain == 'sensor' && !_sensorClasses.contains(attrs['device_class'])) return false;
    if (domain == 'binary_sensor' && !_binaryClasses.contains(attrs['device_class'])) return false;
    if (tokens.isEmpty) return true;
    final name = (attrs['friendly_name'] as String? ?? '').toLowerCase();
    return tokens.any((t) => id.startsWith(t) || id.contains(t) || name.contains(t));
  }

  Future<void> activate(HaEntity e) async {
    String domain;
    String service;
    switch (e.domain) {
      case 'light':
      case 'switch':
      case 'input_boolean':
      case 'fan':
        domain = 'homeassistant';
        service = 'toggle';
        break;
      case 'media_player':
        domain = 'media_player';
        service = 'toggle';
        break;
      case 'cover':
        domain = 'cover';
        service = 'toggle';
        break;
      case 'lock':
        domain = 'lock';
        service = e.state == 'locked' ? 'unlock' : 'lock';
        break;
      case 'climate':
        domain = 'climate';
        service = e.state == 'off' ? 'turn_on' : 'turn_off';
        break;
      case 'scene':
      case 'script':
        domain = e.domain;
        service = 'turn_on';
        break;
      default:
        return;
    }
    await callService(domain, service, {'entity_id': e.id});
  }

  Future<void> callService(String domain, String service, Map<String, dynamic> data) async {
    try {
      await http
          .post(Uri.parse('$url/api/services/$domain/$service'), headers: _headers, body: jsonEncode(data))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      _error = 'Command failed.';
      notifyListeners();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    await refresh();
  }

  /// Polls every 5 s while at least one panel is visible.
  void startPolling() {
    _pollers++;
    refresh();
    _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => refresh());
  }

  void stopPolling() {
    _pollers = (_pollers - 1).clamp(0, 1 << 30).toInt();
    if (_pollers == 0) {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
