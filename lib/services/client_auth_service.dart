import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/secure_log.dart';

import '../di/service_locator.dart';
import 'client_panel_agent_claim.dart';
import 'client_panel_service.dart';
import 'device_fingerprint_service.dart';
import 'session_manager.dart';
import 'wallet_secure_storage.dart';
import '../models/client_panel_models.dart';
import '../utils/referral_code_normalize.dart';

const _kKeyUserLegacy = 'client_panel_user';
const _kKeyRefCode = 'client_panel_ref_code';
const _kPrefsRefCode = 'client_panel_device_ref_code';
const _kPrefsInviteCaptured = 'client_panel_device_invite_captured_v1';

String _userStorageKey(String walletAddress) =>
    'client_panel_user_${walletAddress.toLowerCase()}';

/// Signature callback type: signs a UTF-8 message with the wallet's ETH key.
typedef WalletSigner = Future<String> Function(String message);

/// Outcome of [ClientAuthService.ensureAuthenticated].
class AuthEnsureResult {
  final bool ok;
  final String? errorKey;

  const AuthEnsureResult._({
    required this.ok,
    this.errorKey,
  });

  factory AuthEnsureResult.success() =>
      const AuthEnsureResult._(ok: true);

  factory AuthEnsureResult.fail(String errorKey) =>
      AuthEnsureResult._(ok: false, errorKey: errorKey);
}

/// Handles automatic registration / login via Sign-in with Wallet.
class ClientAuthService {
  static ClientAuthService get instance => ServiceLocator.get<ClientAuthService>();
  ClientAuthService._();
  /// DI constructor. Use [instance] for singleton access.
  ClientAuthService();

  static const _storage = WalletSecureStorage.instance;

  /// Callback that signs a message with the wallet's Ethereum private key.
  /// Set by [ClientPanelProvider] when the wallet is resolved.
  WalletSigner? _signer;

  ClientUser? _currentUser;
  ClientUser? get currentUser => _currentUser;

  String? _sessionWalletAddress;

