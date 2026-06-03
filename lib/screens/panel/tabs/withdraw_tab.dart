import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';

class WithdrawTab extends StatefulWidget {
  const WithdrawTab({super.key});

  @override
  State<WithdrawTab> createState() => _WithdrawTabState();
}

class _WithdrawTabState extends State<WithdrawTab> {
  final _amountCtrl = TextEditingController();
  String _sourceType = 'all';
  bool _submitting = false;

  static const _feePct = 0.05;
  static const _minBtc = 0.002;

  double get _amount =>
      double.tryParse(_amountCtrl.text.trim()) ?? 0;
  double get _fee => _amount * _feePct;
  double get _net => _amount - _fee;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(ClientPanelProvider provider) async {
    final amount = _amount;
    if (amount < _minBtc) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('panel.min_withdraw'
                .tr(args: ['$_minBtc BTC']))),
      );
      return;
    }

    final confirmed = await _showConfirmDialog(provider, amount);
    if (!confirmed) return;

    setState(() => _submitting = true);
    final ok = await provider.requestWithdrawal(
      amountBtc: amount,
      sourceType: _sourceType,
    );
    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        _amountCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('panel.withdraw_submitted'.tr()),
              backgroundColor:
                  Theme.of(context).colorScheme.primary),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  provider.withdrawalsError ?? 'panel.withdraw_failed'.tr()),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<bool> _showConfirmDialog(
      ClientPanelProvider provider, double amount) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('panel.confirm_withdraw'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConfirmRow(
                    label: 'panel.amount'.tr(),
                    value: '${amount.toStringAsFixed(8)} BTC'),
                _ConfirmRow(
                    label: 'panel.fee'.tr(),
                    value: '${_fee.toStringAsFixed(8)} BTC (5%)'),
                const Divider(),
                _ConfirmRow(
                    label: 'panel.net_amount'.tr(),
                    value: '${_net.toStringAsFixed(8)} BTC',
                    bold: true),
                const SizedBox(height: 8),
                _ConfirmRow(
                    label: 'panel.source'.tr(),
                    value: _sourceType.toUpperCase()),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('panel.cancel'.tr())),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(ctx).colorScheme.primary),
                child: Text('panel.confirm'.tr(),
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        final primary = Theme.of(context).colorScheme.primary;
        final balance = provider.dashboard?.balance;
        return RefreshIndicator(
          color: primary,
          onRefresh: () => provider.loadWithdrawals(reset: true),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _WithdrawForm(
                amountCtrl: _amountCtrl,
                sourceType: _sourceType,
                balance: balance,
                fee: _fee,
                net: _net,
                submitting: _submitting,
                onSourceChanged: (v) => setState(() => _sourceType = v!),
                onAmountChanged: (_) => setState(() {}),
                onSubmit: () => _submit(provider),
              ),
              const SizedBox(height: 24),
              Text('panel.withdraw_history'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 12),
              if (provider.withdrawalsLoading &&
                  provider.withdrawals.isEmpty)
                Center(
                    child: CircularProgressIndicator(color: primary))
              else if (provider.withdrawals.isEmpty)
                _Empty()
              else
                ...provider.withdrawals
                    .map((w) => _WithdrawalRow(wd: w))
                    ,
            ],
          ),
        );
      },
    );
  }
}

class _WithdrawForm extends StatelessWidget {
  final TextEditingController amountCtrl;
  final String sourceType;
  final ClientBalance? balance;
  final double fee;
  final double net;
  final bool submitting;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onSubmit;

  const _WithdrawForm({
    required this.amountCtrl,
    required this.sourceType,
    required this.balance,
    required this.fee,
    required this.net,
    required this.submitting,
    required this.onSourceChanged,
    required this.onAmountChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('panel.request_withdraw'.tr(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 16)),
          if (balance != null) ...[
            const SizedBox(height: 8),
            Text(
              '${'panel.available'.tr()}: ${_availableStr(balance!)} BTC',
              style:
                  const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,8}'))
            ],
            onChanged: onAmountChanged,
            decoration: InputDecoration(
              labelText: 'panel.amount_btc'.tr(),
              hintText: '0.00000000',
              suffixText: 'BTC',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: sourceType,
            decoration: InputDecoration(
              labelText: 'panel.source'.tr(),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primary),
              ),
            ),
            items: [
              DropdownMenuItem(
                  value: 'all', child: Text('panel.source_all'.tr())),
              DropdownMenuItem(
                  value: 'own',
                  child: Text('panel.source_own'.tr())),
              DropdownMenuItem(
                  value: 'referral',
                  child: Text('panel.source_referral'.tr())),
            ],
            onChanged: onSourceChanged,
          ),
          const SizedBox(height: 12),
          if (amountCtrl.text.isNotEmpty) ...[
            _FeeLine(
                label: 'panel.fee'.tr(),
                value: '${fee.toStringAsFixed(8)} BTC'),
            const SizedBox(height: 4),
            _FeeLine(
                label: 'panel.net_amount'.tr(),
                value: '${net.toStringAsFixed(8)} BTC',
                highlight: true),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('panel.request_withdraw'.tr(),
                      style: const TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  String _availableStr(ClientBalance b) {
    switch (sourceType) {
      case 'own':
        return b.ownBtc.toStringAsFixed(8);
      case 'referral':
        return b.referralBtc.toStringAsFixed(8);
      default:
        return (b.ownBtc + b.referralBtc).toStringAsFixed(8);
    }
  }
}

class _FeeLine extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _FeeLine(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 12)),
        Text(value,
            style: TextStyle(
                fontWeight:
                    highlight ? FontWeight.w700 : FontWeight.w400,
                color: highlight
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black87,
                fontSize: 12)),
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _ConfirmRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.w400)),
        ],
      ),
    );
  }
}

class _WithdrawalRow extends StatelessWidget {
  final ClientWithdrawal wd;
  const _WithdrawalRow({required this.wd});

  Color get _statusColor {
    switch (wd.status) {
      case 'confirmed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${wd.requestedBtc.toStringAsFixed(8)} BTC',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  'Net: ${wd.netBtc.toStringAsFixed(8)} BTC',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 11),
                ),
                Text(
                  _formatDate(wd.createdAt),
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  wd.status.toUpperCase(),
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (wd.txHash != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${wd.txHash!.substring(0, 8)}...',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.history_rounded,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('panel.no_withdrawals'.tr(),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
