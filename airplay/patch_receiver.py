#!/usr/bin/env python3
"""ArcTV 27 patches for jqssun/android-airplay-server (GPL-3.0).

1. Advertises as "Arc TV" by default.
2. Only takes over the screen for mirroring / AirPlay video, not for music.
3. Hands its MediaSession token to the launcher and asks it to open Now Playing
   (album art + synced lyrics) when a music stream starts.

Every replacement must match exactly once, so an upstream change fails the build loudly
instead of silently producing a half-patched receiver.
"""
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
base = root / "app/src/main/kotlin/io/github/jqssun/airplay"


def patch(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    n = text.count(old)
    if n != 1:
        sys.exit(f"patch failed: {path.name}: expected 1 match, found {n}:\n{old}")
    path.write_text(text.replace(old, new))


prefs = base / "Prefs.kt"
patch(prefs, 'DEF_SERVER_NAME = "Android AirPlay"', 'DEF_SERVER_NAME = "Arc TV"')

svc = base / "service/AirPlayService.kt"

# (2) don't jump to the receiver UI on bare connection; wait for video
patch(svc,
      """        if (requiresPin()) return
        if (!shouldLaunchOnConnect()) return
        launchMainActivity()
    }""",
      """        if (requiresPin()) return
        // ArcTV 27: the receiver UI is launched once mirroring/video actually starts;
        // music is shown by the launcher's Now Playing screen instead.
    }""")

patch(svc,
      """        if (running) videoRenderer.startSession() else {""",
      """        if (running) {
            videoRenderer.startSession()
            if (shouldLaunchOnConnect()) launchMainActivity()
        } else {""")

patch(svc,
      """        airPlayVideoPlayer.play(location, startPositionSeconds)
""",
      """        airPlayVideoPlayer.play(location, startPositionSeconds)
        if (shouldLaunchOnConnect()) launchMainActivity()
""")

# (3) hand the session to the launcher
patch(svc,
      """        if (audioOnly && !prev) {
            mediaSession?.isActive = true""",
      """        if (audioOnly && !prev) {
            mediaSession?.isActive = true
            _arcNotifyLauncher(openNowPlaying = true)""")

patch(svc,
      """        mediaSession?.setMetadata(builder.build())
""",
      """        mediaSession?.setMetadata(builder.build())
        _arcNotifyLauncher(openNowPlaying = false)
""")

patch(svc,
      """    private fun launchMainActivity() {""",
      """    // ArcTV 27 launcher integration
    private fun _arcNotifyLauncher(openNowPlaying: Boolean) {
        try {
            val token = mediaSession?.sessionToken?.token as? android.os.Parcelable ?: return
            sendBroadcast(
                Intent("com.omeda.arc.AIRPLAY_SESSION")
                    .setPackage("com.omeda.arc")
                    .putExtra("token", token)
            )
            if (openNowPlaying) {
                startActivity(
                    Intent()
                        .setClassName("com.omeda.arc", "com.omeda.arc.MainActivity")
                        .putExtra("arc_open", "now_playing")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "ArcTV launcher notify failed", e)
        }
    }

    private fun launchMainActivity() {""")

print("receiver patched")
