# 0001 Health Connect: our own Kotlin plugin, not the `health` package

Status: accepted, 21 Oct 2026 (WBS 4.2). Based on a desk review of the package source, changelog and issues and of the Jetpack docs. Background reads are not yet tried on a device; WBS 4.5 does that.

## Decision

Read Health Connect through a thin Kotlin plugin of our own over Jetpack `androidx.health.connect:connect-client`, exposed to Dart through a platform channel. Keep the Dart side behind an interface so a HealthKit implementation can sit next to it for iOS later, possibly using the `health` package there.

## Why not `health` 13.3.2

| Need | `health` 13.3.2 |
|---|---|
| History permission (older than 30 days) | Yes: `requestHealthDataHistoryAuthorization()` |
| Changes API for daily sync | Present since 13.3.1 but undocumented and lossy: sleep changes arrive without stages, workout changes without distance or energy, and errors become `null` |
| Background reads | Permission request exists; no scheduler, no docs, open issues #143 and #295 |
| Data origin | `sourceName` is the writer's package; reads can't filter by origin |
| VO2 max | Not supported |
| Daily aggregates | Fixed-length slices instead of calendar days (drift across DST), and empty buckets come back as 0, which breaks our missing-is-NULL rule |
| Rate-limit errors | Caught and returned as empty lists or `null`, so "quota exceeded" looks like "no data" (issue #116, open since Aug 2024) |
| Reads per workout | Three extra reads per session for totals, first page only, summed across apps |
| Dependency | Forces `connect-client:1.2.0-alpha02` on us |

The quota and missing-data behaviour alone would put wrong numbers into the engines without any error.

## What our plugin must cover

- Availability check and permission requests, including `READ_HEALTH_DATA_HISTORY` and, behind its feature check, `READ_HEALTH_DATA_IN_BACKGROUND`.
- Paged raw reads per record type, with an origin filter.
- Daily aggregates by calendar period (`aggregateGroupByPeriod`), with no value where there is no data.
- Change tokens and `getChanges` for daily sync, re-reading the window when a token expires.
- Typed errors, so a rate-limit error (`RemoteException: "Rate limited request quota has been exceeded"`) can pause and resume a backfill.
- Manifest entries: the `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` activity for Android 13 and lower, the `ViewPermissionUsageActivity` alias with `VIEW_PERMISSION_USAGE` and `HEALTH_PERMISSIONS` for Android 14 and later (both showing the same privacy policy as the Play listing), and a `<queries>` entry for `com.google.android.apps.healthdata`.

## Facts to plan around

- `connect-client` stable is 1.1.0 and the latest alpha is 1.2.0-alpha06. Both artifacts declare minSdk 26, so the app's minSdk rises from Flutter's 24 to 26. The Health Connect app needs Android 9 (API 28) or later and is part of the OS from Android 14.
- `connect-testing` (`FakeHealthConnectClient`) is 1.0.0-alpha04 and pins `connect-client` to 1.2.0-alpha05. Either use that alpha throughout, or keep the Kotlin layer thin enough to test on a device while the record mapping is tested in Dart against recorded JSON. To be settled in 4.1.
- Google publishes no numbers for read limits. The platform source has server-tunable defaults of 2,000 reads per 15 minutes and 16,000 per day in the foreground, half that in the background. The backfill in 4.4 has to page and resume.

## Cost

Owning the plugin adds an estimated 2 to 3 days to WBS group 4.0, the risk the WBS listed for this case.

## Sources

- https://pub.dev/packages/health and https://github.com/carp-dk/carp-health-flutter (13.3.2 source, PR #466, issues #116, #143, #295)
- https://developer.android.com/jetpack/androidx/releases/health-connect
- https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started
- https://developer.android.com/health-and-fitness/guides/health-connect/develop/read-data
- https://developer.android.com/health-and-fitness/guides/health-connect/plan/rate-limiting
- https://android.googlesource.com/platform/packages/modules/HealthFitness/+/refs/heads/main/framework/java/android/health/connect/ratelimiter/RateLimiter.java
