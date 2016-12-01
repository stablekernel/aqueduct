import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

// These tests are based on the specification found at http://www.w3.org/TR/cors/.
void main() {
  var app = new Application<CORSSink>();
  app.configuration.port = 8000;

  setUpAll(() async {
    await app.start(runOnMainIsolate: true);
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
      var req =
          await (new HttpClient().open("OPTIONS", "localhost", 8000, "opts"));
      req.headers.set("Authorization", "Bearer auth");
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 200);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test(
        "Return 401 if there is an actual endpoint for OPTIONS and request is unauthorized (No CORS Headers)",
        () async {
      var req =
          await (new HttpClient().open("OPTIONS", "localhost", 8000, "opts"));
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 401);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("Return 404 if there is no endpoint for OPTIONS (No CORS Headers)",
        () async {
      var req =
          await (new HttpClient().open("OPTIONS", "localhost", 8000, "foobar"));
      var resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 404);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test(
        "Return 405 if there is an endpoint, but OPTIONS not supported (No CORS Headers)",
        () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "nopolicy"));
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
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive"));
      req.headers.set("Origin", "http://exclusive.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://exclusive.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test(
        "If origin is invalid because of case-sensitivity, get 403 from OPTIONS",
        () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive"));
      req.headers.set("Origin", "http://Exclusive.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If origin is invalid, get 403 from OPTIONS", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If no policy defined, return 403", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "nopolicy"));
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
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "PATCH");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If allow method is available", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("Just one allowed method returns that", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "single_method"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "GET");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"), "GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
      expect(resp.headers.value("access-control-max-age"), "86400");
    });

    test("If one allow header is available", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("If multiple allow header is available", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers",
          "authorization, x-requested-with, x-forwarded-for, content-type");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("If allow header is a simple header, return 200", () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test("If one allow header is not available, but others are, get a 403",
        () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
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
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers.set("Access-Control-Request-Headers", "x-foo");
      var resp = await req.close();

      expect(resp.statusCode, 403);
      expectThatNoCORSProcessingOccurred(resp);
    });

    test("If all specified allow headers are not available, get a 403",
        () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
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
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
    });

    test(
        "If valid origin and endpoint do not allow credentials, add allow origin but not creds",
        () async {
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "restrictive_nocreds"));
      req.headers.set("Origin", "http://exclusive.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://exclusive.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
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
      var req = await (new HttpClient()
          .open("OPTIONS", "localhost", 8000, "defaultpolicy"));
      req.headers.set("Origin", "http://foobar.com");
      req.headers.set("Access-Control-Request-Method", "POST");
      req.headers
          .set("Access-Control-Request-Headers", "accept, authorization");
      var resp = await req.close();

      expect(resp.statusCode, 200);
      expect(resp.headers.value("access-control-allow-origin"),
          "http://foobar.com");
      expect(resp.headers.value("access-control-allow-headers"),
          "authorization, x-requested-with, x-forwarded-for, content-type");
      expect(resp.headers.value("access-control-allow-methods"),
          "POST, PUT, DELETE, GET");
      expect(resp.headers.value("access-control-expose-headers"), isNull);
      expect(resp.headers.value("access-control-allow-credentials"), "true");
      expect(resp.headers.value("access-control-max-age"), "86400");
    });
  });
}

