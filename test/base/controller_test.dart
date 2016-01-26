@TestOn("vm")
import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:monadart/monadart.dart';
import 'dart:convert';
import 'dart:async';

void main() {

  HttpServer server;

  setUp(() {
  });

  tearDown(() async {
    if (server != null) {
      await server.close();
    }
  });

  tearDownAll(() async {
    if (server != null) {
      await server.close();
    }
  });

  test("Get w/ no params", () async {
    server = await enableController("/a", new RequestHandlerGenerator<TController>());

    var res = await http.get("http://localhost:4040/a");

    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), "getAll");

  });

  test("Get w/ 1 param", () async {
    server = await enableController("/a/:id", new RequestHandlerGenerator<TController>());
    var res = await http.get("http://localhost:4040/a/123");

    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), "123");
  });

  test("Get w/ 2 param", () async {
    server = await enableController("/a/:id/:flag", new RequestHandlerGenerator<TController>());

    var res = await http.get("http://localhost:4040/a/123/active");

    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), "123active");
  });

  test("Unsupported method", () async {
    server = await enableController("/a", new RequestHandlerGenerator<TController>());

    var res = await http.delete("http://localhost:4040/a");

    expect(res.statusCode, 404);

    // expect headers to have Allow: GET, POST, PUT
  });

  test("Crashing handler delivers 500", () async {
    server = await enableController("/a/:id", new RequestHandlerGenerator<TController>());

    var res = await http.put("http://localhost:4040/a/a");

    expect(res.statusCode, 500);
  });

  test("Only respond to appropriate content types", () async {
    server = await enableController("/a", new RequestHandlerGenerator<TController>());

    var body = JSON.encode({"a" : "b"});
    var res = await http.post("http://localhost:4040/a", headers: {"Content-Type" : "application/json"}, body: body);
    expect(res.statusCode, 200);
    expect(JSON.decode(res.body), equals({"a" : "b"}));
  });

  test("Return error when wrong content type", () async {
    server = await enableController("/a", new RequestHandlerGenerator<TController>());

    var body = JSON.encode({"a" : "b"});
    var res = await http.post("http://localhost:4040/a", headers: {"Content-Type" : "application/somenonsense"}, body: body);
    expect(res.statusCode, 415);
  });

  test("Query parameters get delivered if exposed as optional params", () async {
    server = await enableController("/a", new RequestHandlerGenerator<QController>());

    var res = await http.get("http://localhost:4040/a?opt=x");
    expect(res.body, "\"OK\"");

    res = await http.get("http://localhost:4040/a");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/a?option=x");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/a?opt=x&q=1");
    expect(res.body, "\"OK\"");

    await server.close(force: true);

    server = await enableController("/:id", new RequestHandlerGenerator<QController>());

    res = await http.get("http://localhost:4040/123?opt=x");
    expect(res.body, "\"OK\"");

    res = await http.get("http://localhost:4040/123");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/123?option=x");
    expect(res.body, "\"NOT\"");

    res = await http.get("http://localhost:4040/123?opt=x&q=1");
    expect(res.body, "\"OK\"");
  });


  test("Path parameters are parsed into appropriate type", () async {
    server = await enableController("/:id", new RequestHandlerGenerator<IntController>());

    var res = await http.get("http://localhost:4040/123");
    expect(res.body, "\"246\"");

    res = await http.get("http://localhost:4040/word");
    expect(res.statusCode, 400);

    await server.close(force: true);

    server = await enableController("/:time", new RequestHandlerGenerator<DateTimeController>());
    res = await http.get("http://localhost:4040/2001-01-01T00:00:00.000000Z");
    expect(res.statusCode, 200);
    expect(res.body, "\"2001-01-01 00:00:05.000Z\"");

    res = await http.get("http://localhost:4040/foobar");
    expect(res.statusCode, 400);
  });

  test("Query parameters are parsed into appropriate types", () async {
    server = await enableController("/a", new RequestHandlerGenerator<IntController>());
    var res = await http.get("http://localhost:4040/a?opt=12");
    expect(res.body, "\"12\"");

    res = await http.get("http://localhost:4040/a?opt=word");
    expect(res.statusCode, 400);

    res = await http.get("http://localhost:4040/a?foo=2");
    expect(res.statusCode, 200);
    expect(res.body, "\"null\"");

    await server.close();

    server = await enableController("/a", new RequestHandlerGenerator<DateTimeController>());
    res = await http.get("http://localhost:4040/a?opt=2001-01-01T00:00:00.000000Z");
    expect(res.statusCode, 200);
    expect(res.body, "\"2001-01-01 00:00:00.000Z\"");

    res = await http.get("http://localhost:4040/a?opt=word");
    expect(res.statusCode, 400);

    res = await http.get("http://localhost:4040/a?foo=2001-01-01T00:00:00.000000Z");
    expect(res.statusCode, 200);
  });

  test("Query parameters can be obtained from x-www-form-urlencoded", () async {
    server = await enableController("/a", new RequestHandlerGenerator<IntController>());
    var res = await http.post("http://localhost:4040/a", headers: {"Content-Type" : "application/x-www-form-urlencoded"}, body: "opt=7");
    expect(res.body, '"7"');
  });

  test("Model and lists are encoded in response", () async {
    server = await enableController("/a/:thing", new RequestHandlerGenerator<ModelEncodeController>());
    var res = await http.get("http://localhost:4040/a/list");
    expect(JSON.decode(res.body), [{"id" : 1}, {"id" : 2}]);

    res = await http.get("http://localhost:4040/a/model");
    expect(JSON.decode(res.body), {"id" : 1, "name" : "Bob"});

    res = await http.get("http://localhost:4040/a/modellist");
    expect(JSON.decode(res.body), [{"id" : 1, "name" : "Bob"}, {"id" : 2, "name" : "Fred"}]);

    res = await http.get("http://localhost:4040/a/null");
    expect(JSON.decode(res.body), isNull);
    expect(res.statusCode, 200);
  });

  test("Sending bad JSON returns 500", () async {
    server = await enableController("/a", new RequestHandlerGenerator<TController>());
    var res = await http.post("http://localhost:4040/a", body: "{`foobar' : 2}", headers: {"Content-Type" : "application/json"});
    expect(res.statusCode, 400);

    res = await http.get("http://localhost:4040/a");
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

  @httpPost
  Future<Response> create({int opt: null}) async {
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

class ModelEncodeController extends HttpController {
  @httpGet getThings(String thing) async {
    if (thing == "list") {
      return new Response.ok([{"id" : 1}, {"id" : 2}]);
    }

    if (thing == "model") {
      var m = new TestModel()
        ..id = 1
        ..name = "Bob";
      return new Response.ok(m);
    }

    if (thing == "modellist") {
      var m1 = new TestModel()
        ..id = 1
        ..name = "Bob";
      var m2 = new TestModel()
        ..id = 2
        ..name = "Fred";

      return new Response.ok([m1, m2]);
    }

    if (thing == "null") {
      return new Response.ok(null);
    }
  }
}

Future<HttpServer> enableController(String pattern, RequestHandler controller) async {
  var router = new Router();
  router.route(pattern).then(controller);

  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new ResourceRequest(httpReq)).listen((req) {
    router.deliver(req);
  });

  return server;
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  int id;
  String name;
}