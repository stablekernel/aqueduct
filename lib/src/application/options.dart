import 'dart:io';
import 'application.dart';
import 'package:aqueduct/src/application/channel.dart';

/// A set of values to configure an instance of [Application].
///
/// Instances of this type are configured by the command-line arguments for `aqueduct serve` and passed to [ApplicationChannel] instances in their constructor.
/// Instances of this type are also passed to to a [ApplicationChannel] subclass's `initializeApplication` method before it is instantiated. This allows
/// values to be modified prior to starting the server. See [ApplicationChannel] for example usage.
class ApplicationOptions {
  /// Whether or not this application is being used to document an API.
  ///
  /// Defaults to false. If the application is being instantiated for the purpose of documenting the API,
  /// this flag will be true. This allows [ApplicationChannel] subclasses to take a different initialization path
  /// when documenting vs. running the application.
  bool isDocumenting = false;

  /// The absolute path of the configuration file for this application.
  ///
  /// This value is used by [ApplicationChannel] subclasses to read a configuration file. A [ApplicationChannel] can choose
  /// to read values from this file at different initialization points. This value is set automatically
  /// when using `aqueduct serve`.
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
  /// Defaults to 8081.
  int port = 8081;

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

  /// Contextual values for each [ApplicationChannel] provided by [ApplicationChannel.initializeApplication]
  ///
  /// This is a user-specific set of configuration options provided by [ApplicationChannel.initializeApplication].
  /// Each instance of [ApplicationChannel] has access to these values if set.
  Map<String, dynamic> context = {};
}
