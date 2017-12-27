import 'dart:convert';

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

    test("Has required properties", () {
      expect(doc.asMap(), isNotNull);
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

      test("Paths with path parameter are found in path-level parameters", () {
        expect(doc.paths["/path"].parameters.length, 0);
        expect(doc.paths["/constant"].parameters.length, 0);
        expect(doc.paths["/dynamic"].parameters.length, 0);

        expect(doc.paths["/path/{id}"].parameters.length, 1);
        expect(doc.paths["/path/{id}"].parameters.first.location, APIParameterLocation.path);
        expect(doc.paths["/path/{id}"].parameters.first.schema.type, APIType.string);
        expect(doc.paths["/path/{id}"].parameters.first.name, "id");
      });

      test("Paths have all expected operations", () {
        expect(doc.paths["/dynamic"].operations, {});

        final getConstant = doc.paths["/constant"].operations["get"];
        final postConstant = doc.paths["/constant"].operations["post"];
        expect(getConstant.responses["200"].description, "get/0-200");
        expect(postConstant.responses["200"].description, "post/0-200");

        final getPath0 = doc.paths["/path"].operations["get"];
        final postPath0 = doc.paths["/path"].operations["post"];
        expect(getPath0.responses["200"].description, "get/0-200");
        expect(postPath0.responses["200"].description, "post/0-200");

        final getPath1 = doc.paths["/path/{id}"].operations["get"];
        final putPath1 = doc.paths["/path/{id}"].operations["put"];
        expect(getPath1.responses["200"].description, "get/1-200");
        expect(getPath1.responses["400"].description, "get/1-400");
        expect(getPath1.parameters.length, 2);
        expect(putPath1.responses["200"].description, "put/1-200");
      });

      test("Middleware can provide additional parameters to operation", () {
        final opsWithMiddleware = [
          doc.paths["/path/{id}"].operations.values,
          doc.paths["/path"].operations.values,
          doc.paths["/constant"].operations.values,
        ].expand((i) => i).toList();

        opsWithMiddleware.forEach((op) {
          final middlewareParam =
              op.parameters.where((p) => p.referenceURI == "#/components/parameters/x-api-key").toList();
          expect(middlewareParam.length, 1);

          expect(doc.components.resolve(middlewareParam.first).schema.type, APIType.string);
        });
      });
    });

    group("Components", () {
      test("Component created by a controller is automatically emitted", () {
        expect(doc.components.parameters["x-api-key"], isNotNull);
      });

      test("Componentable property in channel automatically emit components", () {
        expect(doc.components.schemas["someObject"], isNotNull);
        expect(doc.components.schemas["named-component"], isNotNull);
        expect(doc.components.schemas["ref-component"], isNotNull);
      });

      test("Componentable getter in channel does not automatically emit components", () {
        expect(doc.components.schemas["won't-show-up"], isNull);
      });

      test("Regular instance method in channel does not automatically emit component", () {
        expect(doc.components.schemas["won't-show-up"], isNull);
      });

      test("Can resolve component by type", () {
        final ref = doc.components.schemas["someObject"].properties["refByType"];
        expect(ref.referenceURI, "#/components/schemas/ref-component");

        final resolved = doc.components.resolve(ref);
        expect(resolved.type, APIType.object);
        expect(resolved.properties["key"].type, APIType.string);
      });
    });
  });
}

class DefaultChannel extends ApplicationChannel {
  ComponentA a;

  ComponentB b = new ComponentB();

  UnaccountedForControllerWithComponents get documentableButNotAutomaticGetter =>
      new UnaccountedForControllerWithComponents();

  String notDocumentable;

  Controller documentableButNotAutomaticMethod() {
    return new UnaccountedForControllerWithComponents();
  }

  @override
  Future prepare() async {
    a = new ComponentA();
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
    documentableChild?.documentComponents(components);
  }

  @override
  Map<String, APIOperation> documentOperations(APIComponentRegistry components, APIPath path) {
    final ops = super.documentOperations(components, path);

    ops.values.forEach((op) {
      op.parameters ??= [];
      op.parameters.add(components.parameters["x-api-key"]);
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
          ..parameters = [new APIParameter.header("x-op", schema: new APISchemaObject.integer())]
          ..responses = {
            "200": new APIResponse()..description = "get/1-200",
            "400": new APIResponse()..description = "get/1-400",
          },
        "put": new APIOperation()..responses = {"200": new APIResponse()..description = "put/1-200"},
      };
    }

    return {
      "get": new APIOperation()..responses = {"200": new APIResponse()..description = "get/0-200"},
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

class UnaccountedForControllerWithComponents extends Controller {
  @override
  void documentComponents(APIComponentRegistry components) {
    components.schema.register("won't-show-up", new APISchemaObject.object({"key": new APISchemaObject.string()}));
  }
}