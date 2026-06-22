import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/view_models/send_detail_view_model.dart';

String _symbol(SendDetailViewModel vm) => vm.token?.symbol ?? '';
///
/// Displays transaction details (from, to, amount, fee) and allows
/// the user to confirm or cancel the send.
class SendConfirmModal extends StatelessWidget {
  const SendConfirmModal({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewModel = context.watch<SendDetailViewModel>();
    final txDetails = viewModel.txDetails;
    if (txDetails == null) return const SizedBox();

    final selectedFee = viewModel.networkFeeOptions[viewModel.selectedPriority]!;
    final amountValue = double.tryParse(viewModel.amountController.text) ?? 0.0;
    final totalValue = (amountValue * viewModel.pricePerToken).toStringAsFixed(2);
    final totalWithFee = ((double.tryParse(totalValue) ?? 0.0) + selectedFee.feeUsd).toStringAsFixed(2);

    return Container(
      color: scheme.onSurface.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon and title
              const Icon(Icons.send_rounded, size: 48, color: Color(0xFF08C495)),
              const SizedBox(height: 16),
              Text(
                'Transaction Confirmation',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: scheme.onSurface),
              ),
              const SizedBox(height: 20),

              // Amount
              Text(
                '-${txDetails.details.amount} ${_symbol(viewModel)}',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                '≈ \$$totalValue',
                style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),

              // Transaction details
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _DetailRow(label: 'From', value: viewModel.walletName),
                    const SizedBox(height: 12),
                    _DetailRow(label: 'To', value: viewModel.formatAddress(txDetails.details.recipient)),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Network Fee',
                      value: '${selectedFee.feeEth.toStringAsFixed(8)} ${viewModel.getBlockchainCurrency()}',
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(label: 'Total', value: '≈ \$$totalWithFee'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Warning
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please double-check the recipient address before confirming.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: viewModel.dismissConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerLow,
                        foregroundColor: scheme.onSurface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: viewModel.isLoading ? null : () => viewModel.onConfirmSend(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: viewModel.isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: scheme.onPrimary, strokeWidth: 2),
                            )
                          : Text('Send ${viewModel.token?.symbol ?? ''}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
