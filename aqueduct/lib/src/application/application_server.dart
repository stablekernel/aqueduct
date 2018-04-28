import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:logging/logging.dart';
import '../http/request.dart';
import 'package:aqueduct/src/application/channel.dart';
import '../http/controller.dart';
import 'application.dart';
import 'options.dart';
import 'package:stack_trace/stack_trace.dart';

/// Listens for HTTP requests and delivers them to its [ApplicationChannel] instance.
///
/// An Aqueduct application creates instances of this type to pair an HTTP server and an
/// instance of an [ApplicationChannel] subclass. Instances are created by [Application]
/// and shouldn't be created otherwise.
class ApplicationServer {
  /// Creates a new server that sending requests to [channelType].
  ///
  /// You should not need to invoke this method directly.
  ApplicationServer(ClassMirror channelType, this.options, this.identifier, {this.captureStack: false}) {
    channel = channelType.newInstance(new Symbol(""), []).reflectee;
    channel.server = this;
    channel.options = options;
  }

  /// The configuration this instance used to start its [channel].
  ApplicationOptions options;

  /// The underlying [HttpServer].
  HttpServer server;

  /// The instance of [ApplicationChannel] serving requests.
  ApplicationChannel channel;

  /// The cached entrypoint of [channel].
  Controller entryPoint;

  /// Used during debugging to capture the stacktrace better for asynchronous calls.
  ///
  /// Defaults to false.
  bool captureStack;

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
  Logger get logger => new Logger("aqueduct");

  /// Starts this instance, allowing it to receive HTTP requests.
  ///
  /// Do not invoke this method directly.
  Future start({bool shareHttpServer: false}) async {
    logger.fine("ApplicationServer($identifier).start entry");

    await channel.prepare();

    entryPoint = channel.entryPoint;
    entryPoint.didAddToChannel();

    logger.fine("ApplicationServer($identifier).start binding HTTP");
    var securityContext = channel.securityContext;
    if (securityContext != null) {
      _requiresHTTPS = true;

      server = await HttpServer.bindSecure(options.address,
          options.port, securityContext,
          requestClientCertificate: options.isUsingClientCertificate,
          v6Only: options.isIpv6Only,
          shared: shareHttpServer);
    } else {
      _requiresHTTPS = false;

      server = await HttpServer.bind(
          options.address, options.port,
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
    server.serverHeader = "aqueduct/${this.identifier}";

    logger.fine("ApplicationServer($identifier).didOpen start listening");
    if (captureStack) {
      server.map((baseReq) => new Request(baseReq)).listen((req) {
        Chain.capture(() {
          entryPoint.receive(req);
        });
      });
    } else {
      server.map((baseReq) => new Request(baseReq)).listen(entryPoint.receive);
    }

    channel.willStartReceivingRequests();
    logger.info("Server aqueduct/$identifier started.");
  }

  void sendApplicationEvent(dynamic event) {
    // By default, do nothing
  }
}