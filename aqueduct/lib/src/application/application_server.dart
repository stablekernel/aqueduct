import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/application/channel.dart';
import 'package:logging/logging.dart';
import 'package:runtime/runtime.dart';

import '../http/controller.dart';
import '../http/request.dart';
import 'application.dart';
import 'options.dart';

/// Listens for HTTP requests and delivers them to its [ApplicationChannel] instance.
///
/// An Aqueduct application creates instances of this type to pair an HTTP server and an
/// instance of an [ApplicationChannel] subclass. Instances are created by [Application]
/// and shouldn't be created otherwise.
class ApplicationServer {
  /// Creates a new server.
  ///
  /// You should not need to invoke this method directly.
  ApplicationServer(this.channelType, this.options, this.identifier) {
    channel = (RuntimeContext.current[channelType] as ChannelRuntime).instantiateChannel()
      ..server = this
      ..options = options;
  }

  /// The configuration this instance used to start its [channel].
  ApplicationOptions options;

  /// The underlying [HttpServer].
  HttpServer server;

  /// The instance of [ApplicationChannel] serving requests.
  ApplicationChannel channel;

  /// The cached entrypoint of [channel].
  Controller entryPoint;

  final Type channelType;

  /// Target for sending messages to other [ApplicationChannel.messageHub]s.
  ///
  /// Events are added to this property by instances of [ApplicationMessageHub] and should not otherwise be used.
  EventSink<dynamic> hubSink;

  /// Whether or not this server requires an HTTPS listener.
  bool get requiresHTTPS => _requiresHTTPS;
  bool _requiresHTTPS = false;

  /// The unique identifier of this instance.
  ///
  /// Each instance has its own identifier, a numeric value starting at 1, to identify it
  /// among other instances.
  int identifier;

  /// The logger of this instance
  Logger get logger => Logger("aqueduct");

  /// Starts this instance, allowing it to receive HTTP requests.
  ///
  /// Do not invoke this method directly.
  Future start({bool shareHttpServer = false}) async {
    logger.fine("ApplicationServer($identifier).start entry");

    await channel.prepare();

    entryPoint = channel.entryPoint;
    entryPoint.didAddToChannel();

    logger.fine("ApplicationServer($identifier).start binding HTTP");
    final securityContext = channel.securityContext;
    if (securityContext != null) {
      _requiresHTTPS = true;

      server = await HttpServer.bindSecure(
          options.address, options.port, securityContext,
          requestClientCertificate: options.isUsingClientCertificate,
          v6Only: options.isIpv6Only,
          shared: shareHttpServer);
    } else {
      _requiresHTTPS = false;

      server = await HttpServer.bind(options.address, options.port,
          v6Only: options.isIpv6Only, shared: shareHttpServer);
    }

    logger.fine("ApplicationServer($identifier).start bound HTTP");
    return didOpen();
  }

  /// Closes this HTTP server and channel.
  Future close() async {
    logger.fine("ApplicationServer($identifier).close Closing HTTP listener");
    await server?.close(force: true);
    logger.fine("ApplicationServer($identifier).close Closing channel");
    await channel?.close();

    // This is actually closed by channel.messageHub.close, but this shuts up the analyzer.
    hubSink?.close();
    logger.fine("ApplicationServer($identifier).close Closing complete");
  }

  /// Invoked when this server becomes ready receive requests.
  ///
  /// [ApplicationChannel.willStartReceivingRequests] is invoked after this opening has completed.
  Future didOpen() async {
    server.serverHeader = "aqueduct/$identifier";

    logger.fine("ApplicationServer($identifier).didOpen start listening");
    server.map((baseReq) => Request(baseReq)).listen(entryPoint.receive);

    channel.willStartReceivingRequests();
    logger.info("Server aqueduct/$identifier started.");
  }

  void sendApplicationEvent(dynamic event) {
    // By default, do nothing
  }
}
