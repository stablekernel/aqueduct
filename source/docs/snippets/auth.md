# Aqueduct Authorization and Authentication Snippets

## Enable OAuth 2.0

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppChannel extends ApplicationChannel {
  AuthServer authServer;
  ManagedContext context;

  @override
  Future prepare() async {
    final dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    final psc = new PostgreSQLPersistentStore(
        "username",
        "password",
        "localhost",
        5432
        "my_app");

    context = new ManagedContext(dataModel, psc);

    final delegate = new ManagedAuthDelegate<User>(context);
    authServer = new AuthServer(delegate);
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/auth/token").link(() => AuthController(authServer));  
    return router;
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

class AppChannel extends ApplicationChannel {
  AuthServer authServer;
  ManagedContext context;

  @override
  Future prepare() async {
    final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    final psc = PostgreSQLPersistentStore(
        "username",
        "password",
        "localhost",
        5432
        "my_app");

    context = new ManagedContext(dataModel, psc);

    final delegate = ManagedAuthDelegate<User>(context);
    authServer = AuthServer(delegate);
  }

  @override
  Controller get entryPoint {
    router.route("/auth/token").link(() => AuthController(authServer));

    router
      .route("/profile")
      .link(() => Authorizer.bearer(authServer, scopes: ["profile.readonly"]))
      .link(() => ProfileController(context));
  }
}

class ProfileController extends ResourceController {
  ProfileController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> getProfile() async {
    final id = request.authorization.ownerID;
    final query = new Query<User>(context)
      ..where((u) => u.id).equalTo(id);

    return new Response.ok(await query.fetchOne());
  }
}
```

## Basic Authentication

```dart
import 'package:aqueduct/aqueduct.dart';

class AppChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();
    router
      .route("/profile")
      .link(() => Authorizer.basic(PasswordVerifier()))
      .linkFunction((req) async => new Response.ok(null));

    return router;
  }
}

class PasswordVerifier extends AuthValidator {
  @override
  FutureOr<Authorization> validate<T>(AuthorizationParser<T> parser, T authorizationData, {List<AuthScope> requiredScope}) {
    if (!isPasswordCorrect(authorizationData)) {
      return null;
    }

    return Authorization(null, authorizationData.username, this);
  }
}
```

## Add OAuth 2.0 Authorization Code Flow

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppChannel extends ApplicationChannel {
  AuthServer authServer;
  ManagedContext context;

  @override
  Future prepare() async {
    final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    final psc = PostgreSQLPersistentStore(
        "username",
        "password",
        "localhost",
        5432
        "my_app");

    context = new ManagedContext(dataModel, psc);

    final delegate = new ManagedAuthDelegate<User>(context);
    authServer = new AuthServer(delegate);
  }  

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/auth/token").link(() => AuthController(authServer));  

    router.route("/auth/code").link(() => AuthCodeController(authServer, delegate: this));

    return router;
  }

  Future<String> render(AuthCodeController forController, Uri requestUri, String responseType, String clientID,
      String state, String scope) async {
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
    <form action="${requestUri.path}" method="POST">
        <input type="hidden" name="state" value="$state">
        <input type="hidden" name="client_id" value="$clientID">
        <input type="hidden" name="response_type" value="$responseType">
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
