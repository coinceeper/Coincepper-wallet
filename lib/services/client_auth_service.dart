import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_secrets.dart';
import 'client_panel_service.dart';
import 'device_fingerprint_service.dart';
import 'wallet_secure_storage.dart';
import '../models/client_panel_models.dart';
import '../utils/referral_code_normalize.dart';

const _kKeyUserLegacy = 'client_panel_user';
const _kKeyRefCode = 'client_panel_ref_code';
/// Device-wide (per install) mirror — survives multi-wallet panel sign-up.
const _kPrefsRefCode = 'client_panel_device_ref_code';
const _kPrefsInviteCaptured = 'client_panel_device_invite_captured_v1';

String _userStorageKey(String walletAddress) =>
    'client_panel_user_${walletAddress.toLowerCase()}';

String _manualPinStorageKey(String walletAddress) =>
    'client_panel_manual_pin_${walletAddress.toLowerCase()}';

/// Outcome of [ClientAuthService.ensureAuthenticated].
class AuthEnsureResult {
  final bool ok;
  /// easy_localization key (e.g. `panel.invite_invalid`).
  final String? errorKey;
  final bool needsWebPin;

  const AuthEnsureResult._({
    required this.ok,
    this.errorKey,
    this.needsWebPin = false,
  });

  factory AuthEnsureResult.success() =>
      const AuthEnsureResult._(ok: true);

  factory AuthEnsureResult.fail(String errorKey, {bool needsWebPin = false}) =>
      AuthEnsureResult._(
        ok: false,
        errorKey: errorKey,
        needsWebPin: needsWebPin,
      );
}

/// Handles automatic registration / login without any explicit UI.
class ClientAuthService {
  static ClientAuthService? _instance;
  static ClientAuthService get instance => _instance ??= ClientAuthService._();
  ClientAuthService._();

  static const _storage = WalletSecureStorage.instance;

  ClientUser? _currentUser;
  ClientUser? get currentUser => _currentUser;

  /// Backend cookie/session last logged-in wallet (`0x...` lower-case normalized internally).
  String? _sessionWalletAddress;

