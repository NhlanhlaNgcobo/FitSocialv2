package com.fitsocial.fitsocial_app

import android.service.notification.NotificationListenerService

/**
 * Exists only to be a permission anchor. It reads no notifications.
 *
 * Android gates [android.media.session.MediaSessionManager.getActiveSessions]
 * behind notification-listener access, and that access is granted to a
 * *component*, not to a package — so there has to be a declared
 * NotificationListenerService to point at, even though the media-session APIs
 * are the only thing we want out of it.
 *
 * Deliberately empty: `onNotificationPosted` and `onNotificationRemoved` are
 * left unimplemented so nothing in this app is ever handed the contents of a
 * notification. The service is named in the manifest with the
 * BIND_NOTIFICATION_LISTENER_SERVICE permission, and its component name is
 * what [MediaSessionBridge] passes to the session manager.
 */
class MediaSessionListener : NotificationListenerService()
