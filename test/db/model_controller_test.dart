import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../helpers.dart';

main() {
  ModelContext context = null;
  HttpServer server = null;

  setUpAll(() async {
    context = await contextWithModels([TestModel]);
    ModelContext.defaultContext = context;

    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8080);
    var router = new Router();
    router.route("/users/[:id]").next(() => new TestModelController());
    router.finalize();

    server.listen((req) async {
      router.deliver(new Request(req));
    });
  });

  tearDownAll(() async {
    await server?.close(force: true);
  });

  test("Request with no path parameters OK", () async {
    var response = await http.get("http://localhost:8080/users");
    expect(response.statusCode, 200);
  });

  test("Request with path parameter of type needing parse OK", () async {
    var response = await http.get("http://localhost:8080/users/1");
    expect(response.statusCode, 200);
  });

  test("Request with path parameter of wrong type returns 404", () async {
    var response = await http.get("http://localhost:8080/users/foo");
    expect(response.statusCode, 404);
  });

  test("Request with path parameter and body", () async {
    var response = await http.put("http://localhost:8080/users/2", headers: {
      "Content-Type" : "application/json;charset=utf-8"
    }, body: JSON.encode({"name" : "joe"}));
    expect(response.statusCode, 200);
  });

  test("Request without path parameter and body", () async {
    var response = await http.post("http://localhost:8080/users", headers: {
      "Content-Type" : "application/json;charset=utf-8"
    }, body: JSON.encode({"name" : "joe"}));
    expect(response.statusCode, 200);
  });

}

class TestModelController extends ModelController<TestModel> {
  TestModelController() : super();

  @httpGet getAll() async {
    int statusCode = 200;

    if (query == null) {
      statusCode = 400;
    }

    if (query.values.backingMap.length != 0) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpGet getOne(int id) async {
    int statusCode = 200;

    if (query == null) {
      statusCode = 400;
    }

    var comparisonMatcher = query.matchOn["id"];
    if (comparisonMatcher.operator != MatcherOperator.equalTo || comparisonMatcher.value != id) {
      statusCode = 400;
    }

    if (query.values.backingMap.length != 0) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpPut putOne(int id) async {
    int statusCode = 200;

    if (query.values == null) {
      statusCode = 400;
    }
    if (query.values.name != "joe") {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }

    var comparisonMatcher = query.matchOn["id"];
    if (comparisonMatcher.operator != MatcherOperator.equalTo || comparisonMatcher.value != id) {
      statusCode = 400;
    }

    if (query.values == null) {
      statusCode = 400;
    }

    if (query.values.name != "joe") {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpPost create() async {
    int statusCode = 200;
    if (query.values == null) {
      statusCode = 400;
    }
    if (query.values.name != "joe") {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @httpPost crash(int id) async {
    return new Response.ok("");
  }
}

class TestModel extends Model<_TestModel> implements _TestModel {}
class _TestModel {
  @ColumnAttributes(primaryKey: true)
  int id;

  String name;
  String email;
}