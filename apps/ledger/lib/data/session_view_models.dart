import 'package:flx/flx.dart';

import 'ledger_repository.dart';
import 'security.dart';

/// Drives the lock screen: PIN entry, setup, and lockout.
class LockViewModel extends ViewModel {
  LockViewModel(this._lock);

  final PinLock _lock;

  bool _unlocked = false;
  String _entry = '';
  String? _message;

  bool get isUnlocked => _unlocked;
  bool get isConfigured => _lock.isConfigured;
  bool get isLockedOut => _lock.isLockedOut;
  int get attemptsRemaining => _lock.attemptsRemaining;
  String get entry => _entry;
  String? get message => _message;

  /// The dots shown above the keypad.
  int get entryLength => _entry.length;

  /// A ledger with no PIN set is open — the lock is opt-in.
  bool get requiresUnlock => _lock.isConfigured && !_unlocked;

  void press(String digit) {
    if (_lock.isLockedOut || _entry.length >= 12) return;
    _entry += digit;
    _message = null;
    notify();
  }

  void backspace() {
    if (_entry.isEmpty) return;
    _entry = _entry.substring(0, _entry.length - 1);
    _message = null;
    notify();
  }

  void clearEntry() {
    _entry = '';
    _message = null;
    notify();
  }

  /// Checks the entered PIN. Returns true when the ledger is now open.
  bool submit() {
    if (_lock.isLockedOut) {
      _message = 'Too many attempts. Reset the app to continue.';
      notify();
      return false;
    }
    if (_entry.isEmpty) {
      _message = 'Enter your PIN';
      notify();
      return false;
    }

    if (_lock.verify(_entry)) {
      _unlocked = true;
      _entry = '';
      _message = null;
      notify();
      return true;
    }

    _entry = '';
    _message = _lock.isLockedOut
        ? 'Too many attempts. Reset the app to continue.'
        : 'Wrong PIN — ${_lock.attemptsRemaining} attempts left';
    notify();
    return false;
  }

  void lock() {
    _unlocked = false;
    _entry = '';
    notify();
  }

  /// Called once at startup when no PIN is configured.
  void openWithoutPin() {
    _unlocked = true;
    notify();
  }
}

/// Settings: PIN management, theme, and destructive actions.
class SettingsViewModel extends ViewModel {
  SettingsViewModel(this._lock, this._repo, this._lockVm);

  final PinLock _lock;
  final LedgerRepository _repo;
  final LockViewModel _lockVm;

  bool _darkMode = false;
  String? _pinError;
  String? _status;

  bool get darkMode => _darkMode;
  bool get hasPin => _lock.isConfigured;
  String? get pinError => _pinError;
  String? get status => _status;

  void setDarkMode(bool value) {
    _darkMode = value;
    notify();
  }

  /// Validates and stores a new PIN. Returns true on success.
  Future<bool> setPin(String pin, String confirmation) async {
    final problem = PinLock.validate(pin);
    if (problem != null) {
      _pinError = problem;
      _status = null;
      notify();
      return false;
    }
    if (pin != confirmation) {
      _pinError = 'The two PINs do not match';
      _status = null;
      notify();
      return false;
    }

    await _lock.setPin(pin);
    _pinError = null;
    _status = 'PIN updated';
    notify();
    return true;
  }

  Future<void> removePin() async {
    await _lock.clear();
    _pinError = null;
    _status = 'PIN removed';
    notify();
  }

  void lockNow() => _lockVm.lock();

  /// Wipes every transaction and reinstates the starter data.
  Future<void> resetLedger() async {
    await _repo.reset();
    _status = 'Ledger reset';
    notify();
  }

  void clearStatus() {
    if (_status == null && _pinError == null) return;
    _status = null;
    _pinError = null;
    notify();
  }
}
