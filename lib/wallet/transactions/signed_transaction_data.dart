/// Immutable signed transaction data for idempotent broadcast retry.
///
/// Stores the raw signed bytes (hex, JSON, or base58 depending on chain)
/// so that retries can re-broadcast the exact same signed transaction
/// without re-signing. This is the core of the "sign once, broadcast many"
/// pattern used by all major crypto wallets.
class SignedTransactionData {
  /// The raw signed transaction data.
  /// - EVM native: RLP-encoded signed tx hex (without 0x prefix)
  /// - EVM token: signed bytes hex from web3dart
  /// - BTC: hex-encoded signed raw transaction
  /// - TRON / TRC20: JSON string of signed transaction
  /// - Solana: base58-encoded signed transaction
  /// - XRP: hex-encoded tx blob
  /// - Polkadot: hex-encoded extrinsic
  final String rawData;

  /// Chain label for routing the broadcast to the correct provider.
  /// One of: 'EVM', 'BTC', 'TRON', 'TRC20', 'SOL', 'XRP', 'DOT'
  final String chainLabel;

  /// Original blockchain name (e.g. "ethereum", "bsc", "polygon").
  /// Used for RPC endpoint resolution during broadcast.
  final String blockchainName;

  const SignedTransactionData({
    required this.rawData,
    required this.chainLabel,
    required this.blockchainName,
  });

  @override
  String toString() =>
      'SignedTransactionData(chain: $chainLabel, blockchain: $blockchainName, rawData: ${rawData.length} chars)';
}
