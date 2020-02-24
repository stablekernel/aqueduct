import 'dart:async';
import "dart:core";
import "dart:io";

import 'package:aqueduct/aqueduct.dart';
import 'package:http/http.dart' as http;
import "package:test/test.dart";

// These tests are based on the specification found at http://www.w3.org/TR/cors/.
void main() {
  Controller.letUncaughtExceptionsEscape = true;
  var app = Application<CORSChannel>();
  app.options.port = 8000;

  setUpAll(() async {
    await app.startOnCurrentIsolate();
  });

  tearDownAll(() async {
    await app?.stop();
  });

  group(
      "Normal/Simple Requests: If the origin header is not present, terminate this set of steps. (No CORS Headers.)",
      () {
    // This group ensures that if a controller has or doesn't have a policy, if it is not a CORS request,
    // no CORS headers/processing occurs.
    test("Controller with no policy returns correctly", () async {
      var resp = await http.get("http://localhost:8000/nopolicy");
      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Controller with permissive default policy returns correctly",
        () async {
      var resp = await http.get("http://localhost:8000/defaultpolicy");
      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Controller with restrict policy returns correctly", () async {
      var resp = await http.get("http://localhost:8000/restrictive");
      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Invalid resource 404s", () async {
      var resp = await http.get("http://localhost:8000/foobar");
      expect(resp.statusCode, 404);
      expectThatNoCORSProcessingOccurred(resp);
    });
  });

  group(
      "Normal/Simple Requests: If the value of the Origin header is not a case-sensitive match for any of the values in list of origins, do not add heads and terminate steps",
      () {
    // This group ensures that if the Origin is invalid for a resource, that CORS processing aborts.
    test("Valid endpoint returns correctly, mis-matched origin", () async {
      var resp = await http.get("http://localhost:8000/restrictive",
          headers: {"Origin": "not this"});
      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Valid endpoint, case match failure", () async {
      var resp = await http.get("http://localhost:8000/restrictive",
          headers: {"Origin": "http://Exclusive.com"});
      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Invalid resource gets CORS headers to expose 404 to calling client",
        () async {
      // In this case, there is no 'resource', so we add the origin so the calling client can see the 404. Not sure on this behavior.
      var resp = await http.get("http://localhost:8000/foobar",
          headers: {"Origin": "http://abc.com"});
      expect(resp.statusCode, 404);
      expect(resp.headers["access-control-allow-origin"], "http://abc.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], isNull);
      expect(resp.headers["access-control-allow-credentials"], isNull);
    });

    test(
        "Unauthorized resource with invalid origin does not attach CORS headers",
        () async {
      var resp = await http.get("http://localhost:8000/restrictive_auth",
          headers: {
            "Origin": "http://Exclusive.com",
            "Authorization": "Bearer noauth"
          });
      expect(resp.statusCode, 401);
      expectThatNoCORSProcessingOccurred(resp);
    });
  });

  group(
      "Normal/Simple Requests: If the resource supports credentials add a single Access-Control-Allow-Origin header...",
      () {
    // This group ensures that requests with a valid Origin attach that origin and that allow-credentials is added if correct.
    test(
        "Origin and credentials are returned if credentials are supported and origin is specific, origin must be non-*",
        () async {
      var resp = await http.get("http://localhost:8000/restrictive",
          headers: {"Origin": "http://exclusive.com"});
      expect(resp.statusCode, 200);
      expect(
          resp.headers["access-control-allow-origin"], "http://exclusive.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], "foobar, x-foo");
      expect(resp.headers["access-control-allow-credentials"], "true");
    });

    test(
        "Normal/Simple Requests: Origin and credentials are returned if credentials are supported and origin is catch-all, origin must be non-*",
        () async {
      var resp = await http.get("http://localhost:8000/defaultpolicy",
          headers: {"Origin": "http://foobar.com"});
      expect(resp.statusCode, 200);
      expect(resp.headers["access-control-allow-origin"], "http://foobar.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], isNull);
      expect(resp.headers["access-control-allow-credentials"], "true");
    });

    test(
        "Normal/Simple Requests: If credentials are not supported and origin is valid, only set origin",
        () async {
      var resp = await http.get("http://localhost:8000/restrictive_nocreds",
          headers: {"Origin": "http://exclusive.com"});
      expect(resp.statusCode, 200);
      expect(
          resp.headers["access-control-allow-origin"], "http://exclusive.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], "foobar");
      expect(resp.headers["access-control-allow-credentials"], isNull);
    });
  });

  group(
      "Normal/Simple Requests: If the list of exposed headers is not empty, add one or more Access-Control-Expose-Headers...",
      () {
    // This group ensures that headers are exposed correctly
    test("Empty exposed headers returns no header to indicate them", () async {
      var resp = await http.get("http://localhost:8000/defaultpolicy",
          headers: {"Origin": "http://foobar.com"});
      expect(resp.statusCode, 200);
      expect(resp.headers["access-control-allow-origin"], "http://foobar.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], isNull);
      expect(resp.headers["access-control-allow-credentials"], "true");
    });

    test("If one exposed header, return it in ACEH", () async {
      var resp = await http.get("http://localhost:8000/restrictive_nocreds",
          headers: {"Origin": "http://exclusive.com"});
      expect(resp.statusCode, 200);
      expect(
          resp.headers["access-control-allow-origin"], "http://exclusive.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], "foobar");
      expect(resp.headers["access-control-allow-credentials"], isNull);
    });

    test("If multiple exposed headers, return them in ACEH", () async {
      var resp = await http.get("http://localhost:8000/restrictive", headers: {
        "Authorization": "Bearer auth",
        "Origin": "http://exclusive.com"
      });

      expect(resp.statusCode, 200);
      expect(
          resp.headers["access-control-allow-origin"], "http://exclusive.com");
      expect(resp.headers["access-control-allow-headers"], isNull);
      expect(resp.headers["access-control-allow-methods"], isNull);
      expect(resp.headers["access-control-expose-headers"], "foobar, x-foo");
      expect(resp.headers["access-control-allow-credentials"], "true");
    });
  });

  // Make sure preflights don't get exposed headers
  group("Preflight: If the origin header is not present", () {
    // This group ensures that an OPTIONS request without CORS headers gets treated like a normal OPTIONS request
    test(
        "Return 200 if there is an actual endpoint for OPTIONS (No CORS Headers)",
        () async {
      var req = await HttpClient().open("OPTIONS", "localhost", 8000, "opts");
      req.headers.set("Authorization", "Bearer auth");
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test(
        "Return 401 if there is an actual endpoint for OPTIONS and request is unauthorized (No CORS Headers)",
        () async {
      var req = await HttpClient().open("OPTIONS", "localhost", 8000, "opts");
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 401);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Return 404 if there is no endpoint for OPTIONS (No CORS Headers)",
        () async {
      var req =
          await HttpClient().open("OPTIONS", "localhost", 8000, "foobar");
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 404);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test(
        "Return 405 if there is an endpoint, but OPTIONS not supported (No CORS Headers)",
        () async {
      var req =
          await HttpClient().open("OPTIONS", "localhost", 8000, "nopolicy");
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 405);
      expectThatNoCORSProcessingOccurred(resp);
    });
  });

  group(
      "Preflight: If the value of Origin header is not a case-sensitive match for list of origins...",
      () {
    // This group ensures that if the Origin is invalid, we return a 403.

    test("If origin is correct, get 200 from OPTIONS", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive");
      req.headers.set("Origin", "http://exclusive.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://exclusive.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test(
        "If origin is invalid because of case-sensitivity, get 403 from OPTIONS",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive");
      req.headers.set("Origin", "http://Exclusive.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If origin is invalid, get 403 from OPTIONS", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If no policy defined, return 403", () async {
      var req =
          await HttpClient().open("OPTIONS", "localhost", 8000, "nopolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });
  });

  group("Preflight: Validate headers and methods", () {
    // This group ensures that if the Origin is valid, but there is no Access-Control-Request-Method, we return a 403.
    test("If allow method is not available", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "PATCH");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If allow method is available", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("Just one allowed method returns that", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "single_method");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "GET");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"), "GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
      expect(resp.headers.value("access-control-max-age"), "86400");
    });

    test("If one allow header is available", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("Headers are case insensitive", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers",
          "Authorization, X-Requested-With, X-Forwarded-For, Content-Type");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("If multiple allow header is available", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers",
          "authorization, x-requested-with, x-forwarded-for, content-type");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("If allow header is a simple header, return 200", () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("If one allow header is not available, but others are, get a 403",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers",
          "authorization, x-requested-with, x-forwarded-for, content-type, x-foo");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If one specified allow headers are not available, get a 403",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "x-foo");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If all specified allow headers are not available, get a 403",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "x-foo, x-bar");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });
  });

  group(
      "Preflight: Add Access-Control-Allow-Origin and Access-Control-Allow-Credentials",
      () {
    // This group ensures that if we have a valid origin, we add the allow-origin and optionally allow-credentials
    test(
        "If valid origin and endpoint allows credentials, add allow origin/creds",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test(
        "If valid origin and endpoint do not allow credentials, add allow origin but not creds",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive_nocreds");
      req.headers.set("Origin", "http://exclusive.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://exclusive.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), isNull);
    });
  });

  group("Preflight: Optionally add a single Acces-Control-Max-Age header", () {
    // This group ensures that we add Access-Control-Max-Age if defined and everything else is valid
    test(
        "If valid origin and endpoint allows credentials, add allow origin/creds",
        () async {
      var req = await HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy");
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "origin, authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
      expect(resp.headers.value("access-control-max-age"), "86400");
    });
  });

  group("Generators and policies", () {
    test("Headers don't continue to pile up when using a generator", () async {
      http.Response lastResponse;

      for (var i = 0; i < 10; i++) {
        lastResponse = await http.get("http://localhost:8000/add",
            headers: {"Origin": "http://www.a.com"});
        expect(lastResponse.statusCode, 200);
      }

      expect(
          lastResponse.headers["access-control-expose-headers"]
              .indexOf("X-Header"),
          greaterThanOrEqualTo(0));
      expect(
          lastResponse.headers["access-control-expose-headers"]
              .indexOf("X-Header"),
          lastResponse.headers["access-control-expose-headers"]
              .lastIndexOf("X-Header"));
    });
  });
}

void expectThatNoCORSProcessingOccurred(dynamic resp) {
  if (resp is http.Response) {
    expect(resp.headers["access-control-allow-origin"], isNull);
    expect(resp.headers["access-control-allow-headers"], isNull);
    expect(resp.headers["access-control-allow-methods"], isNull);
    expect(resp.headers["access-control-expose-headers"], isNull);
    expect(resp.headers["access-control-allow-credentials"], isNull);
  } else if (resp is HttpClientResponse) {
    expect(resp.headers.value("access-control-allow-origin"), isNull);
    expect(resp.headers.value("access-control-allow-headers"), isNull);
    expect(resp.headers.value("access-control-allow-methods"), isNull);
    expect(resp.headers.value("access-control-expose-headers"), isNull);
    expect(resp.headers.value("access-control-allow-credentials"), isNull);
  }
}

class CORSChannel extends ApplicationChannel with AuthValidator {
  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/add").link(() => AdditiveController());

    router
        .route("/opts")
        .link(() => Authorizer(this))
        .link(() => OptionsController());
    router.route("/restrictive").link(() => RestrictiveOriginController());
    router.route("/single_method").link(() => SingleMethodController());
    router
        .route("/restrictive_auth")
        .link(() => Authorizer(this))
        .link(() => RestrictiveOriginController());
    router
        .route("/restrictive_nocreds")
        .link(() => RestrictiveNoCredsOriginController());
    router.route("/nopolicy").link(() => NoPolicyController());
    router.route("/defaultpolicy").link(() => DefaultPolicyController());
    router
        .route("/nopolicyauth")
        .link(() => Authorizer(this))
        .link(() => NoPolicyController());
    router
        .route("/defaultpolicyauth")
        .link(() => Authorizer(this))
        .link(() => DefaultPolicyController());
    return router;
  }

  @override
  FutureOr<Authorization> validate<T>(
      AuthorizationParser<T> parser, T authorizationData,
      {List<AuthScope> requiredScope}) {
    if (authorizationData == "noauth") {
      return null;
    }
    return Authorization("a", 1, this);
  }
}

class NoPolicyController extends ResourceController {
  NoPolicyController() {
    policy = null;
  }

  @Operation.get()
  Future<Response> getAll() async {
    return Response.ok("getAll");
  }

  @Operation.post()
  Future<Response> throwException() async {
    throw Response.badRequest(body: {"error": "Foobar"});
  }
}

class DefaultPolicyController extends ResourceController {
  @Operation.get()
  Future<Response> getAll() async {
    return Response.ok("getAll");
  }

  @Operation.post()
  Future<Response> throwException() async {
    throw Response.badRequest(body: {"error": "Foobar"});
  }
}

class RestrictiveNoCredsOriginController extends ResourceController {
  RestrictiveNoCredsOriginController() {
    policy.allowedOrigins = ["http://exclusive.com"];
    policy.allowCredentials = false;
    policy.exposedResponseHeaders = ["foobar"];
  }

  @Operation.get()
  Future<Response> getAll() async {
    return Response.ok("getAll");
  }

  @Operation.post()
  Future<Response> makeThing() async {
    return Response.ok("makeThing");
  }
}

class RestrictiveOriginController extends ResourceController {
  RestrictiveOriginController() {
    policy.allowedOrigins = ["http://exclusive.com"];
    policy.exposedResponseHeaders = ["foobar", "x-foo"];
  }

  @Operation.get()
  Future<Response> getAll() async {
    return Response.ok("getAll");
  }

  @Operation.post()
  Future<Response> makeThing() async {
    return Response.ok("makeThing");
  }
}

class OptionsController extends ResourceController {
  OptionsController() {
    policy = null;
  }

  @Operation("OPTIONS")
  Future<Response> getThing() async {
    return Response.ok("getThing");
  }
}

class SingleMethodController extends ResourceController {
  SingleMethodController() {
    policy.allowedMethods = ["GET"];
  }
}

class AdditiveController extends ResourceController {
  AdditiveController() {
    policy.exposedResponseHeaders.add("X-Header");
  }

  @Operation.get()
  Future<Response> getThing() async {
    return Response.ok(null);
  }
}
