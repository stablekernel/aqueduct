import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';
import 'package:aqueduct/src/utilities/documented_element_analyzer_bridge.dart';
import 'package:test/test.dart';

void main() {
  DocumentedElement.provider = AnalyzerDocumentedElementProvider();
  Map<String, APIOperation> collectionOperations;
  Map<String, APIOperation> idOperations;
  APIOperation serializeCheckOperation;
  APIDocumentContext context;

  setUpAll(() async {
    context = APIDocumentContext(APIDocument()
      ..info = APIInfo("x", "1.0.0")
      ..paths = {}
      ..components = APIComponents());

    final ac = A();
    ac.restore(ac.recycledState);
    ac.didAddToChannel();
    ac.documentComponents(context);
    final bc = B();
    bc.restore(bc.recycledState);
    bc.didAddToChannel();
    bc.documentComponents(context);

    collectionOperations = ac.documentOperations(context, "/", APIPath());
    idOperations = ac.documentOperations(
        context, "/", APIPath(parameters: [APIParameter.path("id")]));

    serializeCheckOperation = bc.documentOperations(context, "/a", APIPath())["post"];

    await context.finalize();
  });

  test("Bound properties are part of every operation and carry documentation",
      () {
    for (var op in [collectionOperations.values, idOperations.values]
        .expand((i) => i)) {
      expect(op.parameterNamed("optionalQueryProperty").schema.type,
          APIType.integer);
      expect(op.parameterNamed("optionalQueryProperty").isRequired, false);
      expect(op.parameterNamed("optionalQueryProperty").location,
          APIParameterLocation.query);
      expect(op.parameterNamed("optionalQueryProperty").description,
          contains("1"));

      expect(op.parameterNamed("requiredHeaderProperty").schema.type,
          APIType.string);
      expect(op.parameterNamed("requiredHeaderProperty").isRequired, true);
      expect(op.parameterNamed("requiredHeaderProperty").location,
          APIParameterLocation.header);
      expect(op.parameterNamed("requiredHeaderProperty").description,
          contains("2"));
      expect(op.parameterNamed("requiredHeaderProperty").description,
          contains("3"));
    }
  });

  test(
      "Each operation is accounted for and documented if documentation comment exists",
      () {
    expect(collectionOperations, {"get": isNotNull, "post": isNotNull});
    expect(idOperations, {"get": isNotNull, "put": isNotNull});

    expect(collectionOperations["get"].id, "getAllAs");
    expect(collectionOperations["get"].summary, contains("3"));
    expect(collectionOperations["get"].description, contains("1"));

    expect(collectionOperations["post"].id, "createA");
    expect(collectionOperations["post"].summary, contains("5"));
    expect(collectionOperations["post"].description, contains("3"));

    expect(idOperations["get"].id, "getOneA");
    expect(idOperations["get"].summary, contains("4"));
    expect(idOperations["get"].description, contains("2"));

    expect(idOperations["put"].id, "undocumented");
    expect(idOperations["put"].summary, isEmpty);
    expect(idOperations["put"].description, isEmpty);
  });

  test("Method parameters are configured appropriately", () {
    expect(collectionOperations["get"].parameters.length, 4);

    expect(
        collectionOperations["get"]
            .parameterNamed("requiredHeaderParameter")
            .location,
        APIParameterLocation.header);
    expect(
        collectionOperations["get"]
            .parameterNamed("requiredHeaderParameter")
            .isRequired,
        true);
    expect(
        collectionOperations["get"]
            .parameterNamed("requiredHeaderParameter")
            .schema
            .type,
        APIType.string);
    expect(
        collectionOperations["get"]
            .parameterNamed("requiredHeaderParameter")
            .schema
            .format,
        "date-time");
    expect(
        collectionOperations["get"]
            .parameterNamed("requiredHeaderParameter")
            .description,
        contains("1"));

    expect(
        collectionOperations["get"]
            .parameterNamed("optionalQueryParameter")
            .location,
        APIParameterLocation.query);
    expect(
        collectionOperations["get"]
            .parameterNamed("optionalQueryParameter")
            .isRequired,
        false);
    expect(
        collectionOperations["get"]
            .parameterNamed("optionalQueryParameter")
            .schema
            .type,
        APIType.string);
    expect(
        collectionOperations["get"]
            .parameterNamed("optionalQueryParameter")
            .schema
            .format,
        isNull);
    expect(
        collectionOperations["get"]
            .parameterNamed("optionalQueryParameter")
            .description,
        contains("2"));

    expect(collectionOperations["post"].parameters.length, 3);

    expect(
        collectionOperations["post"]
            .parameterNamed("requiredQueryParameter")
            .location,
        APIParameterLocation.query);
    expect(
        collectionOperations["post"]
            .parameterNamed("requiredQueryParameter")
            .isRequired,
        true);
    expect(
        collectionOperations["post"]
            .parameterNamed("requiredQueryParameter")
            .schema
            .type,
        APIType.integer);
    expect(
        collectionOperations["post"]
            .parameterNamed("requiredQueryParameter")
            .schema
            .format,
        isNull);
    expect(
        collectionOperations["post"]
            .parameterNamed("requiredQueryParameter")
            .description,
        isNull);
  });

  test(
      "If request body is bound, shows up in documentation for operation with valid ref",
      () {
    expect(context.schema.hasRegisteredType(AModel), true);
    expect(
        collectionOperations["post"]
            .requestBody
            .content["application/json"]
            .schema
            .referenceURI
            .path,
        "/components/schemas/AModel");
  });

  test("If Serializable overrides automatic generation, it is not automatically generated and must be registered", () {
    expect(serializeCheckOperation.requestBody.content["application/json"].schema.referenceURI.path, "/components/schemas/Override");
    expect(context.document.components.schemas["OverrideGeneration"], isNull);
    expect(context.document.components.schemas["Override"].properties["k"], isNotNull);
  });
}

