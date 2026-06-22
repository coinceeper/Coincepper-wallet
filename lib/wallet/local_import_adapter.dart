import '../services/api_models.dart';
import 'wallet_models.dart';

class LocalImportAdapter {
  static ImportWalletResponse toImportResponse(LocalWalletImported imported) {
    return ImportWalletResponse(
      status: 'success',
      message: 'Wallet imported locally',
      data: ImportWalletData(
        addresses: imported.toBlockchainAddresses(),
        mnemonic: imported.mnemonic,
        userID: imported.walletId,
        walletID: imported.walletId,
      ),
    );
  }
}