  /// Derives an 8-digit PIN from the wallet address using HMAC-SHA256 (deterministic per wallet).
  String derivePin(String walletAddress) {
    final key = utf8.encode(BuildSecrets.clientHmacSecret);
    final msg = utf8.encode(walletAddress.toLowerCase());
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(msg).toString();
    final digits = digest.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) return digits.substring(0, 8);
    final fallback =
        digest.codeUnits.map((c) => c % 10).join().padLeft(8, '0');
    return fallback.substring(0, 8);
  }

  Future<void> saveUserForAddress(String walletAddress, ClientUser user) =>
      _storage.write(
        key: _userStorageKey(walletAddress),
        value: jsonEncode({
          'id': user.id,
          'btc_address': user.btcAddress,
          'ref_code': user.refCode,
          'status': user.status,
        }),
      );

  Future<ClientUser?> loadUserForAddress(String walletAddress) async {
    final key = _userStorageKey(walletAddress);
    var raw = await _storage.read(key: key);
    raw ??= await _storage.read(key: _kKeyUserLegacy);
    if (raw == null) return null;
    try {
      final u = ClientUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (u.btcAddress.toLowerCase() != walletAddress.toLowerCase()) {
        return null;
      }
      return u;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistReferralCode(String normalized) async {
    await _storage.write(key: _kKeyRefCode, value: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsRefCode, normalized);
    await prefs.setBool(_kPrefsInviteCaptured, true);
  }

  /// True after the user entered an invite code once this install (multi-wallet reuse).
  Future<bool> isDeviceInviteCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPrefsInviteCaptured) == true) return true;
    final code = await loadReferralCode();
    return code != null && code.isNotEmpty;
  }

  Future<void> markDeviceInviteCaptured() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsInviteCaptured, true);
  }

  /// Returns `false` if input could not be parsed into a non-empty code (nothing saved).
  Future<bool> saveReferralCode(String code) async {
    final n = normalizeInviteInput(code);
    if (n.isEmpty) return false;
    await _persistReferralCode(n);
    return true;
  }

  Future<String?> loadReferralCode() async {
    var raw = await _storage.read(key: _kKeyRefCode);
    if (raw == null || raw.trim().isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_kPrefsRefCode);
      if (raw != null && raw.trim().isNotEmpty) {
        await _storage.write(key: _kKeyRefCode, value: raw.trim());
      }
    }
    if (raw == null || raw.trim().isEmpty) return null;
    final n = normalizeInviteInput(raw);
    if (n.isEmpty) return null;
    if (n != raw.trim()) {
      await _persistReferralCode(n);
    }
    return n;
  }

  /// PIN typed by users who registered on the web (bcrypt ≠ app-derived PIN).
  Future<void> saveManualPinForWallet(String walletAddress, String pin) async {
    final p = pin.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(p)) return;
    await _storage.write(key: _manualPinStorageKey(walletAddress), value: p);
  }

  Future<String?> loadManualPin(String walletAddress) =>
      _storage.read(key: _manualPinStorageKey(walletAddress));

  Future<void> clearManualPin(String walletAddress) =>
      _storage.delete(key: _manualPinStorageKey(walletAddress));

  Future<void> clearBackendSessionOnly() async {
    try {
      await ClientPanelService.instance.logout();
    } catch (_) {
      await ClientPanelService.instance.clearSession();
    }
    _sessionWalletAddress = null;
    _currentUser = null;
  }

  Future<void> clearSession() async {
    await clearBackendSessionOnly();
    await _storage.delete(key: _kKeyUserLegacy);
  }

  bool _isNetworkDio(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        (e.response == null &&
            e.type != DioExceptionType.badResponse &&
            e.type != DioExceptionType.cancel);
  }

  bool _isSuspended403(DioException e) {
    if (e.response?.statusCode != 403) return false;
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      return (data['error'] as String).toLowerCase().contains('suspended');
    }
    return e.response.toString().toLowerCase().contains('suspended');
  }

  String _normWallet(String walletAddress) {
    final n = ClientPanelService.normalizeBtcAddressForApi(walletAddress);
    if (n == null) throw const MalformedPanelAddressException();
    return n;
  }

  /// Maps known 400 responses from client auth endpoints (register / login).
  String? _clientAuth400ErrorKey(DioException e) {
    final data = e.response?.data;
    if (data is! Map) return null;
    final apiCode = data['code'];
    if (apiCode is String && apiCode == 'INVALID_PANEL_ADDRESS') {
      return 'panel.invalid_btc_address';
    }
    final err = data['error'];
    if (err is! String) return null;
    if (err == 'invalid Bitcoin address') return 'panel.invalid_btc_address';
    if (err.toLowerCase() == 'invalid request body') {
      return 'panel.invalid_request';
    }
    return null;
  }

  Future<AuthEnsureResult> ensureAuthenticated(String walletAddress) async {
    try {
      walletAddress = _normWallet(walletAddress);
    } on MalformedPanelAddressException {
      return AuthEnsureResult.fail('panel.wallet_address_incomplete');
    }
    final norm = walletAddress.toLowerCase();
    final svc = ClientPanelService.instance;
    await svc.init();

    if (_sessionWalletAddress != null && _sessionWalletAddress != norm) {
      await clearBackendSessionOnly();
    }

    if (await svc.hasValidSession() && _sessionWalletAddress == norm) {
      _currentUser ??= await loadUserForAddress(norm);
      if (_currentUser != null &&
          _currentUser!.btcAddress.toLowerCase() == norm) {
        return AuthEnsureResult.success();
      }
      await clearBackendSessionOnly();
    }

    final derived = derivePin(walletAddress);
    final manual = await loadManualPin(walletAddress);
    final pins = <String>[];
    if (manual != null &&
        manual.isNotEmpty &&
        RegExp(r'^\d{8}$').hasMatch(manual.trim())) {
      final m = manual.trim();
      if (!pins.contains(m)) pins.add(m);
    }
    if (!pins.contains(derived)) pins.add(derived);

    for (final pin in pins) {
      try {
        final fp = await DeviceFingerprintService.instance.get();
        final data = await svc.login(
          btcAddress: walletAddress,
          pin: pin,
          deviceFingerprint: fp,
        );
        _applyAuthSuccess(walletAddress, norm, data);
        return AuthEnsureResult.success();
      } on MalformedPanelAddressException {
        return AuthEnsureResult.fail('panel.wallet_address_incomplete');
      } on DioException catch (e) {
        if (_isNetworkDio(e)) {
          return AuthEnsureResult.fail('panel.network_error');
        }
        if (_isSuspended403(e)) {
          return AuthEnsureResult.fail('panel.account_suspended');
        }
        final code = e.response?.statusCode;
        if (code == 401) continue;
        if (code == 403) {
          return AuthEnsureResult.fail('panel.account_suspended');
        }
        if (code == 400) {
          final key400 = _clientAuth400ErrorKey(e);
          if (key400 != null) return AuthEnsureResult.fail(key400);
        }
        return AuthEnsureResult.fail('panel.auth_failed');
      } on FormatException {
        return AuthEnsureResult.fail('panel.auth_failed');
      }
    }

    return _tryRegisterWithResult(walletAddress, derived);
  }

  void _applyAuthSuccess(
    String walletAddress,
    String norm,
    Map<String, dynamic> data,
  ) {
    ClientPanelService.instance.setBearerFromAuthBody(data);
    final rawUser = data['user'];
    if (rawUser is! Map<String, dynamic>) {
      throw const FormatException('auth response missing user');
    }
    _currentUser = ClientUser.fromJson(rawUser);
    saveUserForAddress(walletAddress, _currentUser!);
    _sessionWalletAddress = norm;
    markDeviceInviteCaptured();
  }

  String? _serverErrorMessage(DioException e) {
    final d = e.response?.data;
    if (d is Map && d['error'] is String) return d['error'] as String;
    return null;
  }

  Future<AuthEnsureResult> _tryRegisterWithResult(
    String walletAddress,
    String pin,
  ) async {
    final svc = ClientPanelService.instance;
    final inviteCode = await loadReferralCode() ?? '';

    if (inviteCode.isEmpty) {
      return AuthEnsureResult.fail('panel.no_invite_code');
    }

    try {
      if (kDebugMode) {
        final h =
            sha256.convert(utf8.encode(walletAddress.toLowerCase())).toString();
        debugPrint(
          '[panel auth] register attempt len=${walletAddress.length} '
          'addrSha256=${h.substring(0, 16)}…',
        );
      }
      final fp = await DeviceFingerprintService.instance.get();
      final data = await svc.register(
        btcAddress: walletAddress,
        pin: pin,
        inviteCode: inviteCode,
        deviceFingerprint: fp,
      );
      _applyAuthSuccess(walletAddress, walletAddress.toLowerCase(), data);
      return AuthEnsureResult.success();
    } on MalformedPanelAddressException {
      return AuthEnsureResult.fail('panel.wallet_address_incomplete');
    } on DioException catch (e) {
      if (_isNetworkDio(e)) {
        return AuthEnsureResult.fail('panel.network_error');
      }
      final status = e.response?.statusCode;
      if (status == 403) {
        return AuthEnsureResult.fail('panel.invite_invalid');
      }
      if (status == 409) {
        final manual = await loadManualPin(walletAddress);
        final hasManual =
            manual != null && RegExp(r'^\d{8}$').hasMatch(manual.trim());
        if (hasManual) {
          return AuthEnsureResult.fail('panel.auth_failed');
        }
        return AuthEnsureResult.fail(
          'panel.account_exists_web_pin',
          needsWebPin: true,
        );
      }
      if (status == 400) {
        final mapped = _clientAuth400ErrorKey(e);
        if (mapped != null) return AuthEnsureResult.fail(mapped);
        final msg = (_serverErrorMessage(e) ?? '').toLowerCase();
        if (msg.contains('pin')) {
          return AuthEnsureResult.fail('panel.auth_failed');
        }
        return AuthEnsureResult.fail('panel.registration_failed');
      }
      if (status == 401) {
        return AuthEnsureResult.fail('panel.auth_failed');
      }
      return AuthEnsureResult.fail('panel.auth_failed');
    } on FormatException {
      return AuthEnsureResult.fail('panel.auth_failed');
    }
  }
}