class A extends ResourceController {
  /// 1
  @Bind.query("optionalQueryProperty")
  int propQ;

  /// 2
  ///
  /// 3
  @requiredBinding
  @Bind.header("requiredHeaderProperty")
  String propH;

  /// 3
  ///
  /// 1
  @Operation.get()
  Future<Response> getAllAs(

      /// 1
      @Bind.header("requiredHeaderParameter") DateTime paramH,
      {

      /// 2
      @Bind.query("optionalQueryParameter") String paramQ}) async {
    return Response.ok(null);
  }

  /// 4
  ///
  /// 2
  @Operation.get('id')
  Future<Response> getOneA(
      {@Bind.query("optionalQueryParameter") String paramQ}) async {
    return Response.ok(null);
  }

  /// 5
  ///
  /// 3
  @Operation.post()
  Future<Response> createA(

      /// 1
      ///
      /// 2
      @Bind.body() AModel model,
      @Bind.query("requiredQueryParameter") int q) async {
    return Response.ok(null);
  }

  @Operation.put('id')
  Future<Response> undocumented(
      @Bind.query("requiredQueryParameter") int q, @Bind.body() AModel body,
      {@Bind.header("optionalHeaderParameter") String h}) async {
    return Response.ok(null);
  }
}

class AModel extends Serializable {
  double key;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return {};
  }
}

class B extends ResourceController {
  @Operation.post()
  Future<Response> post(@Bind.body() OverrideGeneration o) async {
    return Response.ok(null);
  }

  @override
  void documentComponents(APIDocumentContext context) {
    super.documentComponents(context);
    context.schema.register("Override", APISchemaObject.object({"k": APISchemaObject.boolean()}), representation: OverrideGeneration);
  }
}

class OverrideGeneration extends Serializable {
  int id;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return {};
  }

  static bool get shouldAutomaticallyDocument {
    return false;
  }
}