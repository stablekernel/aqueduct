import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:mirrors';
import '../helpers.dart';

void main() {
  HttpServer server;

  setUpAll(() {
    new ManagedContext(
        new ManagedDataModel([TestModel]), new DefaultPersistentStore());
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  group("Happy path", () {

  });

  group("Programer error cases", () {
    test("Does not implement HTTPSerializable", () async {

    });
  });

  group("Input error cases", () {
    test("Is List when expecting Map", () async {

    });

    test("Is Map when expecting List", () async {

    });
  });
}



class TestModel extends ManagedObject<_TestModel> implements _TestModel {}
class _TestModel {
  @managedPrimaryKey
  int id;

  String name;
}

class CrashModel implements HTTPSerializable {
  void fromRequestBody(dynamic requestBody) {
    throw new Exception("whatever");
  }

  dynamic asSerializable() {
    return null;
  }
}

Future<HttpServer> enableController(String pattern, Type controller) async {
  var router = new Router();
  router.route(pattern).generate(
          () => reflectClass(controller).newInstance(new Symbol(""), []).reflectee);
  router.finalize();

  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 4040);
  server.map((httpReq) => new Request(httpReq)).listen(router.receive);

  return server;
}