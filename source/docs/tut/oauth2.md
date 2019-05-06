# 5. Adding Authentication and Authorization with OAuth 2.0

Our `heroes` application lets anyone create or view the same set of heroes. We will continue to build on the last chapter's project, `heroes`, requiring a user to log in before viewing or creating heroes.

!!! note "We're Done With the Browser App"
    We're at the point now where using the browser application to test our Aqueduct app gets a bit cumbersome. From here on out, we'll use `curl`, `aqueduct document client` and tests.

## The Basics of OAuth 2.0

[OAuth 2.0](https://tools.ietf.org/html/rfc6749) is an authorization framework that also contains guidance on authentication. Authentication is the process of proving you are a particular user, typically through a username and password. Authorization is the process of ensuring that a user can access a particular resource or collection of resources. In our application, a user will have to be authenticated before being authorized to view or create heroes.

In a simple authentication and authorization scheme, each HTTP request contains the username and password (credentials) of the user in an `Authorization` header. There are a number of security risks involved in doing this, so OAuth 2.0 takes another approach: you send your credentials once, and get a 'access token' in return. You then send this access token in each request. Because the server grants the token, it knows that you've already entered your credentials (you've *authenticated*) and it remembers who the token belongs to. It's effectively the same thing as sending your credentials each time, except that the token has a time limit and can be revoked when things go wrong.

Aqueduct has a built-in OAuth 2.0 implementation that leverages the ORM. This implementation is part of the `aqueduct` package, but it is a separate library named `aqueduct/managed_auth`. It takes a few steps to set up that might be difficult to understand if you are not familiar with OAuth 2.0, but you'll get a well-tested, secure authorization implementation.

