part of monadart;

class Application {
  List<_RouteSpec> routeSpecs = [];
  List<_ServerRecord> servers = [];

  dynamic address;
  int port = 8080;
  int instanceCount = 1;
  bool ipv6Only = false;
  bool useClientCertificate = false;
  String serverCertificateName = null;

  void addControllerForPath(String path, Type controllerType) {
    // Validate this controller here
    routeSpecs.add(new _RouteSpec(path, controllerType));
  }



  start() async {
    if (address == null) {
      if (ipv6Only) {
        address = InternetAddress.ANY_IP_V6;
      } else {
        address = InternetAddress.ANY_IP_V4;
      }
    }

    for (int i = 0; i < instanceCount; i++) {
      var serverRecord = await spawn();
      servers.add(serverRecord);
    }

    servers.forEach((i) {
      i.resume();
    });
  }

  Future<_ServerRecord> spawn() async {
    var isolate = await Isolate.spawn(_Server.entry, this, paused: true);
    var receivePort = new ReceivePort();
    isolate.setErrorsFatal(true);
    isolate.addErrorListener(receivePort.sendPort);

    var record = new _ServerRecord(isolate, receivePort);
    record.receivePort.listen((msg) {
      print("Restarting server, error: ${msg}");
      unlink(record);
      spawn();
    });
    return record;
  }

  void unlink(_ServerRecord rec) {
    rec.receivePort.close();
    servers.remove(rec);
  }
}

class _RouteSpec {
  final Type controller;
  final String path;
  _RouteSpec(this.path, this.controller);
}

class _Server {
  HttpServer server;
  Router router = new Router();
  Application application;

  _Server(Application app) {
    application = app;
  }

  void routeRequest(ResourceRequest req, Type controllerType) {
    ResourceController controller = reflectClass(controllerType).newInstance(new Symbol(""), []).reflectee;
    controller.resourceRequest = req;
    controller.process();
  }

  Future start() async {
    var onBind = (serv) {
      server = serv;

      application.routeSpecs.forEach((routeSpec) {
        router.addRoute(routeSpec.path).listen((req) {
          routeRequest(req, routeSpec.controller);
        });
      });

      server.map((req) => new ResourceRequest(req))
        .listen(router.listener);
    };

    if (application.serverCertificateName != null) {
      HttpServer
          .bindSecure(application.address, application.port,
              certificateName: application.serverCertificateName,
              v6Only: application.ipv6Only,
              shared: application.instanceCount > 1)
          .then(onBind);
    } else if (application.useClientCertificate) {
      HttpServer
          .bindSecure(application.address, application.port,
              requestClientCertificate: true,
              v6Only: application.ipv6Only,
              shared: application.instanceCount > 1)
          .then(onBind);
    } else {
      HttpServer
          .bind(application.address, application.port,
              v6Only: application.ipv6Only,
              shared: application.instanceCount > 1)
          .then(onBind);
    }
  }

  static void entry(Application params) {
    var server = new _Server(params);

    server.start();
  }
}

class _ServerRecord {
  final Isolate isolate;
  final ReceivePort receivePort;

  _ServerRecord(this.isolate, this.receivePort);

  void resume() {
    isolate.resume(isolate.pauseCapability);
  }
}
