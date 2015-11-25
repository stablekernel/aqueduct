import 'package:monadart/monadart.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

Future main() async {
  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8080);
  server.listen((req) {
    var reqHandler = new RequestHandler(requestHandler: (req) {
      throw new HttpResponseException(400, "This was the error");
    });

    var resReq = new ResourceRequest(req);
    reqHandler.deliver(resReq);
//    req.response.statusCode = 200;
//    req.response.headers.add(HttpHeaders.CONTENT_TYPE, "application/json");
//    req.response.writeln(JSON.encode({"error" : "error text"}));
//    req.response.close();
  });

  test ("Client decodes", () async {
    var tc = new TestClient()..host = "http://localhost:8080";
    var response = await tc.jsonRequest("/any").get();
    print("${response}");

  });
}