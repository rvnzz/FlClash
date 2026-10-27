import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'print.dart';

/// Device identification for subscription servers that limit devices per
/// user, in the format Remnawave expects (docs.rw → HWID device limit):
/// `x-hwid` (required), `x-device-os`, `x-ver-os`, `x-device-model`.
class Hwid {
  static Hwid? _instance;

  static const _enabledKey = 'remnawaveHwidEnabled';
  static const _fallbackKey = 'remnawaveHwidFallback';
  static const _salt = 'flclash-hwid:';

  Future<_DeviceIdentity>? _identity;

  Hwid._internal();

  factory Hwid() {
    _instance ??= Hwid._internal();
    return _instance!;
  }

  Future<bool> get enabled async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
  }

  Future<String> get id async => (await _resolve()).hwid;

  /// Empty when sending is turned off, so callers can always spread it.
  Future<Map<String, String>> get headers async {
    try {
      if (!await enabled) {
        return const {};
      }
      final identity = await _resolve();
      return {
        'x-hwid': identity.hwid,
        'x-device-os': identity.os,
        if (identity.osVersion.isNotEmpty) 'x-ver-os': identity.osVersion,
        if (identity.model.isNotEmpty) 'x-device-model': identity.model,
      };
    } catch (e) {
      commonPrint.log('hwid headers error: $e');
      return const {};
    }
  }

  Future<_DeviceIdentity> _resolve() async {
    final cached = _identity;
    if (cached != null) {
      return cached;
    }
    final future = _load();
    _identity = future;
    try {
      return await future;
    } catch (_) {
      _identity = null;
      rethrow;
    }
  }

  Future<_DeviceIdentity> _load() async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    String? raw;
    String os = Platform.operatingSystem;
    String osVersion = '';
    String model = '';
    switch (deviceInfo) {
      case final AndroidDeviceInfo info:
        raw = await app?.getAndroidId();
        os = 'Android';
        osVersion = info.version.release;
        model = _join(info.manufacturer, info.model);
      case final WindowsDeviceInfo info:
        raw = info.deviceId;
        os = 'Windows';
        osVersion =
            '${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
        model = info.computerName;
      case final MacOsDeviceInfo info:
        raw = info.systemGUID;
        os = 'macOS';
        osVersion =
            '${info.majorVersion}.${info.minorVersion}.${info.patchVersion}';
        model = info.model;
      case final LinuxDeviceInfo info:
        raw = info.machineId;
        os = 'Linux';
        osVersion = info.versionId ?? '';
        model = info.prettyName;
      case final IosDeviceInfo info:
        raw = info.identifierForVendor;
        os = 'iOS';
        osVersion = info.systemVersion;
        model = info.modelName;
      default:
        break;
    }
    raw = raw?.trim();
    if (raw == null || raw.isEmpty || _isPlaceholder(raw)) {
      raw = await _fallback();
    }
    final digest = sha256.convert(utf8.encode('$_salt$raw')).toString();
    return _DeviceIdentity(
      hwid: digest.substring(0, 32),
      os: os,
      osVersion: _sanitize(osVersion),
      model: _sanitize(model),
    );
  }

  /// Random per-install id, kept so the device stays the same device.
  Future<String> _fallback() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_fallbackKey);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    final random = Random.secure();
    final value = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await preferences.setString(_fallbackKey, value);
    return value;
  }

  static bool _isPlaceholder(String value) {
    final normalized = value.replaceAll(RegExp(r'[-\s]'), '').toLowerCase();
    return normalized.isEmpty ||
        RegExp(r'^0+$').hasMatch(normalized) ||
        normalized == '9774d56d682e549c' ||
        normalized == 'unknown';
  }

  static String _join(String a, String b) {
    if (b.toLowerCase().startsWith(a.toLowerCase())) {
      return b;
    }
    return '$a $b'.trim();
  }

  /// Header values must stay single-line printable ASCII.
  static String _sanitize(String value) {
    return value.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  }
}

class _DeviceIdentity {
  final String hwid;
  final String os;
  final String osVersion;
  final String model;

  const _DeviceIdentity({
    required this.hwid,
    required this.os,
    required this.osVersion,
    required this.model,
  });
}

final hwid = Hwid();
