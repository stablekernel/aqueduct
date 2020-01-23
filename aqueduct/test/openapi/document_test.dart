import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:runtime/runtime.dart';
import 'package:test/test.dart';

/*
These tests handle the core behavior of document generation. Types that extend doc-gen behavior, e.g. AuthServer, ResourceController, etc.
will have their own tests. It does test Router, though.
 */

void main() {
  group("Default channel", () {
    APIDocument doc;
    DateTime controllerDocumented;
    DateTime controllerPrepared;
    DateTime appPrepared;

    setUpAll(() async {
      DefaultChannel.channelClosed = Completer();
      DefaultChannel.controllerDocumented = Completer();
      DefaultChannel.controllerPrepared = Completer();
      DefaultChannel.appPrepared = Completer();

      // ignore: unawaited_futures
      DefaultChannel.appPrepared.future
          .then((_) => appPrepared = DateTime.now());
      // ignore: unawaited_futures
      DefaultChannel.controllerPrepared.future
          .then((_) => controllerPrepared = DateTime.now());
      // ignore: unawaited_futures
      DefaultChannel.controllerDocumented.future
          .then((_) => controllerDocumented = DateTime.now());
      doc = await Application.document(DefaultChannel, ApplicationOptions(), {
        "name": "test-title",
        "description": "test-description",
        "version": "1.2.3"
      });
    });

    tearDownAll(() {
      DefaultChannel.channelClosed = null;
      DefaultChannel.controllerDocumented = null;
      DefaultChannel.controllerPrepared = null;
      DefaultChannel.appPrepared = null;
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

    test("Controllers are prepared prior to documenting", () async {
      expect(
          controllerPrepared.isBefore(controllerDocumented) ||
              controllerPrepared.isAtSameMomentAs(controllerDocumented),
          true);
    });

    test("Static init is ran prior to controller prep", () async {
      expect(appPrepared.isBefore(controllerPrepared), true);
    });

    test("Channel is closed after documenting", () async {
      expect(DefaultChannel.channelClosed.future, completes);
    });
  });

  group("Defer behavior", () {
    APIDocumentContext ctx;

    setUp(() async {
      ctx = APIDocumentContext(APIDocument()
        ..info = APIInfo("test", "1.0.0")
        ..paths = {}
        ..components = APIComponents());
    });

    test("Can defer async functions", () async {
      final completer = Completer();

      ctx.defer(() {
        return Future(completer.complete);
      });

      await ctx.finalize();
      expect(completer.future, completes);
    });

    test("Can defer sync functions", () async {
      final completer = Completer();

      ctx.defer(completer.complete);

      await ctx.finalize();
      expect(completer.future, completes);
    });

    test("Deferred operations are executed in order, even when async",
        () async {
      final completer1 = Completer<DateTime>();
      final completer2 = Completer<DateTime>();
      final completer3 = Completer<DateTime>();

      ctx.defer(() {
        return Future(() => completer1.complete(DateTime.now()));
      });
      ctx.defer(() {
        completer2.complete(DateTime.now());
      });
      ctx.defer(() {
        return Future(() => completer3.complete(DateTime.now()));
      });
      await ctx.finalize();

      final f1 = await completer1.future;
      final f2 = await completer2.future;
      final f3 = await completer3.future;

      expect(f1.isBefore(f2) || f1.isAtSameMomentAs(f2), true);
      expect(f2.isBefore(f3) || f2.isAtSameMomentAs(f3), true);
    });

    test("Finalize throws error if contains unresolved type reference",
        () async {
      ctx.document.paths = {
        "/path": APIPath(operations: {
          "get": APIOperation(
              "id1", {"200": ctx.responses.getObjectWithType(String)})
        })
      };

      try {
        await ctx.finalize();
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.message, contains("Reference"));
        expect(e.message, contains("responses"));
        expect(e.message, contains("String"));
        expect(e.message, contains("does not exist"));
      }
    });

    test("Finalize throws error if contains unresolved uri reference",
        () async {
      ctx.document.components.responses["test"] = APIResponse("desc", content: {
        "application/json": APIMediaType(schema: ctx.schema.getObject("foo"))
      });

      try {
        await ctx.finalize();
        fail("unreachable");
      } on ArgumentError catch (e) {
        expect(e.message, contains("Reference"));
        expect(e.message, contains("'#/components/schemas/foo'"));
        expect(e.message, contains("does not exist"));
      }
    });

    test(
        "Deferred async/sync components can be used to register components after they have been referenced",
        () async {
      ctx.document.paths = {
        "/path": APIPath(operations: {
          "get": APIOperation(
              "id1", {"200": ctx.responses.getObjectWithType(String)})
        })
      };

      ctx.document.components.responses["test"] = APIResponse("desc", content: {
        "application/json": APIMediaType(schema: ctx.schema.getObject("foo"))
      });

      ctx.schema.register("foo", APISchemaObject.integer());
      ctx.defer(() {
        return Future(() => ctx.responses
            .register("whatever", APIResponse("foo"), representation: String));
      });

      await ctx.finalize();

      final map = ctx.document.asMap();
      expect(map["paths"]["/path"]["get"]["responses"]["200"][r"$ref"],
          "#/components/responses/whatever");
      expect(
          map["components"]["responses"]["test"]["content"]["application/json"]
              ["schema"][r"$ref"],
          "#/components/schemas/foo");
    });
  });

  group("Happy path", () {
    APIDocument doc;

    setUpAll(() async {
      doc = await Application.document(DefaultChannel, ApplicationOptions(), {
        "name": "test-title",
        "description": "test-description",
        "version": "1.2.3"
      });
    });

    test("Document has appropriate metadata", () {
      expect(doc.version, "3.0.0");
      expect(doc.info.version, "1.2.3");
      expect(doc.info.title, "test-title");
      expect(doc.info.description, "test-description");
    });

    group("Operations", () {
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
        expect(doc.paths["/path/{id}"].parameters.first.location,
            APIParameterLocation.path);
        expect(doc.paths["/path/{id}"].parameters.first.schema.type,
            APIType.string);
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
          final middlewareParam = op.parameters
              .where((p) =>
                  p.referenceURI?.path == "/components/parameters/x-api-key")
              .toList();
          expect(middlewareParam.length, 1);

          expect(doc.components.resolve(middlewareParam.first).schema.type,
              APIType.string);
        });
      });
    });

    group("Components", () {
      test("Component created by a controller is automatically emitted", () {
        expect(doc.components.parameters["x-api-key"], isNotNull);
      });

      test(
          "APIComponentDocumenter properties in channel are automatically emitted in components",
          () {
        expect(doc.components.schemas["someObject"], isNotNull);
        expect(doc.components.schemas["named-component"], isNotNull);
        expect(doc.components.schemas["ref-component"], isNotNull);
      });

      test(
          "Componentable getter/regular instance method in channel does not automatically emit components",
          () {
        expect(doc.components.schemas["won't-show-up"], isNull);
      });

      test("Can resolve component by type", () {
        final ref =
            doc.components.schemas["someObject"].properties["refByType"];
        expect(ref.referenceURI.path, "/components/schemas/ref-component");

        final resolved = doc.components.resolve(ref);
        expect(resolved.type, APIType.object);
        expect(resolved.properties["key"].type, APIType.string);
      });

      test("Add component more than once does not replace it", () {
        final doc = APIDocument()..components = APIComponents();
        final ctx = APIDocumentContext(doc);
        ctx.schema.register("a", APISchemaObject.string(format: "original"),
            representation: String);
        ctx.schema.register("a", APISchemaObject.string(format: "replacement"));

        expect(doc.components.schemas["a"].format, "original");
        expect(ctx.schema.getObjectWithType(String), isNotNull);
      });

      test("getObject and getObjectWithType always return new instance", () {
        final doc = APIDocument()..components = APIComponents();
        final ctx = APIDocumentContext(doc);

        final original = APISchemaObject.string(format: "original");

        // Use both variants, before and after registration
        final ref1 = ctx.schema.getObjectWithType(String);
        final ref2 = ctx.schema.getObject("a");

        ctx.schema.register("a", original, representation: String);
        final ref3 = ctx.schema.getObjectWithType(String);
        final ref4 = ctx.schema.getObject("a");

        expect(ref1.referenceURI.path, "/components/schemas/a");
        expect(ref2.referenceURI.path, "/components/schemas/a");
        expect(ref3.referenceURI.path, "/components/schemas/a");
        expect(ref4.referenceURI.path, "/components/schemas/a");

        expect(identical(ref1, original), false);
        expect(identical(ref1, ref2), false);
        expect(identical(ref3, original), false);
        expect(identical(ref3, ref4), false);
      });
    });
  });

  group("Schema object documentation", () {
    APIDocumentContext ctx;
    setUp(() {
      ctx = APIDocumentContext(APIDocument()
        ..info = APIInfo("x", "1.0.0")
        ..paths = {}
        ..components = APIComponents());
    });

    tearDown(() async {
      // Just in case the test didn't clear these
      await ctx.finalize();
    });

    test("Non-string key map throws error", () {
      final schema = (RuntimeContext.current.runtimes[InvalidMapKey] as SerializableRuntime).documentSchema(ctx);
      expect(schema.properties.isEmpty, true);
      expect(schema.additionalPropertyPolicy, equals(APISchemaAdditionalPropertyPolicy.freeForm));
      expect(schema.description, contains("Failed to"));
      expect(schema.description, contains("Map"));
    });

    test("List that contains non-serializble types throws", () {
      final schema = (RuntimeContext.current.runtimes[InvalidListValue] as SerializableRuntime).documentSchema(ctx);
      expect(schema.properties.isEmpty, true);
      expect(schema.additionalPropertyPolicy, equals(APISchemaAdditionalPropertyPolicy.freeForm));
      expect(schema.description, contains("Failed to"));
      expect(schema.description, contains("DefaultChannel"));
    });

    test("Map that contains values that aren't serializable throws", () {
      final schema = (RuntimeContext.current.runtimes[InvalidMapValue] as SerializableRuntime).documentSchema(ctx);
      expect(schema.properties.isEmpty, true);
      expect(schema.additionalPropertyPolicy, equals(APISchemaAdditionalPropertyPolicy.freeForm));
      expect(schema.description, contains("Failed to"));
      expect(schema.description, contains("DefaultChannel"));
    });

    test("Type documentation for complex types", () {
      final schema = (RuntimeContext.current.runtimes[ComplexTypes] as SerializableRuntime).documentSchema(ctx);

      expect(schema.properties["a"].type, APIType.object);
      expect(schema.properties["a"].additionalPropertySchema.type, APIType.integer);

      expect(schema.properties["b"].type, APIType.array);
      expect(schema.properties["b"].items.type, APIType.integer);

      expect(schema.properties["c"].type, APIType.array);
      expect(schema.properties["c"].items.type, APIType.object);
      expect(schema.properties["c"].items.additionalPropertySchema.type, APIType.string);

      expect(schema.properties["d"].type, APIType.array);
      expect(schema.properties["d"].items.type, APIType.object);
      expect(schema.properties["d"].items.properties["x"].type, APIType.integer);

      expect(schema.properties["e"].type, APIType.object);
      expect(schema.properties["e"].properties["x"].type, APIType.integer);

      expect(schema.properties["f"].type, APIType.object);
      expect(schema.properties["f"].additionalPropertySchema.type, APIType.array);
      expect(schema.properties["f"].additionalPropertySchema.items.type, APIType.string);

      expect(schema.properties["integer"].type, APIType.integer);
      expect(schema.properties["doublePrecision"].type, APIType.number);
      expect(schema.properties["string"].type, APIType.string);
      expect(schema.properties["boolean"].type, APIType.boolean);
      expect(schema.properties["dateTime"].type, APIType.string);
      expect(schema.properties["dateTime"].format, "date-time");
    });
  });
}

