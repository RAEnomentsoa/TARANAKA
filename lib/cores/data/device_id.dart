import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _deviceIdKey = 'device_id';

/// Renvoie l'identifiant de cet appareil, en le générant au premier appel.
Future<String> loadOrCreateDeviceId([
  FlutterSecureStorage storage = const FlutterSecureStorage(),
]) async {
  final existing = await storage.read(key: _deviceIdKey);
  if (existing != null) return existing;

  final random = Random.secure();
  final deviceId = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await storage.write(key: _deviceIdKey, value: deviceId);
  return deviceId;
}
