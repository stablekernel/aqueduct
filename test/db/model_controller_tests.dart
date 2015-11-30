import 'package:monadart/monadart.dart';
import 'dart:async';
import 'package:test/test.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

main() async {

  setUp(() async {
    var server = await
    HttpServer.bind(InternetAddress.ANY_IP_V4, 8080);
    var router = new Router();
    router.route("/users/[:id]").then(
      new RequestHandlerGenerator<TestModelController>(arguments: [null]));

    server.listen((req) async {
      var resReq = new ResourceRequest(req);
      router.deliver(resReq);
    });
  });


    test("All", () async {
      var response = await http.get("http://localhost:8080/users");
      expect(response.statusCode, 200);

      response = await http.get("http://localhost:8080/users/1");
      expect(response.statusCode, 200);

      response = await http.delete("http://localhost:8080/users/1");
      expect(response.statusCode, 200);

      response = await http.put("http://localhost:8080/users/1", headers: {
        "Content-Type" : "application/json;charset=utf-8"
      },
        body: JSON.encode({"name" : "joe"})
      );
      expect(response.statusCode, 200);

      response = await http.post("http://localhost:8080/users", headers: {
        "Content-Type" : "application/json;charset=utf-8"
      },
        body: JSON.encode({"name" : "joe"})
      );
      expect(response.statusCode, 200);
    });

}

class TestModelController extends ModelController<TestModel> {
  TestModelController(QueryAdapter adapter) : super(adapter);

  @httpGet
  Future<Response> getAll()
  async {
    int statusCode = 200;
    if (requestModel != null) {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }
    if (query.predicateObject != null) {
      statusCode = 400;
    }
    if (query.valueObject != null) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpGet
  Future<Response> getOne(int id)
  async {
    int statusCode = 200;
    if (requestModel != null) {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }
    if (query.predicateObject == null) {
      statusCode = 400;
    }
    if (query.predicateObject.id != id) {
      statusCode = 400;
    }
    if (query.valueObject != null) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpPut
  Future<Response> putOne(int id)
  async {
    int statusCode = 200;
    if (requestModel == null) {
      statusCode = 400;
    }
    if (requestModel.name != "joe") {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }

    if (query.predicateObject == null) {
      statusCode = 400;
    }
    if (query.predicateObject.id != id) {
      statusCode = 400;
    }
    if (query.valueObject == null) {
      statusCode = 400;
    }

    if (query.valueObject.name != "joe") {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpDelete
  Future<Response> deleteOne(int id)
  async {
    int statusCode = 200;
    if (requestModel != null) {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }
    if (query.predicateObject == null) {
      statusCode = 400;
    }
    if (query.predicateObject.id != id) {
      statusCode = 400;
    }
    if (query.valueObject != null) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);

  }

  @httpPost
  Future<Response> create()
  async {
    int statusCode = 200;
    if (requestModel == null) {
      statusCode = 400;
    }
    if (requestModel.name != "joe") {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }

    if (query.predicateObject != null) {
      statusCode = 400;
    }

    if (query.valueObject == null) {
      statusCode = 400;
    }
    if (query.valueObject.name != "joe") {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpPost
  Future<Response> crash(int id) async {
    return new Response.ok("");
  }
}

@proxy
@ModelBacking(TestModelBacking)
class TestModel extends Object
  with Model
  implements TestModelBacking {
  noSuchMethod(inv) => super.noSuchMethod(inv);
}

class TestModelBacking {
  @Attributes(primaryKey: true)
  int id;

  String name;
  String email;
}