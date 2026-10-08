# Supabase changes

Apply migrations `202609240001`, `202609240002`, `202609250001`, then `202609250002` to the connected Supabase project before deploying the Flutter changes. They add soft archive flags, scoring access and rank lookup, notifications for GPOA submissions/updates, schedule and letter changes, report submissions/updates/archives, and published scores. The last migration avoids repeating a score notification when the committed score has not changed.

The app notification bell is a live, status-colored inbox. Supabase Realtime must be enabled for the `notifications` table; the migration adds it to `supabase_realtime`. Archiving is soft deletion: archived GPOAs and accomplishment reports remain in the database and can be restored from the Archived tab.

## Device push delivery

The repository had no Firebase project configuration. The current inbox works without Firebase, but OS-level Android/iOS push requires a Firebase project, the matching `google-services.json` and `GoogleService-Info.plist` / FlutterFire options, APNs credentials for iOS, and a trusted server sender (Firebase service account). Never put the service account key in the Flutter app. After those are available, register each signed-in device's FCM token and have a Supabase Edge Function send FCM messages when rows are inserted into `notifications`.