expectThatNoCORSProcessingOccurred(dynamic resp) {
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

class CORSSink extends RequestSink
    implements AuthServerDelegate<AuthImpl, TokenImpl, AuthCodeImpl> {
  CORSSink(Map<String, dynamic> opts) : super(opts) {
    authServer = new AuthServer<AuthImpl, TokenImpl, AuthCodeImpl>(this);
  }

  AuthServer<AuthImpl, TokenImpl, AuthCodeImpl> authServer;

  void setupRouter(Router router) {
    router
        .route("/opts")
        .pipe(new Authorizer(authServer))
        .generate(() => new OptionsController());
    router
        .route("/restrictive")
        .generate(() => new RestrictiveOriginController());
    router.route("/single_method").generate(() => new SingleMethodController());
    router
        .route("/restrictive_auth")
        .pipe(new Authorizer(authServer))
        .generate(() => new RestrictiveOriginController());
    router
        .route("/restrictive_nocreds")
        .generate(() => new RestrictiveNoCredsOriginController());
    router.route("/nopolicy").generate(() => new NoPolicyController());
    router
        .route("/defaultpolicy")
        .generate(() => new DefaultPolicyController());
    router
        .route("/nopolicyauth")
        .pipe(new Authorizer(authServer))
        .generate(() => new NoPolicyController());
    router
        .route("/defaultpolicyauth")
        .pipe(new Authorizer(authServer))
        .generate(() => new DefaultPolicyController());
  }

  Future<TokenImpl> tokenForAccessToken(
      AuthServer server, String accessToken) async {
    if (accessToken == "noauth") {
      return null;
    }

    return new TokenImpl()
      ..accessToken = "access"
      ..refreshToken = "access"
      ..clientID = "access"
      ..resourceOwnerIdentifier = "access"
      ..issueDate = new DateTime.now().toUtc()
      ..expirationDate = new DateTime(10000)
      ..type = "password";
  }

  Future<TokenImpl> tokenForRefreshToken(
      AuthServer server, String refreshToken) async {
    if (refreshToken == "noauth") {
      return null;
    }

    return new TokenImpl()
      ..accessToken = "access"
      ..refreshToken = "access"
      ..clientID = "access"
      ..resourceOwnerIdentifier = "access"
      ..type = "password";
  }

  Future<AuthImpl> authenticatableForUsername(
      AuthServer server, String username) async {
    return new AuthImpl()
      ..username = "access"
      ..id = "access";
  }

  Future<AuthImpl> authenticatableForID(AuthServer server, dynamic id) async {
    return new AuthImpl()
      ..username = "access"
      ..id = "access";
  }

  Future<AuthClient> clientForID(AuthServer server, String id) async {
    if (id == "noauth") {
      return null;
    }

    var salt = AuthServer.generateRandomSalt();
    var password = AuthServer.generatePasswordHash("access", salt);

    return new AuthClient("access", password, salt);
  }

  Future deleteTokenForRefreshToken(
      AuthServer server, String refreshToken) async {}
  Future<TokenImpl> storeToken(AuthServer server, TokenImpl t) async => null;
  Future updateToken(AuthServer server, TokenImpl t) async {}
  Future<AuthCodeImpl> storeAuthCode(
          AuthServer server, AuthCodeImpl ac) async =>
      null;
  Future updateAuthCode(AuthServer server, AuthCodeImpl ac) async {}
  Future deleteAuthCode(AuthServer server, AuthCodeImpl ac) async {}
  Future<AuthCodeImpl> authCodeForCode(
      AuthServer server, String authCode) async {
    return new AuthCodeImpl()
      ..code = authCode
      ..expirationDate = new DateTime.now().add(new Duration(minutes: 10));
  }
}

class AuthImpl implements Authenticatable {
  String username;
  String hashedPassword;
  String salt;
  dynamic id;
}

class TokenImpl implements AuthTokenizable {
  String accessToken;
  String refreshToken;
  DateTime issueDate;
  DateTime expirationDate;
  String type;
  dynamic resourceOwnerIdentifier;
  String clientID;
}

class AuthCodeImpl implements AuthTokenExchangable<TokenImpl> {
  String redirectURI;
  String code;
  String clientID;
  dynamic resourceOwnerIdentifier;
  DateTime issueDate;
  DateTime expirationDate;

  TokenImpl token;
}

class NoPolicyController extends HTTPController {
  NoPolicyController() {
    policy = null;
  }

  @httpGet
  getAll() async {
    return new Response.ok("getAll");
  }

  @httpPost
  throwException() async {
    throw new HTTPResponseException(400, "Foobar");
  }
}

class DefaultPolicyController extends HTTPController {
  @httpGet
  getAll() async {
    return new Response.ok("getAll");
  }

  @httpPost
  throwException() async {
    throw new HTTPResponseException(400, "Foobar");
  }
}

class RestrictiveNoCredsOriginController extends HTTPController {
  RestrictiveNoCredsOriginController() {
    policy.allowedOrigins = ["http://exclusive.com"];
    policy.allowCredentials = false;
    policy.exposedResponseHeaders = ["foobar"];
  }

  @httpGet
  getAll() async {
    return new Response.ok("getAll");
  }

  @httpPost
  makeThing() async {
    return new Response.ok("makeThing");
  }
}

class RestrictiveOriginController extends HTTPController {
  RestrictiveOriginController() {
    policy.allowedOrigins = ["http://exclusive.com"];
    policy.exposedResponseHeaders = ["foobar", "x-foo"];
  }
  @httpGet
  getAll() async {
    return new Response.ok("getAll");
  }

  @httpPost
  makeThing() async {
    return new Response.ok("makeThing");
  }
}

class OptionsController extends HTTPController {
  OptionsController() {
    policy = null;
  }

  @HTTPMethod("options")
  getThing() async {
    return new Response.ok("getThing");
  }
}

class SingleMethodController extends HTTPController {
  SingleMethodController() {
    policy.allowedMethods = ["GET"];
  }
}
