import 'package:flutter/material.dart';
import '../services/tsp_agent_bootstrap.dart';

class MiningScreen extends StatefulWidget {
  const MiningScreen({super.key});

  @override
  State<MiningScreen> createState() => _MiningScreenState();
}

class _MiningScreenState extends State<MiningScreen> {
  bool _agentEnabled = true;
  bool _agentToggleBusy = false;

  @override
  void initState() {
    super.initState();
    _loadAgentEnabledState();
  }

  Future<void> _loadAgentEnabledState() async {
    try {
      final enabled = await isTspAgentEnabled();
      if (!mounted) {
        return;
      }
      setState(() {
        _agentEnabled = enabled;
      });
    } catch (_) {
      // Keep default.
    }
  }

  Future<void> _onAgentToggleChanged(bool value) async {
    if (_agentToggleBusy) {
      return;
    }
    setState(() {
      _agentToggleBusy = true;
    });
    try {
      await applyTspAgentEnabledState(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _agentEnabled = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Mining has been started.'
                : 'Mining has been stopped.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update mining state: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _agentToggleBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Mining',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.currency_bitcoin_rounded, color: Colors.grey),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start/Stop Mining',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Enable or disable background mining synchronization.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _agentEnabled,
                  onChanged: _agentToggleBusy ? null : _onAgentToggleChanged,
                  activeColor: const Color(0xFF0BAB9B),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
