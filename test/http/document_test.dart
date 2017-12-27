import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

/*
These tests handle the core behavior of document generation. Types that extend doc-gen behavior, e.g. AuthServer, RESTController, etc.
will have their own tests. It does test Router, though.
 */

void main() {
  group(("Default channel"), () {
    APIDocument doc;

    setUpAll(() async {
      doc = await Application.document(DefaultChannel, new ApplicationOptions(),
          {"name": "test-title", "description": "test-description", "version": "1.2.3"});
    });

    test("Document has appropriate metadata", () {
      expect(doc.version, "3.0.0");
      expect(doc.info.version, "1.2.3");
      expect(doc.info.title, "test-title");
      expect(doc.info.description, "test-description");
    });
  });

  group("Happy path", () {
    APIDocument doc;

    setUpAll(() async {
      doc = await Application.document(DefaultChannel, new ApplicationOptions(),
          {"name": "test-title", "description": "test-description", "version": "1.2.3"});
    });

    test("Document has appropriate metadata", () {
      expect(doc.version, "3.0.0");
      expect(doc.info.version, "1.2.3");
      expect(doc.info.title, "test-title");
      expect(doc.info.description, "test-description");
    });

    group("Paths", () {
      test("All paths in Router accounted for", () {
        expect(doc.paths.length, 4);
        expect(doc.paths.containsKey("/path"), true);
        expect(doc.paths.containsKey("/path/{id}"), true);
        expect(doc.paths.containsKey("/constant"), true);
        expect(doc.paths.containsKey("/dynamic"), true);
      });
    });

    group("Components", () {});
  });
}

class DefaultChannel extends ApplicationChannel {
  ComponentA a;

  ComponentB get b => _b;
  ComponentB _b;
  String notDocumentable;

  Controller documentableButNotAutomaticComponent() {
    return new Controller();
  }

  @override
  Future prepare() async {
    a = new ComponentA();
    _b = new ComponentB();
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/path/[:id]").pipe(new Middleware()).generate(() => new Endpoint());

    router.route("/constant").pipe(new UndocumentedMiddleware()).pipe(new Middleware()).generate(() => new Endpoint());

    router.route("/dynamic").listen((Request req) async {
      return new Response.ok("");
    });

    return router;
  }
}

class UndocumentedMiddleware extends Controller {}

class Middleware extends Controller {
  @override
  void documentComponents(APIComponentRegistry components) {
    components.parameters
        .register("x-api-key", new APIParameter.header("x-api-key", schema: new APISchemaObject.string()));
  }

  @override
  Map<String, APIOperation> documentOperations(APIComponentRegistry components, APIPath path) {
    final ops = super.documentOperations(components, path);

    ops.values.forEach((op) {
      op.parameters.add(new APIParameter.header("x-api-key", schema: new APISchemaObject.string()));
    });

    return ops;
  }
}

class Endpoint extends Controller {
  @override
  Map<String, APIOperation> documentOperations(APIComponentRegistry registry, APIPath path) {
    if (path.parameters.length >= 1) {
      return {
        "get": new APIOperation()
          ..responses = {
            "200": new APIResponse()..description = "get/1-200",
            "400": new APIResponse()..description = "get/1-400",
          },
        "put": new APIOperation()..responses = {"200": new APIResponse()..description = "put/1-200"},
      };
    }

    return {
      "get": new APIOperation()
        ..parameters = [registry.parameters["x-api-key"]]
        ..responses = {"200": new APIResponse()..description = "get/0-200"},
      "post": new APIOperation()
        ..requestBody = (new APIRequestBody()
          ..content = {"application/json": new APIMediaType(schema: registry.schema["someObject"])})
        ..responses = {"200": new APIResponse()..description = "post/0-200"}
    };
  }
}

class ComponentA extends Object with APIDocumentable {
  @override
  void documentComponents(APIComponentRegistry components) {
    final schemaObject = new APISchemaObject.object({
      "name": new APISchemaObject.string(),
      "refByType": components.schema.getObjectWithType(ReferencableSchemaObject),
      "refByName": components.schema["named-component"]
    });

    components.schema.register("someObject", schemaObject);
    components.schema.register("named-component", new APISchemaObject.string());
  }
}

class ComponentB extends APIDocumentable {
  @override
  void documentComponents(APIComponentRegistry components) {
    components.schema.register("ref-component", new APISchemaObject.object({"key": new APISchemaObject.string()}),
        representation: ReferencableSchemaObject);
  }
}

class ReferencableSchemaObject {}
