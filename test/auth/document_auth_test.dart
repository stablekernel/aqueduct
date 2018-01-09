import 'dart:convert';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../helpers.dart';

void main() {
  group("Standard tests", () {
    APIDocument doc;

    setUpAll(() async {
      doc = await Application.document(TestChannel, new ApplicationOptions(), {"name": "Test", "version": "1.0"});
      print("${JSON.encode(doc.asMap())}");
    });

    test("AuthServer documents components", () {
      final schemes = doc.components.securitySchemes;

      expect(schemes.length, 2);
      expect(schemes["oauth2"].type, APISecuritySchemeType.oauth2);
      expect(schemes["oauth2-client-authentication"].type, APISecuritySchemeType.http);
      expect(schemes["oauth2-client-authentication"].scheme, "basic");
    });

    test("Basic Authorizer adds oauth2 client authentication to operations for all paths", () {
      final noVarPath = doc.paths["/basic"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {"oauth2-client-authentication": []});
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {"oauth2-client-authentication": []});

      final varPath = doc.paths["/basic/{id}"];
      expect(varPath.operations.length, 1);
      expect(varPath.operations["get"].security.length, 1);
      expect(varPath.operations["get"].security.first.requirements, {"oauth2-client-authentication": []});
    });

    test("No scope bearer authorizer adds oauth2 authentication to operations", () {
      final noVarPath = doc.paths["/bearer-no-scope"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {"oauth2": []});
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {"oauth2": []});
    });

    test("Scoped bearer authorizer adds oauth2 authentication to operations w/ scope", () {
      final noVarPath = doc.paths["/bearer-scope"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {
        "oauth2": ["scope"]
      });
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {
        "oauth2": ["scope"]
      });
    });
  });

  group("Controller Registration", () {});
}

class TestChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = new AuthServer(new InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/basic/[:id]").link(() => new Authorizer.basic(authServer)).link(() => new DocumentedController());
    router
        .route("/bearer-no-scope")
        .link(() => new Authorizer.bearer(authServer))
        .link(() => new DocumentedController());
    router
        .route("/bearer-scope")
        .link(() => new Authorizer.bearer(authServer, scopes: ["scope"]))
        .link(() => new DocumentedController());
    return router;
  }
}

class DocumentedController extends Controller {
  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext components, APIPath path) {
    if (path.containsPathParameters([])) {
      return {
        "get": new APIOperation()
          ..id = "get/0"
          ..responses = {
            "200": new APIResponse()
              ..description = "get/0-200"
              ..content = {"application/json": new APIMediaType(schema: new APISchemaObject.string())}
          },
        "post": new APIOperation()
          ..id = "post/0"
          ..responses = {
            "200": new APIResponse()
              ..description = "post/0-200"
              ..content = {"application/json": new APIMediaType(schema: new APISchemaObject.string())}
          },
      };
    }

    return {
      "get": new APIOperation()
        ..id = "get/1"
        ..responses = {
          "200": new APIResponse()
            ..description = "get/1-200"
            ..content = {"application/json": new APIMediaType(schema: new APISchemaObject.string())}
        }
    };
  }
}
