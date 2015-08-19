@TestOn("vm")

import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import '../lib/monadart.dart';
import 'dart:convert';
import 'dart:async';

void main() {

  HttpServer server;

  void serve(HttpController controller, Map<String, dynamic> pathParams) {
    server.map((req) => new ResourceRequest(req)).listen((ResourceRequest resReq) {
      controller.resourceRequest = resReq;
      resReq.pathParameters = pathParams;
      controller.process();
    });
  }


  setUp(() {
    return HttpServer.bind(InternetAddress.ANY_IP_V4, 4040).then((incomingServer) {
      server = incomingServer;
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



}


class TController extends HttpController {

  @httpGet
  Future<Response> getAll() async {
    return new Response.ok("getAll");
  }

  @httpGet
  Future<Response> getOne(int id) async {
    print("${id.runtimeType}");
    return new Response.ok("${id}");
  }

  @httpGet
  Future<Response> getBoth(int id, String flag) async {
    return new Response.ok("${id}${flag}");
  }

  @httpPut
  Future<Response> putOne(int id) async {
    throw new Exception("Exception!");
    return new Response.ok("$id");
  }

  @httpPost
  Future<Response> post() async {
    var body = this.requestBody;

    return new Response.ok(body);
  }
}