  /// Set the signing callback. Called once when the wallet is resolved.
  void setSigner(WalletSigner signer) {
    _signer = signer;
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
    } catch (e) {
      SecureLog.w('ClientAuth: failed to decode cached user, returning null', error: e);
      return null;
    }
  }

  Future<void> _persistReferralCode(String normalized) async {
    await _storage.write(key: _kKeyRefCode, value: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsRefCode, normalized);
    await prefs.setBool(_kPrefsInviteCaptured, true);
  }

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

  /// Clear stored referral/invite code from all storage backends.
  Future<void> clearReferralCode() async {
    await _storage.delete(key: _kKeyRefCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsRefCode);
    await prefs.remove(_kPrefsInviteCaptured);
  }

  Future<void> clearBackendSessionOnly() async {
    try {
      await ServiceLocator.get<ClientPanelService>().logout();
    } catch (e) {
      SecureLog.w('ClientAuth: logout failed, falling back to clearSession', error: e);
      await ServiceLocator.get<ClientPanelService>().clearSession();
    }
    _sessionWalletAddress = null;
    _currentUser = null;
    // Also terminate the SessionManager session.
    await ServiceLocator.get<SessionManager>().terminateSession();
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

  /// Signs a challenge message using the wallet's private key.
  Future<String> _signChallenge(String message) async {
    final signer = _signer;
    if (signer == null) {
      throw StateError(
        'WalletSigner not configured. Call setSigner() before authenticate.',
      );
    }
    return signer(message);
  }

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

  Future<AuthEnsureResult> ensureAuthenticated(
    String walletAddress, {
    String? walletAddressEth,
  }) async {
    try {
      walletAddress = _normWallet(walletAddress);
    } on MalformedPanelAddressException {
      return AuthEnsureResult.fail('panel.wallet_address_incomplete');
    }
    final norm = walletAddress.toLowerCase();
    final svc = ServiceLocator.get<ClientPanelService>();
    await svc.init();

    // Check for existing valid session via SessionManager (persistent).
    final sessionManager = ServiceLocator.get<SessionManager>();
    if (sessionManager.hasValidSession &&
        sessionManager.sessionWalletAddress?.toLowerCase() == norm) {
      _currentUser ??= await loadUserForAddress(norm);
      if (_currentUser != null &&
          _currentUser!.btcAddress.toLowerCase() == norm) {
        return AuthEnsureResult.success();
      }
      await clearBackendSessionOnly();
    }

    // Legacy fallback: in-memory session check.
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

    // Sign-in with Wallet flow: challenge -> sign -> login/register
    try {
      // 1) Get challenge from server
      final challenge = await svc.getChallenge(walletAddress);
      final nonce = challenge['nonce'] as String?;
      final message = challenge['message'] as String?;
      if (nonce == null || message == null) {
        return AuthEnsureResult.fail('panel.auth_failed');
      }

      // 2) Sign challenge with wallet private key
      final signature = await _signChallenge(message);

      // 3) Try login with signature (include ETH wallet address for verification)
      final fp = await ServiceLocator.get<DeviceFingerprintService>().get();
      try {
        final data = await svc.login(
          btcAddress: walletAddress,
          nonce: nonce,
          signature: signature,
          deviceFingerprint: fp,
          walletAddress: walletAddressEth,
        );
        _applyAuthSuccess(walletAddress, norm, data);
        return AuthEnsureResult.success();
      } on DioException catch (e) {
        if (_isNetworkDio(e)) {
          return AuthEnsureResult.fail('panel.network_error');
        }
        if (_isSuspended403(e)) {
          return AuthEnsureResult.fail('panel.account_suspended');
        }
        final status = e.response?.statusCode;

        // 401 = not found or wrong wallet -> try register
        if (status == 401) {
          return _tryRegisterWithSignature(
            walletAddress, nonce, signature,
            walletAddressEth: walletAddressEth,
          );
        }

        if (status == 400) {
          final key400 = _clientAuth400ErrorKey(e);
          if (key400 != null) return AuthEnsureResult.fail(key400);
        }

        return AuthEnsureResult.fail('panel.auth_failed');
      }
    } on StateError catch (e) {
      SecureLog.w('ClientAuth: signer not configured', error: e);
      return AuthEnsureResult.fail('panel.auth_failed');
    }
  }

  void _applyAuthSuccess(
    String walletAddress,
    String norm,
    Map<String, dynamic> data,
  ) {
    ServiceLocator.get<ClientPanelService>().setBearerFromAuthBody(data);
    final token = data['token'];
    if (token is String && token.isNotEmpty) {
      persistPanelJwt(token);
    }
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

  Future<AuthEnsureResult> _tryRegisterWithSignature(
    String walletAddress,
    String nonce,
    String signature, {
    String? walletAddressEth,
  }) async {
    final svc = ServiceLocator.get<ClientPanelService>();
    final inviteCode = await loadReferralCode() ?? '';

    if (inviteCode.isEmpty) {
      return AuthEnsureResult.fail('panel.no_invite_code');
    }

    try {
      SecureLog.d('ClientAuth: register with signature len=${signature.length}');
      final fp = await ServiceLocator.get<DeviceFingerprintService>().get();
      final data = await svc.register(
        btcAddress: walletAddress,
        nonce: nonce,
        signature: signature,
        inviteCode: inviteCode,
        deviceFingerprint: fp,
        walletAddress: walletAddressEth,
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
      if (status == 400) {
        final mapped = _clientAuth400ErrorKey(e);
        if (mapped != null) return AuthEnsureResult.fail(mapped);
        return AuthEnsureResult.fail('panel.registration_failed');
      }
      return AuthEnsureResult.fail('panel.auth_failed');
    } on FormatException {
      return AuthEnsureResult.fail('panel.auth_failed');
    }
  }
}

