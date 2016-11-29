import 'dart:io';
import 'application.dart';
import '../http/request_sink.dart';

/// A set of values to configure an instance of [Application].
class ApplicationConfiguration {
  /// The address to listen for HTTP requests on.
  ///
  /// By default, this address will default to 'any' address (0.0.0.0). If [isIpv6Only] is true,
  /// 'any' will be any IPv6 address, otherwise, it will be any IPv4 or IPv6 address.
  ///
  /// This value may be an [InternetAddress] or a [String].
  dynamic address;

  /// The port to listen for HTTP requests on.
  ///
  /// Defaults to 8080.
  int port = 8080;

  /// Whether or not the application should only receive connections over IPv6.
  ///
  /// Defaults to false. This flag impacts the default value of the [address] property.
  bool isIpv6Only = false;

  /// Whether or not the application's request controllers should use client-side HTTPS certificates.
  ///
  /// Defaults to false.
  bool isUsingClientCertificate = false;

  /// Information for securing the application over HTTPS.
  ///
  /// Defaults to null. If this is null, this application will run unsecured over HTTP. To
  /// run securely over HTTPS, this property must be set with valid security details.
  SecurityContext securityContext = null;

  /// Options for each [RequestSink] to use when in this application.
  ///
  /// Allows delivery of custom configuration parameters to [RequestSink] instances
  /// that are attached to this application.
  Map<String, dynamic> configurationOptions;
}
