import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

import '../http/request.dart';
import '../http/request_sink.dart';
import 'application.dart';
import 'application_configuration.dart';
import 'package:stack_trace/stack_trace.dart';

/// Manages listening for HTTP requests and delivering them to [RequestSink] instances.
///
/// An Aqueduct application creates instances of this type to pair an HTTP server and an
/// instance of an application-specific [RequestSink]. Instances are created by [Application]
/// and shouldn't be created otherwise.
class ApplicationServer {
  /// The configuration this instance used to start its [sink].
  ApplicationConfiguration configuration;

  /// The underlying [HttpServer].
  HttpServer server;

  /// The instance of [RequestSink] serving requests.
  RequestSink sink;

  bool get requiresHTTPS => _requiresHTTPS;
  bool _requiresHTTPS = false;

  /// The unique identifier of this instance.
  ///
  /// Each instance has its own identifier, a numeric value starting at 1, to identify it
  /// among other instances.
  int identifier;

  /// The logger of this instance
  Logger get logger => new Logger("aqueduct");

  /// Creates an instance of this type.
  ///
  /// You should not need to invoke this method directly.
  ApplicationServer(this.sink, this.configuration, this.identifier) {
    sink.server = this;
  }

  /// Starts this instance, allowing it to receive HTTP requests.
  ///
  /// Do not invoke this method directly, [Application] instances are responsible
  /// for calling this method.
  Future start({bool shareHttpServer: false}) async {
    try {
      sink.setupRouter(sink.router);
      sink.router?.finalize();
      sink.nextController = sink.initialController;

      var securityContext = sink.securityContext;
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

      server.autoCompress = true;
      await didOpen();
    } catch (e) {
      await server?.close(force: true);
      rethrow;
    }
  }

  /// Invoked when this server becomes ready receive requests.
  ///
  /// This method will invoke [RequestSink.open] and await for it to finish.
  /// Once [RequestSink.open] completes, the underlying [server]'s HTTP requests
  /// will be sent to this instance's [sink].
  ///
  /// [RequestSink.didOpen] is invoked after this opening has completed.
  Future didOpen() async {
    logger.info("Server aqueduct/$identifier started.");

    server.serverHeader = "aqueduct/${this.identifier}";

    await sink.willOpen();

    server.map((baseReq) => new Request(baseReq)).listen(_dispatchRequest);

    sink.didOpen();
  }

  void _dispatchRequest(Request request) {
    logger.fine("Request received $request.", request);

    Chain.capture(() {
      sink.willReceiveRequest(request).then((_) {
        sink.receive(request);
      });
    });
  }
}
