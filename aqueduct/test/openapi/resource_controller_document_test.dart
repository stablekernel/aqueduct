import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:test/test.dart';

void main() {
  Map<String, APIOperation> collectionOperations;
  Map<String, APIOperation> idOperations;
  APIOperation serializeCheckOperation;
  Map<String, APIOperation> subclassOperations;
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
    final bSubclass = BSubclass();
    bSubclass.restore(bSubclass.recycledState);
    bSubclass.didAddToChannel();
    bSubclass.documentComponents(context);

    collectionOperations = ac.documentOperations(context, "/", APIPath());
    idOperations = ac.documentOperations(
        context, "/", APIPath(parameters: [APIParameter.path("id")]));

    serializeCheckOperation = bc.documentOperations(context, "/a", APIPath())["post"];

    subclassOperations = bSubclass.documentOperations(context, "/subclass", APIPath());

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

      expect(op.parameterNamed("requiredHeaderProperty").schema.type,
          APIType.string);
      expect(op.parameterNamed("requiredHeaderProperty").isRequired, true);
      expect(op.parameterNamed("requiredHeaderProperty").location,
          APIParameterLocation.header);
    }
  });

  test(
      "Each operation is accounted for and documented if documentation comment exists",
      () {
    expect(collectionOperations, {"get": isNotNull, "post": isNotNull});
    expect(idOperations, {"get": isNotNull, "put": isNotNull});

    expect(collectionOperations["get"].id, "getAllAs");

    expect(collectionOperations["post"].id, "createA");

    expect(idOperations["get"].id, "getOneA");

    expect(idOperations["put"].id, "undocumented");
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

  test("Inherited operation methods are available in document", () {
    expect(subclassOperations.length, 2);
    expect(subclassOperations["get"].id, "get");
    expect(subclassOperations["post"].id, "post");
  });
}

class A extends ResourceController {
  @Bind.query("optionalQueryProperty")
  int propQ;

  @requiredBinding
  @Bind.header("requiredHeaderProperty")
  String propH;

  @Operation.get()
  Future<Response> getAllAs(

      @Bind.header("requiredHeaderParameter") DateTime paramH,
      {

      @Bind.query("optionalQueryParameter") String paramQ}) async {
    return Response.ok(null);
  }

  @Operation.get('id')
  Future<Response> getOneA(
      {@Bind.query("optionalQueryParameter") String paramQ}) async {
    return Response.ok(null);
  }

  @Operation.post()
  Future<Response> createA(
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

class BSubclass extends B {
  @Operation.get()
  Future<Response> get() async {
    return Response.ok(null);
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