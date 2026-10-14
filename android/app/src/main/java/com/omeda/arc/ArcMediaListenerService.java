package com.omeda.arc;

import android.service.notification.NotificationListenerService;

/**
 * Empty notification listener. Being an enabled listener is what lets the
 * launcher read *other* apps' media sessions (Spotify, YouTube Music, ...).
 * AirPlay works without it: the bundled receiver hands its session token over directly.
 */
public class ArcMediaListenerService extends NotificationListenerService {
}
