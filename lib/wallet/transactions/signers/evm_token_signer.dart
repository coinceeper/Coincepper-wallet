export 'evm_token_signer_native.dart'
    if (dart.library.js) 'evm_token_signer_web.dart'
    if (dart.library.html) 'evm_token_signer_web.dart'
    if (dart.library.js_util) 'evm_token_signer_web.dart';