class ComplexTypes extends Serializable {
  /// title
  Map<String, int> a;

  /// title
  ///
  /// summary
  List<int> b;
  List<Map<String, String>> c;
  List<Serial> d;
  Serial e;
  Map<String, List<String>> f;

  String string;
  int integer;
  DateTime dateTime;
  double doublePrecision;
  bool boolean;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class InvalidMapKey extends Serializable {
  Map<int, String> x;
  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class InvalidListValue extends Serializable {
  List<DefaultChannel> y;
  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class InvalidMapValue extends Serializable {
  Map<String, DefaultChannel> z;
  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class Serial extends Serializable {
  int x;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class DefaultChannel extends ApplicationChannel {
  static Completer controllerPrepared;
  static Completer controllerDocumented;
  static Completer channelClosed;
  static Completer appPrepared;

  ComponentA a;

  ComponentB b = ComponentB();

  UnaccountedForControllerWithComponents
      get documentableButNotAutomaticGetter =>
          UnaccountedForControllerWithComponents();

  String notDocumentable;

  Controller documentableButNotAutomaticMethod() {
    return UnaccountedForControllerWithComponents();
  }

  static Future initializeApplication(ApplicationOptions options) async {
    appPrepared?.complete();
  }

  @override
  Future prepare() async {
    a = ComponentA();
  }

  @override
  Controller get entryPoint {
    final router = Router();

    router
        .route("/path/[:id]")
        .linkFunction((req) => req)
        .link(() => Middleware())
        .link(() => Endpoint(null, null));

    final middleware = Middleware();
    router
        .route("/constant")
        .link(() => UndocumentedMiddleware())
        .link(() => middleware)
        .link(() => Endpoint(controllerPrepared, controllerDocumented));

    router.route("/dynamic").linkFunction((Request req) async {
      return Response.ok("");
    });

    return router;
  }

  @override
  Future close() async {
    await super.close();
    channelClosed?.complete();
  }
}

class UndocumentedMiddleware extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return request;
  }
}

class Middleware extends Controller {
  @override
  void documentComponents(APIDocumentContext components) {
    components.parameters.register("x-api-key",
        APIParameter.header("x-api-key", schema: APISchemaObject.string()));
    nextController?.documentComponents(components);
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext components, String route, APIPath path) {
    final ops = super.documentOperations(components, route, path);

    ops.values.forEach((op) {
      op.parameters ??= [];
      op.parameters.add(components.parameters["x-api-key"]);
    });

    return ops;
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return request;
  }
}

class Endpoint extends Controller {
  Endpoint(this.prepared, this.documented);

  final Completer prepared;
  final Completer documented;

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext registry, String route, APIPath path) {
    documented?.complete();

    if (path.parameters.isNotEmpty) {
      return {
        "get": APIOperation("get1", {
          "200": APIResponse("get/1-200"),
          "400": APIResponse("get/1-400"),
        }, parameters: [
          APIParameter.header("x-op", schema: APISchemaObject.integer())
        ]),
        "put": APIOperation("put1", {"200": APIResponse("put/1-200")}),
      };
    }

    return {
      "get": APIOperation("get0", {"200": APIResponse("get/0-200")}),
      "post": APIOperation("post0", {"200": APIResponse("post/0-200")},
          requestBody: APIRequestBody({
            "application/json":
                APIMediaType(schema: registry.schema["someObject"])
          }))
    };
  }

  @override
  void didAddToChannel() {
    prepared?.complete();
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return Response.ok(null);
  }
}

class ComponentA implements APIComponentDocumenter {
  @override
  void documentComponents(APIDocumentContext components) {
    final schemaObject = APISchemaObject.object({
      "name": APISchemaObject.string(),
      "refByType":
          components.schema.getObjectWithType(ReferencableSchemaObject),
      "refByName": components.schema["named-component"]
    });

    components.schema.register("someObject", schemaObject);
    components.schema.register("named-component", APISchemaObject.string());
  }
}

class ComponentB extends APIComponentDocumenter {
  @override
  void documentComponents(APIDocumentContext components) {
    components.schema.register("ref-component",
        APISchemaObject.object({"key": APISchemaObject.string()}),
        representation: ReferencableSchemaObject);
  }
}

class ReferencableSchemaObject {}

class UnaccountedForControllerWithComponents extends Controller {
  @override
  void documentComponents(APIDocumentContext components) {
    components.schema.register("won't-show-up",
        APISchemaObject.object({"key": APISchemaObject.string()}));
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return Response.ok(null);
  }


}
