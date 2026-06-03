import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../navigation/passcode_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/passcode_manager.dart';
import '../services/security_settings_manager.dart';
import 'dart:async';

class PasscodeScreen extends StatefulWidget {
  final String title;
  final String? walletName;
  final String? firstPasscode; // برای تایید
  final String? savedPasscode; // برای ورود
  final VoidCallback? onSuccess; // تابعی که بعد از موفقیت اجرا می‌شود
  final bool isFromBackground; // آیا از بازگشت از پس‌زمینه است
  
  const PasscodeScreen({
    super.key,
    required this.title,
    this.walletName,
    this.firstPasscode,
    this.savedPasscode,
    this.onSuccess,
    this.isFromBackground = false,
  });

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> with WidgetsBindingObserver {
  String enteredCode = '';
  String errorMessage = '';
  bool isConfirmed = false;
  bool isBiometricAvailable = false;
  bool isLocked = false;
  int remainingAttempts = 5;
  int lockoutRemainingTime = 0;
  
  final LocalAuthentication auth = LocalAuthentication();
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  
  LockMethod _lockMethod = LockMethod.passcodeAndBiometric;
  bool _canUseBiometric = false;
  String? _normalizedTitle;

  final borderColors = const [
    Color(0xFF0ab62c), Color(0xFF15b65c), Color(0xFF1bb679),
    Color(0xFF27b6ac), Color(0xFF2db6c7), Color(0xFF39b6fb)
  ];

  Timer? _lockoutTimer;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    _normalizedTitle = _getNormalizedTitle(widget.title);
    await _securityManager.initialize();
    await _checkBiometric();
    // FIX: Await redirect check BEFORE other async ops.
    // This prevents the screen from being redirected mid-initialization,
    // which could leave stray timers running or cause stale state.
    await _redirectIfPasscodeExists();
    if (!mounted) return;
    await _checkLockStatus();
    await _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final lockMethod = await _securityManager.getLockMethod();
      final canUseBiometric = await _securityManager.canUseBiometricInCurrentLockMethod();
      
      setState(() {
        _lockMethod = lockMethod;
        _canUseBiometric = canUseBiometric && isBiometricAvailable;
      });
    } catch (e) {
      print('❌ Error loading security settings: $e');
    }
  }

  Future<void> _redirectIfPasscodeExists() async {
    if (_normalizedTitle == 'choose_passcode' || _normalizedTitle == 'confirm_passcode') {
      final isSet = await PasscodeManager.isPasscodeSet();
      if (isSet) {
        if (mounted) {
          context.replace(RoutePaths.enterPasscode);
        }
      }
    }
  }

  Future<void> _checkBiometric() async {
    final canCheck = await auth.canCheckBiometrics;
    final available = await auth.isDeviceSupported();
    setState(() {
      isBiometricAvailable = canCheck && available;
    });
  }

  Future<void> _checkLockStatus() async {
    final locked = await PasscodeManager.isLocked();
    final attempts = await PasscodeManager.getRemainingAttempts();
    final lockoutTime = await PasscodeManager.getLockoutRemainingTime();
    
    setState(() {
      isLocked = locked;
      remainingAttempts = attempts;
      lockoutRemainingTime = lockoutTime;
    });
    
    if (locked) {
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    // Cancel existing timer
    _lockoutTimer?.cancel();
    
    // Use Timer.periodic instead of recursive Future.delayed
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final remaining = await PasscodeManager.getLockoutRemainingTime();
      setState(() {
        lockoutRemainingTime = remaining;
      });
      
      if (remaining <= 0) {
        timer.cancel();
        await _checkLockStatus();
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _onNumberTap(String number) {
    if (isLocked || isConfirmed) return;
    
    if (enteredCode.length < 6) {
      setState(() {
        enteredCode += number;
        HapticFeedback.lightImpact();
        if (errorMessage.isNotEmpty) {
          errorMessage = '';
        }
      });
      
      // Check passcode immediately when 6 digits entered
      if (enteredCode.length == 6) {
        _handlePasscodeComplete();
      }
    }
  }

  void _onDelete() {
    if (isLocked || isConfirmed) return;
    if (enteredCode.isNotEmpty) {
      setState(() {
        enteredCode = enteredCode.substring(0, enteredCode.length - 1);
        HapticFeedback.lightImpact();
      });
    }
  }

  void _onBiometric() async {
    if (isConfirmed) return;
    HapticFeedback.lightImpact();
    try {
      // بررسی در دسترس بودن biometric
      if (!_canUseBiometric) {
        setState(() {
          errorMessage = _safeTranslate('biometric_not_available', 'Biometric authentication is not available');
        });
        return;
      }
      
      // بررسی دقیق‌تر وضعیت بیومتریک
      final canCheck = await auth.canCheckBiometrics;
      final available = await auth.isDeviceSupported();
      final availableBiometrics = await auth.getAvailableBiometrics();
      
      if (!canCheck || !available || availableBiometrics.isEmpty) {
        setState(() {
          errorMessage = _safeTranslate('biometric_not_available', 'Biometric authentication is not available on this device');
        });
        return;
      }
      
      final didAuth = await auth.authenticate(
        localizedReason: _safeTranslate('authenticate_to_continue', 'Authenticate to continue'),
        options: const AuthenticationOptions(
          biometricOnly: false, // اجازه PIN/Pattern نیز داده شود
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      
      if (didAuth) {
        await _handleSuccessfulAuthentication();
      } else {
        setState(() {
          errorMessage = _safeTranslate('authentication_cancelled', 'Authentication was cancelled or failed');
        });
      }
    } catch (e) {
      print('Biometric error: $e');
      setState(() {
        errorMessage = _safeTranslate('biometric_authentication_error', 'Biometric authentication error: {error}').replaceAll('{error}', e.toString());
      });
    }
  }

  Future<void> _handleSuccessfulAuthentication() async {
    switch (_normalizedTitle) {
      case 'choose_passcode':
        goPasscodeConfirm(
          context,
          firstPasscode: enteredCode,
          walletName: widget.walletName,
        );
        break;
      case 'confirm_passcode':
        // CRITICAL FIX: When biometric is used on confirm screen,
        // enteredCode is empty (user didn't type digits).
        // We MUST save widget.firstPasscode from the choose screen first.
        await _savePasscodeAndComplete();
        break;
      case 'enter_passcode':
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          await completePasscodeSetupSuccess(context);
        }
        break;
      default:
        _handleUnknownTitle();
        break;
    }
  }

  /// Save the passcode from [widget.firstPasscode] (the choose screen value),
  /// then navigate to the next screen.
  Future<void> _savePasscodeAndComplete() async {
    try {
      if (widget.firstPasscode != null && widget.firstPasscode!.isNotEmpty) {
        await PasscodeManager.setPasscode(widget.firstPasscode!);
      }
      if (mounted) {
        await completePasscodeSetupSuccess(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = _safeTranslate('error_setting_passcode', 'Error setting passcode');
          enteredCode = '';
          isConfirmed = false;
        });
      }
    }
  }

  /// Fallback when [_normalizedTitle] doesn't match any expected value.
  void _handleUnknownTitle() {
    setState(() {
      errorMessage = _safeTranslate('error_unknown', 'An unexpected error occurred. Please try again.');
      enteredCode = '';
      isConfirmed = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset state on resume to prevent "stuck" UI
      if (mounted) {
        setState(() {
          enteredCode = '';
          errorMessage = '';
          isConfirmed = false;
        });
        _checkLockStatus();
      }
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PasscodeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // اگر عنوان یا پس‌کد اولیه تغییر کرد، ورودی را ریست کن
    if (widget.title != oldWidget.title || widget.firstPasscode != oldWidget.firstPasscode) {
      setState(() {
        enteredCode = '';
        errorMessage = '';
      });
    }
  }

  Future<void> _handlePasscodeComplete() async {
    if (isConfirmed || isLocked) return;
    
    print('🔒 PasscodeScreen: Verifying 6 digits...');
    setState(() {
      isConfirmed = true;
      errorMessage = '';
    });
    
    try {
      switch (_normalizedTitle) {
        case 'choose_passcode':
          if (mounted) {
            goPasscodeConfirm(
              context,
              firstPasscode: enteredCode,
              walletName: widget.walletName,
            );
          }
          break;
          
        case 'confirm_passcode':
          if (widget.firstPasscode == enteredCode) {
            try {
              await PasscodeManager.setPasscode(enteredCode).timeout(const Duration(seconds: 5));
              if (mounted) {
                if (widget.onSuccess != null) {
                  widget.onSuccess!();
                } else {
                  await completePasscodeSetupSuccess(context);
                }
              }
            } catch (e) {
              print('❌ PasscodeScreen: Error saving passcode: $e');
              if (mounted) {
                setState(() {
                  errorMessage = _safeTranslate('error_setting_passcode', 'Error setting passcode');
                  enteredCode = '';
                  isConfirmed = false;
                });
              }
            }
          } else {
            if (mounted) {
              setState(() {
                errorMessage = _safeTranslate('passcode_mismatch', 'The passcode entered is not the same');
                enteredCode = '';
                isConfirmed = false;
              });
            }
          }
          break;
          
        case 'enter_passcode':
          try {
            print('🔒 PasscodeScreen: Verifying passcode with storage...');
            final isValid = await PasscodeManager.verifyPasscode(enteredCode)
                .timeout(const Duration(seconds: 7), onTimeout: () {
                  print('❌ PasscodeScreen: Verification TIMED OUT');
                  return false;
                });
            
            print('🔒 PasscodeScreen: Verification result: $isValid');
            
            if (isValid) {
              if (mounted) {
                if (widget.onSuccess != null) {
                  widget.onSuccess!();
                } else {
                  await completePasscodeSetupSuccess(context);
                }
              }
            } else {
              await _checkLockStatus();
              if (mounted) {
                setState(() {
                  errorMessage = _safeTranslate('incorrect_passcode', 'Incorrect passcode');
                  enteredCode = '';
                  isConfirmed = false;
                });
              }
            }
          } catch (e) {
            print('❌ PasscodeScreen: Critical verification error: $e');
            await _checkLockStatus();
            if (mounted) {
              setState(() {
                errorMessage = _safeTranslate('verification_error', 'Verification error');
                enteredCode = '';
                isConfirmed = false;
              });
            }
          }
          break;
        default:
          if (mounted) {
            setState(() {
              errorMessage = _safeTranslate('error_unknown', 'An unexpected error occurred. Please try again.');
              enteredCode = '';
              isConfirmed = false;
            });
          }
          break;
      }
    } catch (e) {
      print('❌ PasscodeScreen: Global error in handler: $e');
      if (mounted) {
        setState(() {
          errorMessage = _safeTranslate('general_error', 'An error occurred');
          enteredCode = '';
          isConfirmed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Text(
              _getTranslatedTitle(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: borderColors[index % borderColors.length],
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      if (index < enteredCode.length)
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: borderColors[index % borderColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            if (isLocked)
              Column(
                children: [
                  const Icon(Icons.lock, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    _safeTranslate('wallet_is_locked', 'Wallet is locked'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _safeTranslate('try_again_in', 'Try again in {time}').replaceAll('{time}', _formatTime(lockoutRemainingTime)),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Text(
                    _safeTranslate('passcode_adds_security', 'Passcode adds an extra layer of security\nwhen using the app'),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  // نمایش روش‌های احراز هویت در دسترس
                  if (_lockMethod != LockMethod.passcodeOnly && _canUseBiometric)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fingerprint, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            _safeTranslate('biometric_available', 'Biometric authentication available'),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 40),
            _NumberPad(
              onNumberTap: _onNumberTap,
              onDelete: _onDelete,
              onBiometric: _onBiometric,
              showBiometric: _canUseBiometric && !isLocked,
              isLocked: isLocked,
            ),
          ],
        ),
      ),
    );
  }

  String _getTranslatedTitle() {
    switch (widget.title) {
      case 'Choose Passcode':
        return _safeTranslate('choose_passcode', 'Choose Passcode');
      case 'Confirm Passcode':
        return _safeTranslate('confirm_passcode', 'Confirm Passcode');
      case 'Enter Passcode':
        return _safeTranslate('enter_passcode', 'Enter Passcode');
      default:
        return widget.title;
    }
  }

  /// Normalize title to handle different languages
  String _getNormalizedTitle(String title) {
    final choosePasscode = _safeTranslate('choose_passcode', 'Choose Passcode');
    final confirmPasscode = _safeTranslate('confirm_passcode', 'Confirm Passcode');
    final enterPasscode = _safeTranslate('enter_passcode', 'Enter Passcode');
    
    // 1. Exact match with current language translations
    if (title == choosePasscode) return 'choose_passcode';
    if (title == confirmPasscode) return 'confirm_passcode';
    if (title == enterPasscode) return 'enter_passcode';
    
    // 2. Exact match with English fallback
    if (title == 'Choose Passcode') return 'choose_passcode';
    if (title == 'Confirm Passcode') return 'confirm_passcode';
    if (title == 'Enter Passcode') return 'enter_passcode';
    
    // 3. Keyword detection for translated titles
    final lower = title.toLowerCase().trim();
    if (lower.contains('choose') || lower.contains('select') ||
        lower.contains('انتخاب') || lower.contains('seç') ||
        lower.contains('选择') || lower.contains('elegir') ||
        lower.contains('اختر') || lower.contains('בחר')) {
      return 'choose_passcode';
    }
    if (lower.contains('confirm') || lower.contains('verify') ||
        lower.contains('تایید') || lower.contains('onayla') ||
        lower.contains('确认') || lower.contains('confirmar') ||
        lower.contains('تأكيد') || lower.contains('אשר')) {
      return 'confirm_passcode';
    }
    if (lower.contains('enter') || lower.contains('input') ||
        lower.contains('وارد') || lower.contains('ورود') ||
        lower.contains('gir') || lower.contains('输入') ||
        lower.contains('ingresar') || lower.contains('أدخل') ||
        lower.contains('הכנס')) {
      return 'enter_passcode';
    }
    
    // 4. Fallback based on widget properties
    if (widget.firstPasscode != null && widget.firstPasscode!.isNotEmpty) {
      return 'confirm_passcode';
    }
    if (widget.savedPasscode != null && widget.savedPasscode!.isNotEmpty) {
      return 'enter_passcode';
    }
    return 'choose_passcode';
  }
}

class _NumberPad extends StatelessWidget {
  final void Function(String) onNumberTap;
  final VoidCallback onDelete;
  final VoidCallback onBiometric;
  final bool showBiometric;
  final bool isLocked;
  const _NumberPad({required this.onNumberTap, required this.onDelete, required this.onBiometric, this.showBiometric = true, this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('1', onNumberTap, isLocked: isLocked),
            _NumButton('2', onNumberTap, isLocked: isLocked),
            _NumButton('3', onNumberTap, isLocked: isLocked),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('4', onNumberTap, isLocked: isLocked),
            _NumButton('5', onNumberTap, isLocked: isLocked),
            _NumButton('6', onNumberTap, isLocked: isLocked),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NumButton('7', onNumberTap, isLocked: isLocked),
            _NumButton('8', onNumberTap, isLocked: isLocked),
            _NumButton('9', onNumberTap, isLocked: isLocked),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            showBiometric
                ? _CircleIconButton(
                    icon: Icons.fingerprint,
                    onTap: onBiometric,
                    isLocked: isLocked,
                  )
                : _CircleIconButton(
                    icon: null,
                    onTap: () {}, // دکمه غیر فعال
                    isLocked: isLocked,
                  ),
            _NumButton('0', onNumberTap, isLocked: isLocked),
            _CircleIconButton(
              icon: Icons.backspace,
              onTap: isLocked ? () {} : onDelete,
              isLocked: isLocked,
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData? icon;
  final VoidCallback onTap;
  final bool isLocked;
  const _CircleIconButton({required this.icon, required this.onTap, this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: isLocked ? null : onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isLocked ? Colors.grey.withOpacity(0.3) : const Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: icon != null ? Icon(icon, size: 28, color: isLocked ? Colors.grey.withOpacity(0.5) : Colors.grey) : null,
        ),
      ),
    );
  }
}

class _NumButton extends StatelessWidget {
  final String number;
  final void Function(String) onTap;
  final bool isLocked;
  const _NumButton(this.number, this.onTap, {this.isLocked = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: isLocked ? null : () => onTap(number),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isLocked ? Colors.grey.withOpacity(0.3) : const Color(0xFFF2F2F2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 28, 
              fontWeight: FontWeight.bold, 
              color: isLocked ? Colors.grey : Colors.black
            ),
          ),
        ),
      ),
    );
  }
} 