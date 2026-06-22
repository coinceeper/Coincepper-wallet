import 'package:flutter/material.dart';
import '../services/secure_storage.dart';

/// صفحه Debug برای تست مسائل Keychain
class DebugKeychainScreen extends StatefulWidget {
  const DebugKeychainScreen({super.key});

  @override
  State<DebugKeychainScreen> createState() => _DebugKeychainScreenState();
}

class _DebugKeychainScreenState extends State<DebugKeychainScreen> {
  final SecureStorage _secureStorage = SecureStorage.instance;
  String _debugOutput = 'Tap buttons to debug keychain...';

  void _updateOutput(String message) {
    setState(() {
      _debugOutput += '\n$message';
    });
    print(message);
  }

  Future<void> _debugPrintKeys() async {
    _updateOutput('=== Checking Keychain Keys ===');
    await _secureStorage.debugPrintAllKeychainKeys();
    _updateOutput('✅ Keys printed to console');
  }

  Future<void> _checkOrphanedData() async {
    _updateOutput('=== Checking for Orphaned Data ===');
    await _secureStorage.checkAndClearOrphanedData();
    _updateOutput('✅ Orphaned data check completed');
  }

  Future<void> _forceClearAll() async {
    _updateOutput('=== Force Clearing All Data ===');
    await _secureStorage.debugForceClearAllData();
    _updateOutput('✅ All data cleared');
  }

  void _clearOutput() {
    setState(() {
      _debugOutput = 'Output cleared...';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Keychain'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _debugPrintKeys,
                  child: const Text('Show Keys'),
                ),
                ElevatedButton(
                  onPressed: _checkOrphanedData,
                  child: const Text('Check Orphaned'),
                ),
                ElevatedButton(
                  onPressed: _forceClearAll,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Force Clear All'),
                ),
                ElevatedButton(
                  onPressed: _clearOutput,
                  child: const Text('Clear Output'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Output
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _debugOutput,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
