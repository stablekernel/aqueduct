@TestOn("vm")
import "package:test/test.dart";
import "dart:core";
import 'dart:mirrors';
import "dart:io";
import 'package:http/http.dart' as http;
import '../lib/monadart.dart';
import 'dart:convert';
import 'dart:async';

void main() {

  HttpServer server;
  HttpController currentController;
  Map<String, String> currentPathParams;
  HttpController getCurrentController() => currentController;
  Map<String, String> getCurrentPathParams() => currentPathParams;

  void serve(HttpController controller, Map<String, dynamic> pathParams) {
    currentController = controller;
    var m = {};
    if (pathParams != null) {
      pathParams.forEach((k, v) {
        m[k] = "$v";
      });

      currentPathParams = m;
    } else {
      currentPathParams = null;
    }
  }


  setUp(() {
    return HttpServer.bind(InternetAddress.ANY_IP_V4, 4040).then((incomingServer) {
      server = incomingServer;
      server.map((req) => new ResourceRequest(req)).listen((ResourceRequest resReq) {
        getCurrentController().resourceRequest = resReq;

        getCurrentController().resourceRequest.pathParameters = getCurrentPathParams();

        getCurrentController().process();
      });

    });
  });

  tearDown(() {
    server.close();
  });

  test("Get w/ no params", () async {
    serve(new TController(), null);

    var res = await http.get("http://localhost:4040");

    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), "getAll");
  });

  test("Get w/ 1 param", () async {
    serve(new TController(), {"id" : 123});

    var res = await http.get("http://localhost:4040");

    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), "123");
  });

  test("Get w/ 2 param", () async {
    serve(new TController(), {"id" : 123, "flag" : "active"});

    var res = await http.get("http://localhost:4040");

    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), "123active");
  });

  test("Unsupported method", () async {
    serve(new TController(), null);

    var res = await http.delete("http://localhost:4040");

    expect(res.statusCode, 404);
    // expect headers to have Allow: GET, POST, PUT
  });

  test("Crashing handler delivers 500", () async {
    serve(new TController(), {"id" : 123});
    var res = await http.put("http://localhost:4040");

    expect(res.statusCode, 500);
  });

  test("Only respond to appropriate content types", () async {
    serve(new TController(), null);
    var body = JSON.encode({"a" : "b"});
    var res = await http.post("http://localhost:4040", headers: {"Content-Type" : "application/json"}, body: body);
    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), equals({"a" : "b"}));
  });

  test("Return error when wrong content type", () async {
    serve(new TController(), null);
    var body = JSON.encode({"a" : "b"});
    var res = await http.post("http://localhost:4040", headers: {"Content-Type" : "application/somenonsense"}, body: body);
    expect(res.statusCode, 415);
  });

  test("Query parameters get delivered if exposed as optional params", () async {
    serve(new QController(), null);

    var res = await http.get("http://localhost:4040/a?opt=x");
    expect(res.body, "\"OK\"");

    res = await http.get("http://localhost:4040/a");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/a?option=x");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/a?opt=x&q=1");
    expect(res.body, "\"OK\"");

    ///
    serve(new QController(), {"id" : "123"});

    res = await http.get("http://localhost:4040/a?opt=x");
    expect(res.body, "\"OK\"");

    res = await http.get("http://localhost:4040/a");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/a?option=x");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/a?opt=x&q=1");
    expect(res.body, "\"OK\"");
  });


  test("Path parameters are parsed into appropriate type", () async {
    serve(new IntController(), {"id" : "123"});
    var res = await http.get("http://localhost:4040/a");
    expect(res.body, "\"246\"");

    serve(new IntController(), {"id" : "word"});
    res = await http.get("http://localhost:4040/a");
    expect(res.statusCode, 400);

    serve(new DateTimeController(), {"time" : "2001-01-01T00:00:00.000000Z"});
    res = await http.get("http://localhost:4040/a");
    expect(res.statusCode, 200);
    expect(res.body, "\"2001-01-01 00:00:05.000Z\"");

    serve(new DateTimeController(), {"time" : "foobar"});
    res = await http.get("http://localhost:4040/a");
    expect(res.statusCode, 400);
  });

  test("Query parameters are parsed into appropriate types", () async {
    serve(new IntController(), null);
    var res = await http.get("http://localhost:4040/a?opt=12");
    expect(res.body, "\"12\"");

    serve(new IntController(), null);
    res = await http.get("http://localhost:4040/a?opt=word");
    expect(res.statusCode, 400);

    serve(new IntController(), null);
    res = await http.get("http://localhost:4040/a?foo=2");
    expect(res.statusCode, 200);
    expect(res.body, "\"null\"");

    serve(new DateTimeController(), null);
    res = await http.get("http://localhost:4040/a?opt=2001-01-01T00:00:00.000000Z");
    expect(res.statusCode, 200);
    expect(res.body, "\"2001-01-01 00:00:00.000Z\"");

    serve(new DateTimeController(), null);
    res = await http.get("http://localhost:4040/a?opt=word");
    expect(res.statusCode, 400);

    serve(new DateTimeController(), null);
    res = await http.get("http://localhost:4040/a?foo=2001-01-01T00:00:00.000000Z");
    expect(res.statusCode, 200);
  });
}


class TController extends HttpController {

  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("getAll");
  }

  @httpGet
  Future<Response> getOne(String id) async {
    print("${id.runtimeType}");
    return new Response.ok("${id}");
  }

  @httpGet
  Future<Response> getBoth(String id, String flag) async {
    return new Response.ok("${id}${flag}");
  }

  @httpPut
  Future<Response> putOne(String id) async {
    throw new Exception("Exception!");
    return new Response.ok("$id");
  }

  @httpPost
  Future<Response> post() async {
    var body = this.requestBody;

    return new Response.ok(body);
  }
}

class QController extends HttpController {
  @httpGet
  Future<Response> getAll({String opt: null}) async {
    if (opt == null) {
      return new Response.ok("NOT");
    }

    return new Response.ok("OK");
  }

  @httpGet
  Future<Response> getOne(String id, {String opt: null}) async {
    if (opt == null) {
      return new Response.ok("NOT");
    }

    return new Response.ok("OK");
  }
}

class IntController extends HttpController {
  @httpGet
  Future<Response> getOne(int id) async {
    return new Response.ok("${id * 2}");
  }
  @httpGet
  Future<Response> getAll({int opt: null}) async {
    return new Response.ok("${opt}");
  }
}

class DateTimeController extends HttpController {
  @httpGet
  Future<Response> getOne(DateTime time) async {
    return new Response.ok("${time.add(new Duration(seconds: 5))}");
  }
  @httpGet
  Future<Response> getAll({DateTime opt: null}) async {
    return new Response.ok("${opt}");
  }

}