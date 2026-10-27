# HWID for Remnawave (fork)

This fork sends device identification headers when it downloads a subscription,
in the format Remnawave's **HWID Device Limit** expects:

| Header           | Value                                                             |
|------------------|-------------------------------------------------------------------|
| `x-hwid`         | 32 hex chars: `sha256("flclash-hwid:" + platform id)[0:32]`       |
| `x-device-os`    | `Android` / `Windows` / `macOS` / `Linux`                         |
| `x-ver-os`       | OS version (e.g. `14`, `10.0.26100`, `15.1.0`, `24.04`)           |
| `x-device-model` | Device model / computer name                                      |
| `User-Agent`     | unchanged (FlClash UA or the global UA from settings)             |

Platform id source:

- Android — `Settings.Secure.ANDROID_ID`
- Windows — `deviceId` (MachineGuid) from `device_info_plus`
- macOS — `IOPlatformUUID` (`systemGUID`)
- Linux — `/etc/machine-id`
- fallback — a random id generated once and stored in app preferences

The id is hashed, so the raw hardware id never leaves the device, and it is
stable across reinstalls on the same device (except the fallback).

Headers are sent only for subscription downloads (profile import / update and
"import from URL" in a custom profile), not for rule sets, scripts or icons.

**Settings → General → Request:** "Send HWID" toggle (on by default) and the
current HWID (tap to copy) — handy for finding the device in the Remnawave panel.

Code: `lib/common/hwid.dart`, `Request.getSubscriptionResponseForUrl` in
`lib/common/request.dart`, `getAndroidId` in `AppPlugin.kt`.

Note: `proxy-providers` inside a config are fetched by the Clash core itself and
do not get these headers.
