/*
 * ArcTV 27 additions — GPL-3.0-or-later (same licence as Arc Launcher / FLauncher).
 */
package com.omeda.arc;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;

import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

public class ArcTvBridge {
    private static final String TAG = "ArcTvBridge";
    static final String METHOD_CHANNEL = "com.omeda.arc/arctv";
    static final String MEDIA_EVENTS = "com.omeda.arc/arctv_media";
    static final String AIRPLAY_PKG = "io.github.jqssun.airplay";
    static final String AIRPLAY_ASSET = "airplay-receiver.apk";
    static final String ACTION_AIRPLAY_SESSION = "com.omeda.arc.AIRPLAY_SESSION";

    private final Activity activity;
    private final MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private EventChannel.EventSink sink;

    private MediaController airplayController;
    private MediaController current;
    private Object lastArtKey;
    private byte[] lastArt;
    private Map<String, Object> pendingIntent;
    private boolean dartReady = false;
    private BroadcastReceiver sessionReceiver;
    private MediaSessionManager.OnActiveSessionsChangedListener sessionsListener;

    private final MediaController.Callback callback = new MediaController.Callback() {
        @Override public void onMetadataChanged(MediaMetadata metadata) { emit(); }
        @Override public void onPlaybackStateChanged(PlaybackState state) { emit(); }
        @Override public void onSessionDestroyed() {
            if (current != null && airplayController != null
                    && current.getSessionToken().equals(airplayController.getSessionToken())) {
                airplayController = null;
            }
            select(null);
            reselect();
        }
    };

    public ArcTvBridge(Activity activity, BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, METHOD_CHANNEL);
        channel.setMethodCallHandler((call, result) -> {
            try {
                switch (call.method) {
                    case "getNowPlaying" -> result.success(snapshot());
                    case "mediaControl" -> {
                        String action = call.argument("action");
                        Number pos = call.argument("positionMs");
                        result.success(control(action, pos == null ? 0 : pos.longValue()));
                    }
                    case "hasMediaListenerAccess" -> result.success(hasListenerAccess());
                    case "openMediaListenerSettings" -> result.success(openListenerSettings());
                    case "isAirPlayInstalled" -> result.success(isInstalled(AIRPLAY_PKG));
                    case "hasBundledAirPlay" -> result.success(hasBundledAirPlay());
                    case "installAirPlay" -> result.success(installAirPlay());
                    case "openAirPlay" -> result.success(launchPackage(AIRPLAY_PKG));
                    case "consumePendingIntent" -> {
                        Map<String, Object> p = pendingIntent;
                        pendingIntent = null;
                        dartReady = true;
                        result.success(p);
                    }
                    case "getDeviceName" -> result.success(deviceName());
                    default -> result.notImplemented();
                }
            } catch (Exception e) {
                Log.w(TAG, "method " + call.method + " failed", e);
                result.error("ARCTV_ERROR", e.getMessage(), null);
            }
        });

