import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'storage.dart';

/// Local PIN lock.
///
/// The PIN is never stored — only a salted SHA-256 digest of it. That will not
/// stop someone with the device and patience (a 4-digit space is small), but
/// it does mean reading the app's storage does not hand over the PIN itself.
/// Real secrets belong in the platform keychain; this guards a local ledger.
class PinLock {
  PinLock(this._storage);

  static const _key = 'ledger.pin.v1';
  static const minLength = 4;
  static const maxAttempts = 5;

  final Storage _storage;

  String? _hash;
  String? _salt;
  bool _loaded = false;
  int _failedAttempts = 0;

  bool get isConfigured => _hash != null;
  bool get isLoaded => _loaded;
  int get failedAttempts => _failedAttempts;
  int get attemptsRemaining => maxAttempts - _failedAttempts;

  /// After too many wrong guesses the UI stops accepting input until the user
  /// resets, which is the only lever available without a server.
  bool get isLockedOut => _failedAttempts >= maxAttempts;

  Future<void> load() async {
    final json = await _storage.readJson(_key);
    _hash = json?['hash'] as String?;
    _salt = json?['salt'] as String?;
    _loaded = true;
  }

  /// Rejects PINs that are too short or all the same digit.
  static String? validate(String pin) {
    if (pin.length < minLength) {
      return 'Use at least $minLength digits';
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'Digits only';
    }
    if (pin.split('').toSet().length == 1) {
      return 'Too easy to guess — vary the digits';
    }
    return null;
  }

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    _salt = salt;
    _hash = _digest(pin, salt);
    _failedAttempts = 0;
    await _storage.writeJson(_key, {'hash': _hash, 'salt': salt});
  }

  Future<void> clear() async {
    _hash = null;
    _salt = null;
    _failedAttempts = 0;
    await _storage.delete(_key);
  }

  /// True when [pin] matches. Wrong guesses count toward the lockout.
  bool verify(String pin) {
    final hash = _hash;
    final salt = _salt;
    if (hash == null || salt == null) return true; // no PIN set
    if (isLockedOut) return false;

    if (_digest(pin, salt) == hash) {
      _failedAttempts = 0;
      return true;
    }
    _failedAttempts++;
    return false;
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _digest(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
