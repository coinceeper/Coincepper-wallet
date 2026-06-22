import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/view_models/send_detail_view_model.dart';

/// Modal shown when the user tries to send to their own address.
class SendSelfTransferModal extends StatelessWidget {
  const SendSelfTransferModal({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewModel = context.watch<SendDetailViewModel>();

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
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Transaction Error',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              const Text(
                'You cannot send assets to your own address.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: viewModel.dismissSelfTransferError,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
