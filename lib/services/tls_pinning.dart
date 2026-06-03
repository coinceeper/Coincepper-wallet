import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'build_secrets.dart';

/// Certificate pinning via leaf DER SHA-256 (strict when pins configured).
class TlsPinning {
  TlsPinning._();

  static void configure(Dio dio) {
    if (kIsWeb) return;
    final pinsByHost = BuildSecrets.tlsPinsByHost;
    if (pinsByHost.isEmpty) return;

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient(
          context: SecurityContext(withTrustedRoots: false),
        );
        client.badCertificateCallback = (cert, host, port) {
          return _verifyCert(cert, host, pinsByHost);
        };
        return client;
      },
    );
  }

  static bool _verifyCert(
    X509Certificate cert,
    String host,
    Map<String, Set<String>> pinsByHost,
  ) {
    final hostKey = host.toLowerCase();
    final allowed = pinsByHost[hostKey];
    if (allowed == null || allowed.isEmpty) {
      if (kDebugMode) {
        return true;
      }
      return false;
    }
    final fingerprint = sha256.convert(cert.der).toString().toLowerCase();
    return allowed.contains(fingerprint);
  }
}
