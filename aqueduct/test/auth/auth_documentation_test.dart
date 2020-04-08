import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main()
{
  group("AuthController", ()
  {
    Map<String, APIOperation> operations;
    setUpAll(()
    async {
      final context = APIDocumentContext(APIDocument()
        ..info = APIInfo("title", "1.0.0")
        ..paths = {}
        ..components = APIComponents());
      final authServer = AuthServer(InMemoryAuthStorage());
      authServer.documentComponents(context);
      AuthController ac = AuthController(authServer);
      ac.restore(ac.recycledState);
      ac.didAddToChannel();
      operations = ac.documentOperations(context, "/", APIPath());
      await context.finalize();
    });

    test("Has POST operation", ()
    {
      expect(operations, {"post": isNotNull});
    });

    test(
      "POST has body parameteters for username, password, refresh_token, scope, code, grant_type",
        ()
      {
        final op = operations["post"];
        expect(op.parameters.length, 0);
        expect(op.requestBody.isRequired, true);

        final content =
        op.requestBody.content["application/x-www-form-urlencoded"];
        expect(content, isNotNull);

        expect(content.schema.type, APIType.object);
        expect(content.schema.properties.length, 6);
        expect(content.schema.properties["refresh_token"].type, APIType.string);
        expect(content.schema.properties["scope"].type, APIType.string);
        expect(content.schema.properties["code"].type, APIType.string);
        expect(content.schema.properties["grant_type"].type, APIType.string);
        expect(content.schema.properties["username"].type, APIType.string);
        expect(content.schema.properties["password"].type, APIType.string);

        expect(content.schema.properties["password"].format, "password");
        expect(content.schema.required, ["grant_type"]);
      });

    test("POST requires client authorization", ()
    {
      expect(operations["post"].security.length, 1);
      expect(operations["post"].security.first.requirements,
        {"oauth2-client-authentication": []});
    });

    test("Responses", ()
    {
      expect(operations["post"].responses.length, 2);

      expect(
        operations["post"]
          .responses["200"]
          .content["application/json"]
          .schema
          .type,
        APIType.object);
      expect(
        operations["post"]
          .responses["200"]
          .content["application/json"]
          .schema
          .properties["access_token"]
          .type,
        APIType.string);
      expect(
        operations["post"]
          .responses["200"]
          .content["application/json"]
          .schema
          .properties["refresh_token"]
          .type,
        APIType.string);
      expect(
        operations["post"]
          .responses["200"]
          .content["application/json"]
          .schema
          .properties["expires_in"]
          .type,
        APIType.integer);
      expect(
        operations["post"]
          .responses["200"]
          .content["application/json"]
          .schema
          .properties["token_type"]
          .type,
        APIType.string);
      expect(
        operations["post"]
          .responses["200"]
          .content["application/json"]
          .schema
          .properties["scope"]
          .type,
        APIType.string);

      expect(
        operations["post"]
          .responses["400"]
          .content["application/json"]
          .schema
          .type,
        APIType.object);
      expect(
        operations["post"]
          .responses["400"]
          .content["application/json"]
          .schema
          .properties["error"]
          .type,
        APIType.string);
    });
  });

  group("Auth Redirect", () {
    Map<String, APIOperation> operations;
    setUpAll(() async {
      final context = APIDocumentContext(APIDocument()
        ..info = APIInfo("title", "1.0.0")
        ..paths = {}
        ..components = APIComponents());
      AuthRedirectController ac =
      AuthRedirectController(AuthServer(InMemoryAuthStorage()));
      ac.restore(ac.recycledState);
      ac.didAddToChannel();
      operations = ac.documentOperations(context, "/", APIPath());
      await context.finalize();
    });

    test("Has GET and POST operation", () {
      expect(operations, {"get": isNotNull, "post": isNotNull});
    });

    test("GET serves HTML string for only response", () {
      expect(operations["get"].responses.length, 1);
      expect(
        operations["get"].responses["200"].content["text/html"].schema.type,
        APIType.string);
    });

    test("GET has parameters for client_id, state, response_type and scope",
        () {
        final op = operations["get"];
        expect(op.parameters.length, 4);
        expect(
          op.parameters.every((p) => p.location == APIParameterLocation.query),
          true);
        expect(op.parameterNamed("client_id").schema.type, APIType.string);
        expect(op.parameterNamed("scope").schema.type, APIType.string);
        expect(op.parameterNamed("response_type").schema.type, APIType.string);
        expect(op.parameterNamed("state").schema.type, APIType.string);

        expect(op.parameterNamed("client_id").isRequired, true);
        expect(op.parameterNamed("scope").isRequired, false);
        expect(op.parameterNamed("response_type").isRequired, true);
        expect(op.parameterNamed("state").isRequired, true);
      });

    test(
      "POST has body parameteters for client_id, state, response_type, scope, username and password",
        () {
        final op = operations["post"];
        expect(op.parameters.length, 0);
        expect(op.requestBody.isRequired, true);

        final content =
        op.requestBody.content["application/x-www-form-urlencoded"];
        expect(content, isNotNull);

        expect(content.schema.type, APIType.object);
        expect(content.schema.properties.length, 6);
        expect(content.schema.properties["client_id"].type, APIType.string);
        expect(content.schema.properties["scope"].type, APIType.string);
        expect(content.schema.properties["state"].type, APIType.string);
        expect(content.schema.properties["response_type"].type, APIType.string);
        expect(content.schema.properties["username"].type, APIType.string);
        expect(content.schema.properties["password"].type, APIType.string);
        expect(content.schema.properties["password"].format, "password");
        expect(content.schema.required,
          ["client_id", "state", "response_type", "username", "password"]);
      });

    test("POST response can be redirect or bad request", () {
      expect(operations["post"].responses, {
        "${HttpStatus.movedTemporarily}": isNotNull,
        "${HttpStatus.badRequest}": isNotNull,
      });
    });

    test("POST response is a redirect", () {
      final redirectResponse =
      operations["post"].responses["${HttpStatus.movedTemporarily}"];
      expect(redirectResponse.content, isNull);
      expect(redirectResponse.headers["Location"].schema.type, APIType.string);
      expect(redirectResponse.headers["Location"].schema.format, "uri");
    });
  });
}