# Arc27 Launcher

An Android TV / Google TV home launcher in the style of tvOS 27, forked from
[Arc Launcher](https://github.com/meddouribadis/arclauncher) (GPL-3.0), with:

- **Liquid-glass top bar** – circular glass buttons that lift and light up on focus.
- **Home** button → Control-Center-style sheet with your Home Assistant devices
  (lights, switches, fans, covers, locks, climate, scenes, scripts, media players, temperature/humidity
  and door/motion sensors). **HomeKit accessories** appear here once added to Home Assistant with the
  *HomeKit Device* integration.
- **AirPlay 2 receiver** (bundled, from [jqssun/android-airplay-server](https://github.com/jqssun/android-airplay-server),
  UxPlay engine, GPL-3.0): iPhone/iPad/Mac screen mirroring (H.264/H.265) and AirPlay music.
- **Now Playing** for AirPlay music: blurred album-art background, cover, progress, controls and
  **time-synced lyrics** (from LRCLIB) that scroll and highlight line by line. Opens automatically when music starts.

## Build (no local setup needed)

1. Create a GitHub repo and push this folder to `main` (pushes to `claude/**` branches also build).
2. Actions → **Build Arc27 Launcher** runs automatically (~30–45 min the first time; the receiver compiles FFmpeg/OpenSSL).
3. Download the `Arc27-launcher-apks` artifact. Push a tag like `v1.0.0` to get a GitHub Release instead.

Optional, for upgradeable builds: add repo secrets `ARCTV_KEYSTORE_BASE64`, `ARCTV_KEYSTORE_PASSWORD`,
`ARCTV_KEY_ALIAS`. Without them each build is signed with a throw-away key (uninstall before updating).

## Install

```
adb install Arc27-launcher-arm64-v8a.apk            # or -universal / -armeabi-v7a
```
Uninstall the original Arc Launcher first – same package name (`com.omeda.arc`).
Make it the home app via Settings, Button Mapper, or by disabling the stock launcher with adb.

## First run

**AirPlay** – top bar → AirPlay icon → *Install AirPlay receiver* → confirm → *Open AirPlay receiver* once and allow
“Display over other apps”. The TV then shows up as **Arc TV** (rename in the receiver's settings). It starts on boot.

**Home Assistant** – top bar → Home → *Set up*, or push the config from a computer:
```
adb shell am start -n com.omeda.arc/.MainActivity --es arc_ha_url "http://192.168.1.10:8123" --es arc_ha_token "YOUR_LONG_LIVED_TOKEN"
```

**Other apps' music in Now Playing (optional)** – Spotify, YouTube Music etc.:
```
adb shell cmd notification allow_listener com.omeda.arc/com.omeda.arc.ArcMediaListenerService
```

## Known limits

- Android can't act as a native HomeKit controller; HomeKit devices come through Home Assistant.
- DRM video (Netflix, Apple TV+) can't be mirrored by any third-party AirPlay receiver.
- Lyrics depend on LRCLIB having the song; adjust timing in Settings → AirPlay & Lyrics if lines run early/late.

## Licence

GPL-3.0-or-later. Based on Arc Launcher → LtvLauncher → FLauncher, and android-airplay-server → UxPlay.