!!! note "Alternative Implementations"
    Using `package:aqueduct/managed_auth` is preferable in most cases. In some cases, you may wish to store authorization information in different database system or use token formats like [JWT](https://jwt.io). This is a complex topic that requires significant testing efforts, and is outside the scope of this tutorial.

## Setting up OAuth 2.0: Creating a User Type

Our application needs some concept of a 'user' - a person who logs into the application to manage heroes. This user will have a username and password. In a later exercise, a user will also have a list of heroes that belong to them. Create a new file `model/user.dart` and enter the following code:

```dart
import 'package:aqueduct/managed_auth.dart';
import 'package:heroes/heroes.dart';
import 'package:heroes/model/hero.dart';

class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner<_User> {}

class _User extends ResourceOwnerTableDefinition {}
```

The imported library `package:aqueduct/managed_auth.dart` contains types that use the ORM to store users, tokens and other OAuth 2.0 related data. One of those types is `ResourceOwnerTableDefinition`, the superclass of our user's table definition. This type contains all of the required fields that Aqueduct needs to implement authentication.

!!! tip "Resource Owners"
    A *resource owner* is a more general term for a 'user' that comes from the OAuth 2.0 specification. In the framework, you'll see types and variables using some variant of *resource owner*, but for all intents and purposes, you can consider this a 'user'.

If you are curious, `ResourceOwnerTableDefinition` looks like this:

```dart
class ResourceOwnerTableDefinition {
  @primaryKey
  int id;

  @Column(unique: true, indexed: true)
  String username;

  @Column(omitByDefault: true)
  String hashedPassword;

  @Column(omitByDefault: true)
  String salt;

  ManagedSet<ManagedAuthToken> tokens;
}
```

Because these fields are in `User`'s table definition, our `User` table has all of these database columns.

!!! note "ManagedAuthResourceOwner"
    Note that `User` implements `ManagedAuthResourceOwner<_User>` - this is a requirement of any OAuth 2.0 resource owner type when using `package:aqueduct/managed_auth`.

## Setting up OAuth 2.0: AuthServer and its Delegate

Now that we have a user, we need some way to create new users and authenticate them. Authentication is fairly tricky, especially in OAuth 2.0, so there is a service object that does the hard part for us called an `AuthServer`. This type has all of the logic needed to authentication and authorize users. For example, an `AuthServer` can generate a new token if given valid user credentials.

In `channel.dart`, add the following imports to the top of your file:

```dart
import 'package:aqueduct/managed_auth.dart';
import 'package:heroes/model/user.dart';
```

Then, declare a new `authServer` property in your channel and initialize it in `prepare`:

```dart
class HeroesChannel extends ApplicationChannel {
  ManagedContext context;

  // Add this field
  AuthServer authServer;

  Future prepare() async {
    logger.onRecord.listen((rec) => print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));

    final config = HeroConfig(options.configurationFilePath);
    final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    final persistentStore = PostgreSQLPersistentStore.fromConnectionInfo(
      config.database.username,
      config.database.password,
      config.database.host,
      config.database.port,
      config.database.databaseName);

    context = ManagedContext(dataModel, persistentStore);

    // Add these two lines:
    final authStorage = ManagedAuthDelegate<User>(context);
    authServer = AuthServer(authStorage);
  }
  ...
```

While an `AuthServer` handles the logic of authentication and authorization, it doesn't know how to store or fetch the data it uses for those tasks. Instead, it relies on a *delegate* object to handle storing and fetching data from a database. In our application, we use `ManagedAuthDelegate<T>` - from `package:aqueduct/managed_auth` - as the delegate. This type uses the ORM for these tasks; the type argument must be our application's user object.

!!! tip "Delegation"
    Delegation is a design pattern where an object has multiple callbacks that are grouped into an interface. Instead of defining a closure for each callback, a type implements methods that get called by the delegating object. It is a way of organizing large amounts of related callbacks into a tidy class.

By importing `aqueduct/managed_auth`, we've added a few more managed objects to our application (to store tokens and other authentication data) and we also have a new `User` managed object. It's a good time to run a database migration. From your project directory, run the following commands:

```
aqueduct db generate
aqueduct db upgrade --connect postgres://heroes_user:password@localhost:5432/heroes
```

## Setting up OAuth 2.0: Registering Users

Now that we have the concept of a user, our database and application are set up to handle authentication, we can start creating new users. Let's create a new controller for registering users. This controller will accept `POST` requests that contain a username and password in the body. It will insert a new user into the database and securely hash the user's password.

Before we create this controller, there is something we need to consider: our registration endpoint will require the user's password, but we store the user's password as a cryptographic hash. This prevents someone with access to your database from knowing a user's password. In order to bind the body of a request to a `User` object, it needs a password field, but we don't want to store the password in the database without first hashing it.

We can accomplish this with *transient properties*. A transient property is a property of a managed object that isn't stored in the database. They are declared in the managed object subclass instead of the table definition. By default, a transient property is not read from a request body or encoded into a response body; unless we add the `Serialize` annotation to it. Add this property to your `User` type:

```dart
class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner<_User> {
  @Serialize(input: true, output: false)
  String password;
}
```

This declares that a `User` has a transient property `password` that can be read on input (from a request body), but is not sent on output (to a response body). We don't have to run a database migration because transient properties are not stored in a database.

Now, create the file `controller/register_controller.dart` and enter the following code:

```dart
import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:heroes/model/user.dart';

class RegisterController extends ResourceController {
  RegisterController(this.context, this.authServer);

  final ManagedContext context;
  final AuthServer authServer;

  @Operation.post()
  Future<Response> createUser(@Bind.body() User user) async {
    // Check for required parameters before we spend time hashing
    if (user.username == null || user.password == null) {
      return Response.badRequest(
        body: {"error": "username and password required."});
    }

    user
      ..salt = AuthUtility.generateRandomSalt()
      ..hashedPassword = authServer.hashPassword(user.password, user.salt);

    return Response.ok(await Query(context, values: user).insert());
  }
}
```

This controller takes POST requests that contain a user. A user has many fields (username, password, hashedPassword, salt), but we will calculate the latter two and only require that the request contain the first two. The controller generates a salt and hash of the password before storing it in the database. In `channel.dart`, let's link this controller - don't forget to import it!

```dart
import 'package:heroes/controller/register_controller.dart';

...

  @override
  Controller get entryPoint {
    final router = Router();

    router
      .route('/heroes/[:id]')
      .link(() => HeroesController(context));

    router
      .route('/register')
      .link(() => RegisterController(context, authServer));

    return router;
  }
}    
```

Let's run the application and create a new user using `curl` from the command-line. (We'll specify `-n1` to designate using one isolate and speed up startup.)

```
aqueduct serve -n1
```

Then, issue a request to your server:

```dart
curl -X POST http://localhost:8888/register -H 'Content-Type: application/json' -d '{"username":"bob", "password":"password"}'
```

You'll get back the new user object and its username:

```
{"id":1,"username":"bob"}
```

## Setting up OAuth 2.0: Authenticating Users

