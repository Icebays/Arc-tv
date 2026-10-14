// ArcTV 27 — Smart Home sheet (Home Assistant / HomeKit-via-HA). GPL-3.0-or-later.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home_assistant_service.dart';
import 'liquid_glass.dart';

Future<void> showSmartHomePanel(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Home',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const SmartHomePanel(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class SmartHomePanel extends StatefulWidget {
  const SmartHomePanel({super.key});

  @override
  State<SmartHomePanel> createState() => _SmartHomePanelState();
}

class _SmartHomePanelState extends State<SmartHomePanel> {
  late final HomeAssistantService _ha;

  @override
  void initState() {
    super.initState();
    _ha = context.read<HomeAssistantService>();
    _ha.startPolling();
  }

  @override
  void dispose() {
    _ha.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
        child: Material(
          type: MaterialType.transparency,
          child: LiquidGlass(
            width: (size.width * 0.5).clamp(420.0, 760.0).toDouble(),
            height: size.height - 48,
            blur: 40,
            tint: const Color(0xFF18181D),
            borderRadius: BorderRadius.circular(34),
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
            child: Consumer<HomeAssistantService>(builder: (context, ha, _) => _body(context, ha)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, HomeAssistantService ha) {
    final header = Row(
      children: [
        const Icon(Icons.home_rounded, size: 30),
        const SizedBox(width: 12),
        const Expanded(child: Text('Home', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700))),
        GlassButton.icon(icon: Icons.refresh, size: 40, onPressed: ha.refresh),
        const SizedBox(width: 10),
        GlassButton.icon(icon: Icons.tune, size: 40, onPressed: () => showSmartHomeSettings(context)),
      ],
    );

    Widget content;
    if (!ha.configured) {
      content = _message(
        'Connect Home Assistant',
        'Add your Home Assistant URL and a long-lived access token. HomeKit accessories appear here once they are '
            'added to Home Assistant (HomeKit Device integration) — so do Matter, Zigbee and everything else HA controls.',
        action: GlassButton(
          autofocus: true,
          onPressed: () => showSmartHomeSettings(context),
          child: const Text('Set up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      );
    } else if (ha.loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (ha.entities.isEmpty) {
      content = _message(ha.error ?? 'No devices', 'Nothing matched. Check the URL, token or entity filter.',
          action: GlassButton(
            autofocus: true,
            onPressed: () => showSmartHomeSettings(context),
            child: const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ));
    } else {
      final sections = ha.sections;
      var first = true;
      content = FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            if (ha.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(ha.error!, style: const TextStyle(color: Colors.orangeAccent)),
              ),
            for (final s in sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 0, 10),
                child: Text(s.title,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
              ),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final e in s.entities)
                    _DeviceTile(
                      entity: e,
                      autofocus: () {
                        final a = first;
                        first = false;
                        return a;
                      }(),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, const SizedBox(height: 12), Expanded(child: content)],
    );
  }

  Widget _message(String title, String body, {Widget? action}) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(body, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      );
}

class _DeviceTile extends StatelessWidget {
  final HaEntity entity;
  final bool autofocus;

  const _DeviceTile({required this.entity, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final on = entity.isOn && entity.actionable;
    final accent = entity.domain == 'light' ? const Color(0xFFFFC94A) : Theme.of(context).colorScheme.primary;
    return GlassButton(
      autofocus: autofocus,
      width: 168,
      height: 112,
      padding: const EdgeInsets.all(14),
      focusScale: 1.07,
      tint: on ? Colors.white.withValues(alpha: 0.9) : null,
      onPressed: entity.actionable ? () => context.read<HomeAssistantService>().activate(entity) : () {},
      child: Builder(builder: (context) {
        // Lit tiles render dark-on-white like tvOS/Home app "on" accessories.
        final fg = on ? const Color(0xFF111114) : DefaultTextStyle.of(context).style.color;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? accent : Colors.white.withValues(alpha: 0.12),
              ),
              child: Icon(entity.icon, size: 20, color: on ? Colors.white : fg),
            ),
            const Spacer(),
            Text(entity.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.15, color: fg)),
            Text(entity.displayState,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: fg?.withValues(alpha: 0.65))),
          ],
        );
      }),
    );
  }
}

// ------------------------------------------------------------------ settings

Future<void> showSmartHomeSettings(BuildContext context) =>
    showDialog(context: context, builder: (_) => const SmartHomeSettingsDialog());

class SmartHomeSettingsDialog extends StatefulWidget {
  const SmartHomeSettingsDialog({super.key});

  @override
  State<SmartHomeSettingsDialog> createState() => _SmartHomeSettingsDialogState();
}

class _SmartHomeSettingsDialogState extends State<SmartHomeSettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _filter;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final ha = context.read<HomeAssistantService>();
    _url = TextEditingController(text: ha.url);
    _token = TextEditingController(text: ha.token);
    _filter = TextEditingController(text: ha.filter);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _save({bool close = true}) async {
    setState(() => _busy = true);
    final ha = context.read<HomeAssistantService>();
    await ha.configure(url: _url.text, token: _token.text, filter: _filter.text);
    final err = await ha.testConnection();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = err ?? 'Connected ✓';
    });
    if (err == null && close) Navigator.of(context).pop();
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white, width: 2)),
      );

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: 'Smart Home',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Home Assistant → Profile → Security → Long-lived access tokens. '
            'HomeKit accessories show up after adding them to HA with the “HomeKit Device” integration.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 18),
          TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: _dec('Home Assistant URL', 'http://homeassistant.local:8123')),
          const SizedBox(height: 12),
          TextField(controller: _token, obscureText: true, decoration: _dec('Long-lived access token', 'eyJ0eXAiOi…')),
          const SizedBox(height: 12),
          TextField(
              controller: _filter,
              decoration: _dec('Only show (optional)', 'living_room, light.desk, scene.')),
          const SizedBox(height: 10),
          Text(
            'Tip: typing a token on a remote is painful. From a computer:\n'
            'adb shell am start -n com.omeda.arc/.MainActivity --es arc_ha_url "http://IP:8123" --es arc_ha_token "TOKEN"',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: TextStyle(color: _status!.endsWith('✓') ? Colors.greenAccent : Colors.orangeAccent)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              GlassButton(
                onPressed: _busy ? null : () => _save(),
                child: const Text('Save', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 14),
              GlassButton(
                onPressed: _busy ? null : () => _save(close: false),
                child: const Text('Test connection', style: TextStyle(fontSize: 17)),
              ),
              const SizedBox(width: 14),
              GlassButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(fontSize: 17)),
              ),
              if (_busy) ...[const SizedBox(width: 16), const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))],
            ],
          ),
        ],
      ),
    );
  }
}
