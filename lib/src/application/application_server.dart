import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:logging/logging.dart';
import '../http/request.dart';
import 'package:aqueduct/src/application/channel.dart';
import '../http/request_controller.dart';
import 'application.dart';
import 'application_configuration.dart';
import 'package:stack_trace/stack_trace.dart';

/// Manages listening for HTTP requests and delivering them to [ApplicationChannel] instances.
///
/// An Aqueduct application creates instances of this type to pair an HTTP server and an
/// instance of an application-specific [ApplicationChannel]. Instances are created by [Application]
/// and shouldn't be created otherwise.
class ApplicationServer {
  /// Creates an instance of this type.
  ///
  /// You should not need to invoke this method directly.
  ApplicationServer(ClassMirror channelType, this.configuration, this.identifier, {this.captureStack: false}) {
    channel = channelType.newInstance(new Symbol(""), []).reflectee;
    channel.server = this;
    channel.configuration = configuration;
  }


  /// The configuration this instance used to start its [channel].
  ApplicationConfiguration configuration;

  /// The underlying [HttpServer].
  HttpServer server;

  /// The instance of [ApplicationChannel] serving requests.
  ApplicationChannel channel;

  RequestController entryPoint;

  /// Used during debugging to capture the stacktrace better for asynchronous calls.
  ///
  /// Defaults to false.
  bool captureStack;

  /// Target for sending messages to other [ApplicationChannel] isolates.
  ///
  /// Events are added to this property by instances of [ApplicationMessageHub] and should not otherwise be used.
  EventSink<dynamic> hubSink;

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
  /// Do not invoke this method directly, [Application] instances are responsible
  /// for calling this method.
  Future start({bool shareHttpServer: false}) async {
    logger.fine("ApplicationServer($identifier).start entry");

    await channel.willOpen();

    entryPoint = channel.entryPoint;
    entryPoint.prepare();

    logger.fine("ApplicationServer($identifier).start binding HTTP");
    var securityContext = channel.securityContext;
    if (securityContext != null) {
      _requiresHTTPS = true;

      server = await HttpServer.bindSecure(configuration.address,
          configuration.port, securityContext,
          requestClientCertificate: configuration.isUsingClientCertificate,
          v6Only: configuration.isIpv6Only,
          shared: shareHttpServer);
    } else {
      _requiresHTTPS = false;

      server = await HttpServer.bind(
          configuration.address, configuration.port,
          v6Only: configuration.isIpv6Only, shared: shareHttpServer);
    }

    logger.fine("ApplicationServer($identifier).start bound HTTP");
    return didOpen();
  }

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
  /// [ApplicationChannel.didOpen] is invoked after this opening has completed.
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

    channel.didOpen();
    logger.info("Server aqueduct/$identifier started.");
  }

  void sendApplicationEvent(dynamic event) {
    // By default, do nothing
  }
}