Now that we have a user with a password, we can can create an endpoint that takes user credentials and returns an access token. The good news is that this controller already exists in Aqueduct, you just have to hook it up to a route. Update `entryPoint` in `channel.dart` to add an `AuthController` for the route `/auth/token`:

```dart
@override
Controller get entryPoint {
  final router = Router();

  // add this route
  router
    .route('/auth/token')
    .link(() => AuthController(authServer));

  router
    .route('/heroes/[:id]')
    .link(() => HeroesController(context));

  router
    .route('/register')
    .link(() => RegisterController(context, authServer));

  return router;
}
```

An `AuthController` follows the OAuth 2.0 specification for granting access tokens when given valid user credentials. To understand how a request to this endpoint must be structured, we need to discuss OAuth 2.0 *clients*. In OAuth 2.0, a client is an application that is allowed to access your server on behalf of a user. A client can be a browser application, a mobile application, another server, a voice assistant, etc. A client always has an identifier string, typically something like 'com.stablekernel.account_app.mobile'.

When authenticating, a user is always authenticated through a client. This client information must be attached to every authentication request, and the server must validate that the client had been previously registered. Therefore, we need to register a new client for our application. A client is stored in our application's database using the `aqueduct auth add-client` CLI. Run the following command from your project directory:

```
aqueduct auth add-client --id com.heroes.tutorial --connect postgres://heroes_user:password@localhost:5432/heroes
```

!!! note "OAuth 2.0 Clients"
    A client must have an identifier, but it may also have a secret, redirect URI and list of allowed scopes. See the [guides on OAuth 2.0](../auth/index.md) for how these options impacts authentication. Most notably, a client identifier must have a secret to issue a *refresh token*. Clients are stored in an application's database.

This will insert a new row into an OAuth 2.0 client table created by our last round of database migration and allow us to make authentication requests. An authentication request must meet all of the following criteria:

- the client identifier (and secret, if it exists) are included as a basic `Authorization` header.
- the username and password are included in the request body
- the key-value `grant_type=password` is included in the request body
- the request body content-type is `application/x-www-form-urlencoded`; this means the request body is effectively a query string (e.g. `username=bob&password=pw&grant_type=password`)

In Dart code, this would like this:

```dart
import 'package:http/http.dart' as http; // Must include http package in your pubspec.yaml

final clientID = "com.heroes.tutorial";
final body = "username=bob&password=password&grant_type=password";

// Note the trailing colon (:) after the clientID.
// A client identifier secret would follow this, but there is no secret, so it is the empty string.
final clientCredentials = Base64Encoder().convert("$clientID:".codeUnits);

final response = await http.post(
  "https://stablekernel.com/auth/token",
  headers: {
    "Content-Type": "application/x-www-form-urlencoded",
    "Authorization": "Basic $clientCredentials"
  },
  body: body);
```

You can execute that code or you can use the following `curl`:

```
curl -X POST http://localhost:8888/auth/token -H 'Authorization: Basic Y29tLmhlcm9lcy50dXRvcmlhbDo=' -H 'Content-Type: application/x-www-form-urlencoded' -d 'username=bob&password=password&grant_type=password'
```

If you were successful, you'll get the following response containing an access token:

```
{"access_token":"687PWKFHRTQ9MveQ2dKvP95D4cWie1gh","token_type":"bearer","expires_in":86399}
```

Hang on to this access token, we'll use it in a moment.

## Setting up OAuth 2.0: Securing Routes

Now that we can create and authenticate users, we can protect our heroes from anonymous users by requiring an access token for hero requests. In `channel.dart`, link an `Authorizer` in the middle of the `/heroes` channel:

```dart
router
  .route('/heroes/[:id]')
  .link(() => Authorizer.bearer(authServer))
  .link(() => HeroesController(context));
```

An `Authorizer` protects a channel from unauthorized requests by validating the `Authorization` header of a request. When created with `Authorizer.bearer`, it ensures that the authorization header contains a valid access token. Restart your application and try and access the `/heroes` endpoint without including any authorization:

```
curl -X GET --verbose http://localhost:8888/heroes
```

You'll get a 401 Unauthorized response. Now, include your access token in a bearer authorization header (note that your token will be different):

```
curl -X GET http://localhost:8888/heroes -H 'Authorization: Bearer 687PWKFHRTQ9MveQ2dKvP95D4cWie1gh'
```

You'll get back your list of heroes!

!!! note "Other Uses of Authorizer"
    An `Authorizer` can validate access token scopes and basic authorization credentials. You'll see examples of these in a later exercise.