        new EventChannel(messenger, MEDIA_EVENTS).setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object args, EventChannel.EventSink events) {
                sink = events;
                emit();
            }
            @Override public void onCancel(Object args) { sink = null; }
        });

        registerAirPlayTokenReceiver();
        registerSessionsListener();
        reselect();
    }

    // ---------------------------------------------------------------- intents

    /** Handles launcher intents: "open now playing" from the AirPlay receiver, HA config via adb. */
    public void handleIntent(Intent intent) {
        if (intent == null) return;
        Map<String, Object> map = new HashMap<>();
        String open = intent.getStringExtra("arc_open");
        if (open != null) map.put("open", open);
        String haUrl = intent.getStringExtra("arc_ha_url");
        if (haUrl != null) map.put("haUrl", haUrl);
        String haToken = intent.getStringExtra("arc_ha_token");
        if (haToken != null) map.put("haToken", haToken);
        if (map.isEmpty()) return;
        intent.removeExtra("arc_open");
        intent.removeExtra("arc_ha_url");
        intent.removeExtra("arc_ha_token");
        if (dartReady) {
            main.post(() -> channel.invokeMethod("onArcIntent", map));
        } else {
            pendingIntent = map;
        }
    }

    public void dispose() {
        try { if (sessionReceiver != null) activity.unregisterReceiver(sessionReceiver); } catch (Exception ignored) {}
        try {
            if (sessionsListener != null) {
                MediaSessionManager msm = (MediaSessionManager) activity.getSystemService(Context.MEDIA_SESSION_SERVICE);
                msm.removeOnActiveSessionsChangedListener(sessionsListener);
            }
        } catch (Exception ignored) {}
        select(null);
    }

    // ---------------------------------------------------------------- sessions

    private void registerAirPlayTokenReceiver() {
        sessionReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context ctx, Intent intent) {
                MediaSession.Token token;
                if (Build.VERSION.SDK_INT >= 33) {
                    token = intent.getParcelableExtra("token", MediaSession.Token.class);
                } else {
                    token = intent.getParcelableExtra("token");
                }
                if (token == null) return;
                if (airplayController != null && airplayController.getSessionToken().equals(token)) return;
                airplayController = new MediaController(activity, token);
                reselect();
            }
        };
        ContextCompat.registerReceiver(activity, sessionReceiver,
                new IntentFilter(ACTION_AIRPLAY_SESSION), ContextCompat.RECEIVER_EXPORTED);
    }

    private void registerSessionsListener() {
        if (!hasListenerAccess()) return;
        try {
            MediaSessionManager msm = (MediaSessionManager) activity.getSystemService(Context.MEDIA_SESSION_SERVICE);
            sessionsListener = controllers -> reselect();
            msm.addOnActiveSessionsChangedListener(sessionsListener, listenerComponent(), main);
        } catch (SecurityException e) {
            Log.i(TAG, "media listener access not granted");
        }
    }

    private ComponentName listenerComponent() {
        return new ComponentName(activity, ArcMediaListenerService.class);
    }

    /** AirPlay session wins; otherwise whatever is playing; otherwise first active session. */
    private void reselect() {
        MediaController pick = null;
        if (airplayController != null && isLive(airplayController)) pick = airplayController;
        if (pick == null && hasListenerAccess()) {
            try {
                MediaSessionManager msm = (MediaSessionManager) activity.getSystemService(Context.MEDIA_SESSION_SERVICE);
                List<MediaController> list = msm.getActiveSessions(listenerComponent());
                for (MediaController c : list) {
                    PlaybackState s = c.getPlaybackState();
                    if (s != null && s.getState() == PlaybackState.STATE_PLAYING) { pick = c; break; }
                }
                if (pick == null) {
                    for (MediaController c : list) {
                        if (c.getMetadata() != null) { pick = c; break; }
                    }
                }
            } catch (SecurityException ignored) {}
        }
        if (pick == null && airplayController != null) pick = airplayController;
        select(pick);
    }

    private boolean isLive(MediaController c) {
        PlaybackState s = c.getPlaybackState();
        return c.getMetadata() != null && s != null
                && s.getState() != PlaybackState.STATE_NONE && s.getState() != PlaybackState.STATE_STOPPED;
    }

    private void select(MediaController c) {
        if (current != null && c != null && current.getSessionToken().equals(c.getSessionToken())) {
            emit();
            return;
        }
        if (current != null) {
            try { current.unregisterCallback(callback); } catch (Exception ignored) {}
        }
        current = c;
        if (current != null) current.registerCallback(callback, main);
        emit();
    }

    private void emit() {
        if (sink == null) return;
        Map<String, Object> s = snapshot();
        main.post(() -> { if (sink != null) sink.success(s); });
    }

    private Map<String, Object> snapshot() {
        Map<String, Object> m = new HashMap<>();
        MediaController c = current;
        MediaMetadata md = c == null ? null : c.getMetadata();
        m.put("active", c != null && md != null);
        m.put("nowElapsed", SystemClock.elapsedRealtime());
        if (c == null || md == null) return m;
        m.put("package", c.getPackageName());
        m.put("isAirPlay", AIRPLAY_PKG.equals(c.getPackageName()));
        m.put("title", str(md, MediaMetadata.METADATA_KEY_TITLE, MediaMetadata.METADATA_KEY_DISPLAY_TITLE));
        m.put("artist", str(md, MediaMetadata.METADATA_KEY_ARTIST, MediaMetadata.METADATA_KEY_ALBUM_ARTIST));
        m.put("album", str(md, MediaMetadata.METADATA_KEY_ALBUM, null));
        m.put("durationMs", md.getLong(MediaMetadata.METADATA_KEY_DURATION));
        PlaybackState ps = c.getPlaybackState();
        if (ps != null) {
            m.put("state", ps.getState());
            m.put("positionMs", ps.getPosition());
            m.put("speed", (double) ps.getPlaybackSpeed());
            m.put("updateTime", ps.getLastPositionUpdateTime());
        }
        m.put("artwork", artwork(md));
        return m;
    }

    private static String str(MediaMetadata md, String key, String fallback) {
        CharSequence v = md.getText(key);
        if ((v == null || v.length() == 0) && fallback != null) v = md.getText(fallback);
        return v == null ? "" : v.toString();
    }

    private byte[] artwork(MediaMetadata md) {
        Bitmap bmp = md.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
        if (bmp == null) bmp = md.getBitmap(MediaMetadata.METADATA_KEY_ART);
        if (bmp == null) bmp = md.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON);
        if (bmp == null) return null;
        if (bmp == lastArtKey) return lastArt;
        try {
            Bitmap scaled = bmp;
            int max = Math.max(bmp.getWidth(), bmp.getHeight());
            if (max > 720) {
                float f = 720f / max;
                scaled = Bitmap.createScaledBitmap(bmp, Math.round(bmp.getWidth() * f), Math.round(bmp.getHeight() * f), true);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            scaled.compress(Bitmap.CompressFormat.JPEG, 90, out);
            lastArtKey = bmp;
            lastArt = out.toByteArray();
            return lastArt;
        } catch (Exception e) {
            return null;
        }
    }

    private boolean control(String action, long pos) {
        MediaController c = current;
        if (c == null || action == null) return false;
        MediaController.TransportControls t = c.getTransportControls();
        switch (action) {
            case "play" -> t.play();
            case "pause" -> t.pause();
            case "toggle" -> {
                PlaybackState s = c.getPlaybackState();
                if (s != null && s.getState() == PlaybackState.STATE_PLAYING) t.pause(); else t.play();
            }
            case "next" -> t.skipToNext();
            case "previous" -> t.skipToPrevious();
            case "seek" -> t.seekTo(pos);
            default -> { return false; }
        }
        return true;
    }

    // ---------------------------------------------------------------- permissions & apps

    private boolean hasListenerAccess() {
        return NotificationManagerCompat.getEnabledListenerPackages(activity).contains(activity.getPackageName());
    }

    private boolean openListenerSettings() {
        try {
            Intent i = new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (i.resolveActivity(activity.getPackageManager()) == null) return false;
            activity.startActivity(i);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean isInstalled(String pkg) {
        try {
            activity.getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    private boolean hasBundledAirPlay() {
        try (InputStream ignored = activity.getAssets().open(AIRPLAY_ASSET)) {
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** @return "started", "permission", "missing" or "error". */
    private String installAirPlay() {
        if (!hasBundledAirPlay()) return "missing";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !activity.getPackageManager().canRequestPackageInstalls()) {
            try {
                activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + activity.getPackageName())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (Exception ignored) {}
            return "permission";
        }
        try {
            File out = new File(activity.getCacheDir(), AIRPLAY_ASSET);
            try (InputStream in = activity.getAssets().open(AIRPLAY_ASSET);
                 OutputStream os = new FileOutputStream(out)) {
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
            }
            Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", out);
            Intent i = new Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(i);
            return "started";
        } catch (Exception e) {
            Log.w(TAG, "install failed", e);
            return "error";
        }
    }

    private boolean launchPackage(String pkg) {
        PackageManager pm = activity.getPackageManager();
        Intent i = pm.getLeanbackLaunchIntentForPackage(pkg);
        if (i == null) i = pm.getLaunchIntentForPackage(pkg);
        if (i == null) return false;
        activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        return true;
    }

    private String deviceName() {
        String n = null;
        try { n = Settings.Global.getString(activity.getContentResolver(), Settings.Global.DEVICE_NAME); } catch (Exception ignored) {}
        return n == null ? Build.MODEL : n;
    }
}
