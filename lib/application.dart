part of monadart;

class Application {
  List<_ServerRecord> servers = [];
  int serverIdentifierCounter = 0;

  /* Application Data */
  List<_RouteSpec> routeSpecs = [];
  dynamic address;
  int port = 8080;
  int instanceCount = 1;
  bool isIpv6Only = false;
  bool isUsingClientCertificate = false;
  String serverCertificateName = null;

  void addControllerForPath(Type controllerType, String path) {
    // Validate this controller here
    routeSpecs.add(new _RouteSpec(path, controllerType));
  }

  Future start() async {
    if (address == null) {
      if (isIpv6Only) {
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
    serverIdentifierCounter++;

    var appData = new _ApplicationData(routeSpecs, address, port,
      isIpv6Only, isUsingClientCertificate, serverCertificateName,
      (instanceCount > 1 ? true : false), serverIdentifierCounter);

    var receivePort = new ReceivePort();
    var msg = new _InitialServerMessage(appData, receivePort.sendPort);
    var isolate = await Isolate.spawn(_Server.entry, msg, paused: true);
    isolate.addErrorListener(receivePort.sendPort);


    return new _ServerRecord(isolate, receivePort, serverIdentifierCounter);
  }
}

class _ApplicationData
{
  List<_RouteSpec> routeSpecs;
  dynamic address;
  int port;
  bool ipv6Only;
  bool useClientCertificate;
  String serverCertificateName;
  bool isShared;
  int serverIdentifier;

  _ApplicationData(this.routeSpecs, this.address, this.port, this.ipv6Only,
    this.useClientCertificate, this.serverCertificateName,
    this.isShared, this.serverIdentifier);
}


class _RouteSpec {
  final Type controller;
  final String path;
  _RouteSpec(this.path, this.controller);
}


class _Server {
  HttpServer server;
  Router router = new Router();
  _ApplicationData applicationData;
  SendPort parentMessagePort;

  _Server(this.applicationData, this.parentMessagePort);

  void routeRequest(ResourceRequest req, Type controllerType) {
    ResourceController controller = reflectClass(controllerType).newInstance(new Symbol(""), []).reflectee;
    controller.resourceRequest = req;
    controller.process();
  }

  Future start() async {
    var onBind = (serv) {
      server = serv;
      server.serverHeader = "monadart/${applicationData.serverIdentifier}";
      applicationData.routeSpecs.forEach((routeSpec) {
        router.addRoute(routeSpec.path).listen((req) {
          routeRequest(req, routeSpec.controller);
        });
      });

      server.map((req) => new ResourceRequest(req))
        .listen(router.listener);
    };

    if (applicationData.serverCertificateName != null) {
      HttpServer
          .bindSecure(applicationData.address, applicationData.port,
              certificateName: applicationData.serverCertificateName,
              v6Only: applicationData.ipv6Only,
              shared: applicationData.isShared)
          .then(onBind);
    } else if (applicationData.useClientCertificate) {
      HttpServer
          .bindSecure(applicationData.address, applicationData.port,
              requestClientCertificate: true,
              v6Only: applicationData.ipv6Only,
              shared: applicationData.isShared)
          .then(onBind);
    } else {
      HttpServer
          .bind(applicationData.address, applicationData.port,
              v6Only: applicationData.ipv6Only,
              shared: applicationData.isShared)
          .then(onBind);
    }
  }

  static void entry(_InitialServerMessage params) {
    var server = new _Server(params.application, params.parentMessagePort);

    server.start();
  }
}

class _ServerRecord {
  final Isolate isolate;
  final ReceivePort receivePort;
  final int identifier;

  _ServerRecord(this.isolate, this.receivePort, this.identifier);

  void resume() {
    isolate.resume(isolate.pauseCapability);
  }
}


class _InitialServerMessage {
  _ApplicationData application;
  SendPort parentMessagePort;
  _InitialServerMessage(this.application, this.parentMessagePort);
}
