import 'dart:io';

import 'package:aqueduct/src/application/channel.dart';

import 'application.dart';

/// An object that contains configuration values for an [Application].
///
/// You use this object in an [ApplicationChannel] to manage external configuration data for your application.
class ApplicationOptions {
  /// The absolute path of the configuration file for this application.
  ///
  /// This path is provided when an application is started by the `--config-path` option to `aqueduct serve`.
  /// You may load the file at this path in [ApplicationChannel] to use configuration values.
  String configurationFilePath;

  /// The address to listen for HTTP requests on.
  ///
  /// By default, this address will default to 'any' address (0.0.0.0). If [isIpv6Only] is true,
  /// 'any' will be any IPv6 address, otherwise, it will be any IPv4 or IPv6 address.
  ///
  /// This value may be an [InternetAddress] or a [String].
  dynamic address;

  /// The port to listen for HTTP requests on.
  ///
  /// Defaults to 8888.
  int port = 8888;

  /// Whether or not the application should only receive connections over IPv6.
  ///
  /// Defaults to false. This flag impacts the default value of the [address] property.
  bool isIpv6Only = false;

  /// Whether or not the application's request controllers should use client-side HTTPS certificates.
  ///
  /// Defaults to false.
  bool isUsingClientCertificate = false;

  /// The path to a SSL certificate.
  ///
  /// If specified - along with [privateKeyFilePath] - an [Application] will only allow secure connections over HTTPS.
  /// This value is often set through the `--ssl-certificate-path` command line option of `aqueduct serve`. For finer control
  /// over how HTTPS is configured for an application, see [ApplicationChannel.securityContext].
  String certificateFilePath;

  /// The path to a private key.
  ///
  /// If specified - along with [certificateFilePath] - an [Application] will only allow secure connections over HTTPS.
  /// This value is often set through the `--ssl-key-path` command line option of `aqueduct serve`. For finer control
  /// over how HTTPS is configured for an application, see [ApplicationChannel.securityContext].
  String privateKeyFilePath;

  /// Contextual configuration values for each [ApplicationChannel].
  ///
  /// This is a user-specific set of configuration options provided by [ApplicationChannel.initializeApplication].
  /// Each instance of [ApplicationChannel] has access to these values if set.
  Map<String, dynamic> context = {};
}
