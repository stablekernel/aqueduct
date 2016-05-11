import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

void main() {
  setUpAll(() {
    new Logger("aqueduct").onRecord.listen((rec) => print("$rec"));
  });

/*
  Check same-origin requests that contain Origin

  Simple:
    Methods: GET, HEAD, POST
    Headers: Accept, Accept-Language, Content-Language, Last-Event-ID, Content-Type, but only if the value is one of:
      application/x-www-form-urlencoded
      multipart/form-data
      text/plain
      ALWAYS contains Origin (scheme, host, port)
    Must return:
      Access-Control-Allow-Origin: http://api.bob.com
      Access-Control-Allow-Credentials: true (optional)
      Access-Control-Expose-Headers: FooBar (optional)

 */
  group("No CORS Policy", () {
    HttpServer server;

    setUpAll(() async {
      server = await enableController("/a", new RequestHandlerGenerator<NoPolicyController>());
    });
    tearDownAll(() async {
      await server?.close();
    });

    test("Normal request when no CORS policy", () async {
      var resp = await http.get("http://localhost:8000/a");
      expect(resp.statusCode, 200);
      expect(resp.headers["access-control-allow-origin"], isNull);
    });

    test("Origin request when no CORS policy", () async {
      var resp = await http.get("http://localhost:8000/a", headers: {
        "Origin" : "http://somewhereelse.com"
      });
      expect(resp.statusCode, 200);
      expect(resp.headers["access-control-allow-origin"], isNull);
    });

    test("Preflight request when no CORS policy", () async {
      var client = new HttpClient();
      var req = await client.openUrl("OPTIONS", new Uri(scheme: "http", host: "localhost", port: 8000, path: "a"));
      var resp = await req.close();
      expect(resp.statusCode, 404);
    });
  });

  group("Default CORS Policy", () {
    HttpServer server;

    setUpAll(() async {
      server = await enableController("/a", new RequestHandlerGenerator<DefaultPolicyController>());
    });
    tearDownAll(() async {
      await server?.close();
    });

    test("Normal request", () async {
      var resp = await http.get("http://localhost:8000/a");
      expect(resp.statusCode, 200);
      expect(resp.headers["access-control-allow-origin"], isNull);
    });

    test("Origin request, valid", () async {
      var resp = await http.get("http://localhost:8000/a", headers: {
        "Origin" : "http://somewhereelse.com"
      });
      expect(resp.statusCode, 200);
      expect(resp.headers["access-control-allow-origin"], "http://somewhereelse.com");
    });

    test("Preflight request, valid", () async {
      var client = new HttpClient();
      var req = await client.openUrl("OPTIONS", new Uri(scheme: "http", host: "localhost", port: 8000, path: "a"));
      req.headers.add("Origin", "http://localhost");
      req.headers.add("Access-Control-Request-Method", "POST");
      req.headers.add("Access-Control-Request-Headers", "authorization,x-requested-with");
      req.headers.add("Accept", "*/*");
      var resp = await req.close();
      expect(resp.statusCode, 200);
      expect(resp.contentLength, 0);
      expect(resp.headers.value("access-control-allow-origin"), "http://localhost");
      expect(resp.headers.value("access-control-allow-methods"), "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-allow-headers"), "authorization, x-requested-with, content-type, accept");
    });

  });
}

Future<HttpServer> enableController(String pattern, RequestHandler controller) async {
  var router = new Router();
  router.route(pattern).then(controller);

  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8000);
  server.map((httpReq) => new ResourceRequest(httpReq)).listen((req) {
    router.deliver(req);
  });

  return server;
}

class NoPolicyController extends HttpController {
  NoPolicyController() {
    policy = null;
  }

  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("getAll");
  }
}

class DefaultPolicyController extends HttpController {
  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("getAll");
  }
}

