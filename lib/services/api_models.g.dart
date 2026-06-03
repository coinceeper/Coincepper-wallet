// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BlockchainAddress _$BlockchainAddressFromJson(Map<String, dynamic> json) =>
    BlockchainAddress(
      blockchainName: json['BlockchainName'] as String,
      publicAddress: json['PublicAddress'] as String,
    );

Map<String, dynamic> _$BlockchainAddressToJson(BlockchainAddress instance) =>
    <String, dynamic>{
      'BlockchainName': instance.blockchainName,
      'PublicAddress': instance.publicAddress,
    };

ImportWalletResponse _$ImportWalletResponseFromJson(
        Map<String, dynamic> json) =>
    ImportWalletResponse(
      data: json['data'] == null
          ? null
          : ImportWalletData.fromJson(json['data'] as Map<String, dynamic>),
      message: json['message'] as String,
      status: json['status'] as String,
    );

Map<String, dynamic> _$ImportWalletResponseToJson(
        ImportWalletResponse instance) =>
    <String, dynamic>{
      'data': instance.data,
      'message': instance.message,
      'status': instance.status,
    };

PricesRequest _$PricesRequestFromJson(Map<String, dynamic> json) =>
    PricesRequest(
      symbol:
          (json['Symbol'] as List<dynamic>).map((e) => e as String).toList(),
      fiatCurrencies: (json['FiatCurrencies'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$PricesRequestToJson(PricesRequest instance) =>
    <String, dynamic>{
      'Symbol': instance.symbol,
      'FiatCurrencies': instance.fiatCurrencies,
    };

EstimateFeeRequest _$EstimateFeeRequestFromJson(Map<String, dynamic> json) =>
    EstimateFeeRequest(
      userID: json['UserID'] as String,
      blockchain: json['blockchain'] as String,
      fromAddress: json['from_address'] as String,
      toAddress: json['to_address'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] as String?,
      tokenContract: json['token_contract'] as String? ?? '',
    );

Map<String, dynamic> _$EstimateFeeRequestToJson(EstimateFeeRequest instance) =>
    <String, dynamic>{
      'UserID': instance.userID,
      'blockchain': instance.blockchain,
      'from_address': instance.fromAddress,
      'to_address': instance.toAddress,
      'amount': instance.amount,
      'type': instance.type,
      'token_contract': instance.tokenContract,
    };

RegisterDeviceRequest _$RegisterDeviceRequestFromJson(
        Map<String, dynamic> json) =>
    RegisterDeviceRequest(
      userId: json['UserID'] as String,
      walletId: json['WalletID'] as String,
      deviceToken: json['DeviceToken'] as String,
      deviceName: json['DeviceName'] as String,
      deviceType: json['DeviceType'] as String? ?? 'android',
    );

Map<String, dynamic> _$RegisterDeviceRequestToJson(
        RegisterDeviceRequest instance) =>
    <String, dynamic>{
      'UserID': instance.userId,
      'WalletID': instance.walletId,
      'DeviceToken': instance.deviceToken,
      'DeviceName': instance.deviceName,
      'DeviceType': instance.deviceType,
    };

GetUserBalanceRequest _$GetUserBalanceRequestFromJson(
        Map<String, dynamic> json) =>
    GetUserBalanceRequest(
      userID: json['UserID'] as String,
      currencyName: (json['CurrencyName'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$GetUserBalanceRequestToJson(
        GetUserBalanceRequest instance) =>
    <String, dynamic>{
      'UserID': instance.userID,
      'CurrencyName': instance.currencyName,
    };

WalletData _$WalletDataFromJson(Map<String, dynamic> json) => WalletData(
      userID: json['UserID'] as String?,
      walletID: json['WalletID'] as String?,
      mnemonic: json['mnemonic'] as String?,
      addresses: (json['Addresses'] as List<dynamic>?)
          ?.map((e) => Address.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$WalletDataToJson(WalletData instance) =>
    <String, dynamic>{
      'UserID': instance.userID,
      'WalletID': instance.walletID,
      'mnemonic': instance.mnemonic,
      'Addresses': instance.addresses,
    };

Address _$AddressFromJson(Map<String, dynamic> json) => Address(
      blockchainName: json['BlockchainName'] as String?,
      publicAddress: json['PublicAddress'] as String?,
    );

Map<String, dynamic> _$AddressToJson(Address instance) => <String, dynamic>{
      'BlockchainName': instance.blockchainName,
      'PublicAddress': instance.publicAddress,
    };

PriceData _$PriceDataFromJson(Map<String, dynamic> json) => PriceData(
      change24h: json['change_24h'] as String,
      price: json['price'] as String,
    );

Map<String, dynamic> _$PriceDataToJson(PriceData instance) => <String, dynamic>{
      'change_24h': instance.change24h,
      'price': instance.price,
    };

PricesResponse _$PricesResponseFromJson(Map<String, dynamic> json) =>
    PricesResponse(
      success: const BoolIntConverter().fromJson(json['success']),
      prices: (json['prices'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
            k,
            (e as Map<String, dynamic>).map(
              (k, e) =>
                  MapEntry(k, PriceData.fromJson(e as Map<String, dynamic>)),
            )),
      ),
    );

Map<String, dynamic> _$PricesResponseToJson(PricesResponse instance) =>
    <String, dynamic>{
      'success': const BoolIntConverter().toJson(instance.success),
      'prices': instance.prices,
    };

ApiCurrency _$ApiCurrencyFromJson(Map<String, dynamic> json) => ApiCurrency(
      currencyId: json['CurrencyID'] as String?,
      blockchainName: json['BlockchainName'] as String?,
      currencyName: json['CurrencyName'] as String?,
      symbol: json['Symbol'] as String?,
      icon: json['Icon'] as String?,
      smartContractAddress: json['SmartContractAddress'] as String?,
      isToken: const NullableBoolIntConverter().fromJson(json['IsToken']),
      decimalPlaces: (json['DecimalPlaces'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ApiCurrencyToJson(ApiCurrency instance) =>
    <String, dynamic>{
      'CurrencyID': instance.currencyId,
      'BlockchainName': instance.blockchainName,
      'CurrencyName': instance.currencyName,
      'Symbol': instance.symbol,
      'Icon': instance.icon,
      'SmartContractAddress': instance.smartContractAddress,
      'IsToken': const NullableBoolIntConverter().toJson(instance.isToken),
      'DecimalPlaces': instance.decimalPlaces,
    };

ApiResponse _$ApiResponseFromJson(Map<String, dynamic> json) => ApiResponse(
      currencies: (json['currencies'] as List<dynamic>)
          .map((e) => ApiCurrency.fromJson(e as Map<String, dynamic>))
          .toList(),
      success: const BoolIntConverter().fromJson(json['success']),
    );

Map<String, dynamic> _$ApiResponseToJson(ApiResponse instance) =>
    <String, dynamic>{
      'currencies': instance.currencies,
      'success': const BoolIntConverter().toJson(instance.success),
    };

BalanceItem _$BalanceItemFromJson(Map<String, dynamic> json) => BalanceItem(
      balance: json['balance'] as String?,
      blockchain: json['blockchain'] as String?,
      isToken: const NullableBoolIntConverter().fromJson(json['is_token']),
      symbol: json['symbol'] as String?,
      currencyName: json['currency_name'] as String?,
    );

Map<String, dynamic> _$BalanceItemToJson(BalanceItem instance) =>
    <String, dynamic>{
      'balance': instance.balance,
      'blockchain': instance.blockchain,
      'is_token': const NullableBoolIntConverter().toJson(instance.isToken),
      'symbol': instance.symbol,
      'currency_name': instance.currencyName,
    };

GetUserBalanceResponse _$GetUserBalanceResponseFromJson(
        Map<String, dynamic> json) =>
    GetUserBalanceResponse(
      tokens: json['Tokens'] as Map<String, dynamic>,
      userID: json['UserID'] as String,
      success: const BoolIntConverter().fromJson(json['success']),
    );

Map<String, dynamic> _$GetUserBalanceResponseToJson(
        GetUserBalanceResponse instance) =>
    <String, dynamic>{
      'Tokens': instance.tokens,
      'UserID': instance.userID,
      'success': const BoolIntConverter().toJson(instance.success),
    };

GasFeeItem _$GasFeeItemFromJson(Map<String, dynamic> json) => GasFeeItem(
      gasFee: json['gas_fee'] as String?,
    );

Map<String, dynamic> _$GasFeeItemToJson(GasFeeItem instance) =>
    <String, dynamic>{
      'gas_fee': instance.gasFee,
    };

GasFeeResponse _$GasFeeResponseFromJson(Map<String, dynamic> json) =>
    GasFeeResponse(
      arbitrum: json['arbitrum'] == null
          ? null
          : GasFeeItem.fromJson(json['arbitrum'] as Map<String, dynamic>),
      avalanche: json['avalanche'] == null
          ? null
          : GasFeeItem.fromJson(json['avalanche'] as Map<String, dynamic>),
      binance: json['binance'] == null
          ? null
          : GasFeeItem.fromJson(json['binance'] as Map<String, dynamic>),
      bitcoin: json['bitcoin'] == null
          ? null
          : GasFeeItem.fromJson(json['bitcoin'] as Map<String, dynamic>),
      cardano: json['cardano'] == null
          ? null
          : GasFeeItem.fromJson(json['cardano'] as Map<String, dynamic>),
      cosmos: json['cosmos'] == null
          ? null
          : GasFeeItem.fromJson(json['cosmos'] as Map<String, dynamic>),
      ethereum: json['ethereum'] == null
          ? null
          : GasFeeItem.fromJson(json['ethereum'] as Map<String, dynamic>),
      fantom: json['fantom'] == null
          ? null
          : GasFeeItem.fromJson(json['fantom'] as Map<String, dynamic>),
      optimism: json['optimism'] == null
          ? null
          : GasFeeItem.fromJson(json['optimism'] as Map<String, dynamic>),
      polkadot: json['polkadot'] == null
          ? null
          : GasFeeItem.fromJson(json['polkadot'] as Map<String, dynamic>),
      polygon: json['polygon'] == null
          ? null
          : GasFeeItem.fromJson(json['polygon'] as Map<String, dynamic>),
      solana: json['solana'] == null
          ? null
          : GasFeeItem.fromJson(json['solana'] as Map<String, dynamic>),
      tron: json['tron'] == null
          ? null
          : GasFeeItem.fromJson(json['tron'] as Map<String, dynamic>),
      xrp: json['xrp'] == null
          ? null
          : GasFeeItem.fromJson(json['xrp'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GasFeeResponseToJson(GasFeeResponse instance) =>
    <String, dynamic>{
      'arbitrum': instance.arbitrum,
      'avalanche': instance.avalanche,
      'binance': instance.binance,
      'bitcoin': instance.bitcoin,
      'cardano': instance.cardano,
      'cosmos': instance.cosmos,
      'ethereum': instance.ethereum,
      'fantom': instance.fantom,
      'optimism': instance.optimism,
      'polkadot': instance.polkadot,
      'polygon': instance.polygon,
      'solana': instance.solana,
      'tron': instance.tron,
      'xrp': instance.xrp,
    };

Transaction _$TransactionFromJson(Map<String, dynamic> json) => Transaction(
      txHash: json['txHash'] as String?,
      from: json['from'] as String?,
      to: json['to'] as String?,
      amount: json['amount'] as String?,
      tokenSymbol: json['tokenSymbol'] as String?,
      direction: json['direction'] as String?,
      status: json['status'] as String?,
      timestamp: json['timestamp'] as String?,
      blockchainName: json['blockchainName'] as String?,
      price: Transaction._priceFromJson(json['price']),
      temporaryId: json['temporaryId'] as String?,
      explorerUrl: json['explorerUrl'] as String?,
      fee: json['fee'] as String?,
      assetType: json['assetType'] as String?,
      tokenContract: json['tokenContract'] as String?,
    );

Map<String, dynamic> _$TransactionToJson(Transaction instance) =>
    <String, dynamic>{
      'txHash': instance.txHash,
      'from': instance.from,
      'to': instance.to,
      'amount': instance.amount,
      'tokenSymbol': instance.tokenSymbol,
      'direction': instance.direction,
      'status': instance.status,
      'timestamp': instance.timestamp,
      'blockchainName': instance.blockchainName,
      'price': instance.price,
      'temporaryId': instance.temporaryId,
      'explorerUrl': instance.explorerUrl,
      'fee': instance.fee,
      'assetType': instance.assetType,
      'tokenContract': instance.tokenContract,
    };

TransactionsResponse _$TransactionsResponseFromJson(
        Map<String, dynamic> json) =>
    TransactionsResponse(
      count: (json['count'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      perPage: (json['per_page'] as num).toInt(),
      status: json['status'] as String,
      transactions: (json['transactions'] as List<dynamic>)
          .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TransactionsResponseToJson(
        TransactionsResponse instance) =>
    <String, dynamic>{
      'count': instance.count,
      'page': instance.page,
      'per_page': instance.perPage,
      'status': instance.status,
      'transactions': instance.transactions,
    };

TransactionDetails _$TransactionDetailsFromJson(Map<String, dynamic> json) =>
    TransactionDetails(
      amount: json['amount'] as String,
      blockchain: json['blockchain'] as String,
      estimatedFee: json['estimated_fee'] as String,
      explorerUrl: json['explorer_url'] as String,
      recipient: json['recipient'] as String,
      sender: json['sender'] as String,
      senderBalanceAfter: json['sender_balance_after'] as String,
      senderBalanceBefore: json['sender_balance_before'] as String,
    );

Map<String, dynamic> _$TransactionDetailsToJson(TransactionDetails instance) =>
    <String, dynamic>{
      'amount': instance.amount,
      'blockchain': instance.blockchain,
      'estimated_fee': instance.estimatedFee,
      'explorer_url': instance.explorerUrl,
      'recipient': instance.recipient,
      'sender': instance.sender,
      'sender_balance_after': instance.senderBalanceAfter,
      'sender_balance_before': instance.senderBalanceBefore,
    };

PrepareTransactionResponse _$PrepareTransactionResponseFromJson(
        Map<String, dynamic> json) =>
    PrepareTransactionResponse(
      details:
          TransactionDetails.fromJson(json['details'] as Map<String, dynamic>),
      expiresAt: json['expires_at'] as String,
      message: json['message'] as String,
      success: const BoolIntConverter().fromJson(json['success']),
      transactionId: json['transaction_id'] as String,
    );

Map<String, dynamic> _$PrepareTransactionResponseToJson(
        PrepareTransactionResponse instance) =>
    <String, dynamic>{
      'details': instance.details,
      'expires_at': instance.expiresAt,
      'message': instance.message,
      'success': const BoolIntConverter().toJson(instance.success),
      'transaction_id': instance.transactionId,
    };

PriorityOption _$PriorityOptionFromJson(Map<String, dynamic> json) =>
    PriorityOption(
      fee: (json['fee'] as num?)?.toInt(),
      feeEth: (json['fee_eth'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$PriorityOptionToJson(PriorityOption instance) =>
    <String, dynamic>{
      'fee': instance.fee,
      'fee_eth': instance.feeEth,
    };

PriorityOptions _$PriorityOptionsFromJson(Map<String, dynamic> json) =>
    PriorityOptions(
      average: json['average'] == null
          ? null
          : PriorityOption.fromJson(json['average'] as Map<String, dynamic>),
      fast: json['fast'] == null
          ? null
          : PriorityOption.fromJson(json['fast'] as Map<String, dynamic>),
      slow: json['slow'] == null
          ? null
          : PriorityOption.fromJson(json['slow'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PriorityOptionsToJson(PriorityOptions instance) =>
    <String, dynamic>{
      'average': instance.average,
      'fast': instance.fast,
      'slow': instance.slow,
    };

EstimateFeeResponse _$EstimateFeeResponseFromJson(Map<String, dynamic> json) =>
    EstimateFeeResponse(
      fee: (json['fee'] as num?)?.toInt(),
      feeCurrency: json['fee_currency'] as String?,
      gasPrice: (json['gas_price'] as num?)?.toInt(),
      gasUsed: (json['gas_used'] as num?)?.toInt(),
      priorityOptions: json['priority_options'] == null
          ? null
          : PriorityOptions.fromJson(
              json['priority_options'] as Map<String, dynamic>),
      timestamp: (json['timestamp'] as num?)?.toInt(),
      unit: json['unit'] as String?,
      usdPrice: (json['usd_price'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$EstimateFeeResponseToJson(
        EstimateFeeResponse instance) =>
    <String, dynamic>{
      'fee': instance.fee,
      'fee_currency': instance.feeCurrency,
      'gas_price': instance.gasPrice,
      'gas_used': instance.gasUsed,
      'priority_options': instance.priorityOptions,
      'timestamp': instance.timestamp,
      'unit': instance.unit,
      'usd_price': instance.usdPrice,
    };

RegisterDeviceResponse _$RegisterDeviceResponseFromJson(
        Map<String, dynamic> json) =>
    RegisterDeviceResponse(
      success: const BoolIntConverter().fromJson(json['success']),
      message: json['message'] as String?,
      deviceId: json['deviceId'] as String?,
    );

Map<String, dynamic> _$RegisterDeviceResponseToJson(
        RegisterDeviceResponse instance) =>
    <String, dynamic>{
      'success': const BoolIntConverter().toJson(instance.success),
      'message': instance.message,
      'deviceId': instance.deviceId,
    };

ConfirmTransactionResponse _$ConfirmTransactionResponseFromJson(
        Map<String, dynamic> json) =>
    ConfirmTransactionResponse(
      success: const NullableBoolIntConverter().fromJson(json['success']),
      message: json['message'] as String?,
      transactionHash: json['transaction_hash'] as String?,
      txHash: json['tx_hash'] as String?,
      status: json['status'] as String?,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$ConfirmTransactionResponseToJson(
        ConfirmTransactionResponse instance) =>
    <String, dynamic>{
      'success': const NullableBoolIntConverter().toJson(instance.success),
      'message': instance.message,
      'transaction_hash': instance.transactionHash,
      'tx_hash': instance.txHash,
      'status': instance.status,
      'description': instance.description,
    };

NotificationPayload _$NotificationPayloadFromJson(Map<String, dynamic> json) =>
    NotificationPayload(
      title: json['title'] as String,
      body: json['body'] as String,
    );

Map<String, dynamic> _$NotificationPayloadToJson(
        NotificationPayload instance) =>
    <String, dynamic>{
      'title': instance.title,
      'body': instance.body,
    };

NotificationData _$NotificationDataFromJson(Map<String, dynamic> json) =>
    NotificationData(
      transactionId: json['transaction_id'] as String?,
      type: json['type'] as String?,
      direction: json['direction'] as String?,
      amount: json['amount'] as String?,
      currency: json['currency'] as String?,
      symbol: json['symbol'] as String?,
      fromAddress: json['from_address'] as String?,
      toAddress: json['to_address'] as String?,
      walletId: json['wallet_id'] as String?,
      timestamp: json['timestamp'] as String?,
      status: json['status'] as String?,
    );

Map<String, dynamic> _$NotificationDataToJson(NotificationData instance) =>
    <String, dynamic>{
      'transaction_id': instance.transactionId,
      'type': instance.type,
      'direction': instance.direction,
      'amount': instance.amount,
      'currency': instance.currency,
      'symbol': instance.symbol,
      'from_address': instance.fromAddress,
      'to_address': instance.toAddress,
      'wallet_id': instance.walletId,
      'timestamp': instance.timestamp,
      'status': instance.status,
    };

AndroidNotificationConfig _$AndroidNotificationConfigFromJson(
        Map<String, dynamic> json) =>
    AndroidNotificationConfig(
      channelId: json['channel_id'] as String?,
      sound: json['sound'] as String?,
      icon: json['icon'] as String?,
      priority: (json['priority'] as num?)?.toInt(),
    );

Map<String, dynamic> _$AndroidNotificationConfigToJson(
        AndroidNotificationConfig instance) =>
    <String, dynamic>{
      'channel_id': instance.channelId,
      'sound': instance.sound,
      'icon': instance.icon,
      'priority': instance.priority,
    };

FCMNotificationMessage _$FCMNotificationMessageFromJson(
        Map<String, dynamic> json) =>
    FCMNotificationMessage(
      notification: NotificationPayload.fromJson(
          json['notification'] as Map<String, dynamic>),
      data: NotificationData.fromJson(json['data'] as Map<String, dynamic>),
      androidConfig: (json['android'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
            k, AndroidNotificationConfig.fromJson(e as Map<String, dynamic>)),
      ),
    );

Map<String, dynamic> _$FCMNotificationMessageToJson(
        FCMNotificationMessage instance) =>
    <String, dynamic>{
      'notification': instance.notification,
      'data': instance.data,
      'android': instance.androidConfig,
    };
