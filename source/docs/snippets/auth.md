# Aqueduct Authorization and Authentication Snippets

## Enable OAuth 2.0

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppSink extends RequestSink {
  AppSink(ApplicationConfiguration appConfig) : super(appConfig) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        "username",
        "password",
        "localhost",
        5432
        "my_app");

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);

    var authStorage = new ManagedAuthStorage<User>(ManagedContext.defaultContext);
    authServer = new AuthServer(authStorage);
  }

  AuthServer authServer;

  @override
  void setupRouter(Router router) {
    router.route("/auth/token").generate(() => new AuthController(authServer));  
  }
}
```

## Add OAuth 2.0 Clients to Database

```
aqueduct auth add-client \
  --id com.app.test \
  --secret supersecret \
  --allowed-scopes 'profile kiosk:location raw_db_access.readonly' \
  --connect postgres://username:password@localhost:5432/my_app
```

## Require OAuth 2.0 Scope to Access Routes

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppSink extends RequestSink {
  AppSink(ApplicationConfiguration appConfig) : super(appConfig) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        "username",
        "password",
        "localhost",
        5432
        "my_app");

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);

    var authStorage = new ManagedAuthStorage<User>(ManagedContext.defaultContext);
    authServer = new AuthServer(authStorage);
  }

  AuthServer authServer;

  @override
  void setupRouter(Router router) {
    router.route("/auth/token").generate(() => new AuthController(authServer));

    router
      .route("/profile")
      .pipe(new Authorizer.bearer(authServer, scopes: ["profile.readonly"]))
      .generate(() => new ProfileController());
  }
}

class ProfileController extends HTTPController {
  @Bind.method("get")
  Future<Response> getProfile() async {
    var id = request.authorization.resourceOwnerIdentifier;
    return new Response.ok(await profileForUserID(id));
  }
}
```

## Basic Authentication

```dart
import 'package:aqueduct/aqueduct.dart';

class AppSink extends RequestSink {
  AppSink(ApplicationConfiguration appConfig) : super(appConfig) {
    passwordVerifier = new PasswordVerifier();
  }

  PasswordVerified passwordVerifier;

  @override
  void setupRouter(Router router) {
    router
      .route("/profile")
      .pipe(new Authorizer.basic(passwordVerifier))
      .listen((req) async => new Response.ok(null));
  }
}

class PasswordVerifier extends AuthValidator {
  @override
  Future<Authorization> fromBasicCredentials(AuthBasicCredentials usernameAndPassword) async {
    if (!isPasswordCorrect(usernameAndPassword)) {
      return null;
    }

    return new Authorization(null, usernameAndPassword.username, this);
  }

  @override
  Future<Authorization> fromBearerToken(String bearerToken, {List<AuthScope> scopesRequired}) {
    throw new HTTPResponseException(400, "Use basic authorization");
  }
}
```

## Add OAuth 2.0 Authorization Code Flow

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppSink extends RequestSink {
  AppSink(ApplicationConfiguration appConfig) : super(appConfig) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        "username",
        "password",
        "localhost",
        5432
        "my_app");

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);

    var authStorage = new ManagedAuthStorage<User>(ManagedContext.defaultContext);
    authServer = new AuthServer(authStorage);
  }

  AuthServer authServer;

  @override
  void setupRouter(Router router) {
    router.route("/auth/token").generate(() => new AuthController(authServer));  

    router.route("/auth/code").generate(() => new AuthCodeController(authServer,
        renderAuthorizationPageHTML: renderLoginPage));
  }

  Future<String> renderLoginPage(
    AuthCodeController controller, Uri requestURI, Map<String, String> queryParameters) async {

    return """
<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <title>Login</title>
</head>

<body>
<div class="container">
    <h1>Login</h1>
    <form action="${requestURI.path}" method="POST">
        <input type="hidden" name="state" value="${queryParameters["state"]}">
        <input type="hidden" name="client_id" value="${queryParameters["client_id"]}">
        <input type="hidden" name="response_type" value="code">
        <div class="form-group">
            <label for="username">User Name</label>
            <input type="text" class="form-control" name="username" placeholder="Please enter your user name">
        </div>
        <div class="form-group">
            <label for="password">Password</label>
            <input type="password" class="form-control" name="password" placeholder="Please enter your password">
        </div>
        <button type="submit" class="btn btn-success">Login</button>
    </form>
</div>
</body>

</html>
    """;    
  }
}
```
