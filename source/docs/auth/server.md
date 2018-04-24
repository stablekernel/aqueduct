# Creating AuthServers to Authenticate and Authorize

An `AuthServer` is a service that handles creating, verifying and refreshing authorization tokens. You create an `AuthServer` in your application channel and inject into types that deal with authorization. This types include:

- `Authorizer`: middleware controller that protects endpoint controllers from unauthorized access
- `AuthController`: endpoint controller that grants access tokens
- `AuthCodeController`: endpoint controller that grants authorization codes to be exchanged for access tokens

An `AuthServer` must persist the data it uses and creates - like client identifiers and access tokens. Storage is often performed by a database, but it can be in memory, a cache or some other medium. Because of the many different storage mediums, an `AuthServer` doesn't perform any storage itself - it relies on an instance of `AuthDelegate` specific to your application. This allows storage to be independent of verification logic.

## Creating Instances of AuthServer and AuthDelegate

`AuthDelegate` is an interface that an `AuthServer` uses to handle storage of client identifiers, tokens and other authorization artifacts. An `AuthServer` must be created with a concrete implementation of `AuthDelegate`. Aqueduct contains a concrete implementation of `AuthDelegate` that uses the ORM. It is highly recommended to use this implementation instead of implementing your own storage because it has been thoroughly tested and handles cleaning up expired data correctly.

This concrete implementation is named `ManagedAuthDelegate<T>`. It exists in a sub-package of Aqueduct and must be explicitly imported. Here's an example of creating an `AuthServer` and `ManagedAuthDelegate<T>`:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class MyApplicationChannel extends ApplicationChannel {  
  AuthServer authServer;

  @override
  Future prepare() async {
    final context = ManagedContext(...);
    final delegate = ManagedAuthDelegate<User>(context);
    authServer = AuthServer(delegate);
  }

  ...
}
```

(Notice that `ManagedAuthDelegate` has a type argument - this will be covered in the next section.)

While `AuthServer` has methods for handling authorization tasks, it is rarely used directly. Instead, `AuthCodeController` and `AuthController` are hooked up to routes to grant authorization tokens through your application's HTTP API. Instances of `Authorizer` secure routes in channels. All of these types invoke the appropriate methods on the `AuthServer`. Here's an example `ApplicationChannel` subclass that sets up and uses authorization:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class MyApplicationChannel extends ApplicationChannel {
  AuthServer authServer;
  ManagedContext context;

  @override
  Future prepare() async {
    context = ManagedContext(...);
    final delegate = ManagedAuthDelegate<User>(context);
    authServer = AuthServer(delegate);
  }

  @override
  Controller get entryPoint {
    final router = Router();

    // Set up auth token route- this grants and refresh tokens
    router.route("/auth/token").link(() => AuthController(authServer));

    // Set up auth code route- this grants temporary access codes that can be exchanged for token
    router.route("/auth/code").link(() => AuthCodeController(authServer));

    // Set up protected route
    router
      .route("/protected")
      .link(() => Authorizer.bearer(authServer))
      .link(() => ProtectedController());

    return router;
  }
}
```

For more details on authorization controllers like `AuthController`, see [Authorization Controllers](controllers.md). For more details on securing routes, see [Authorizers](authorizer.md).

## Using ManagedAuthDelegate

`ManagedAuthDelegate<T>` is a concrete implementation of `AuthDelegate`, providing storage of authorization tokens and clients for an `AuthServer`. Storage is accomplished by Aqueduct's ORM. `ManagedAuthDelegate<T>`, by default, is not part of the standard `aqueduct` library. To use this class, an application must import `package:aqueduct/managed_auth.dart`.

The type argument to `ManagedAuthDelegate<T>` represents the application's concept of a 'user' or 'account' - OAuth 2.0 terminology would refer to this type as a *resource owner*. A resource owner must be a `ManagedObject<T>` subclass that is specific to your application. Its table definition *must extend* `ManagedAuthenticatable` and the instance type must implement `ManagedAuthResourceOwner<T>`, where `T` is the table definition. A basic definition may look like this:

```dart
class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner<_User> {
}

class _User extends ManagedAuthenticatable {
  @Column(unique: true)
  String email;
}
```

By extending `ManagedAuthenticatable` in the table definition, the database table has the following four columns:

- an integer primary key named `id`
- a unique string `username`
- a password hash
- a salt used to generate the password hash

A `ManagedAuthenticatable` also has a `ManagedSet` of `tokens` for each token that has been granted on its behalf.

The interface `ManagedAuthResourceOwner<T>` is a requirement that ensures the type argument is both a `ManagedObject<T>` and `ManagedAuthenticatable`, and serves no other purpose than to restrict `ManagedAuthDelegate<T>`'s type parameter.

This structure allows an application to declare its own 'user' type while still enforcing the needs of Aqueduct's OAuth 2.0 implementation.

The `managed_auth` library also declares two `ManagedObject<T>` subclasses. `ManagedAuthToken` represents instances of authorization tokens and codes, and `ManagedAuthClient` represents instances of OAuth 2.0 clients. This means that an Aqueduct application that uses `ManagedAuthDelegate<T>` has a minimum of three database tables: users, tokens and clients.

`ManagedAuthDelegate<T>` will delete authorization tokens and codes when they are no longer in use. This is determined by how many tokens a resource owner has and the tokens expiration dates. Once a resource owner acquires more than 40 tokens/codes, the oldest tokens/codes (determined by expiration date) are deleted. Effectively, the resource owner is limited to 40 tokens. This number can be changed when instantiating `ManagedAuthDelegate<T>`:

```dart
final delegate = ManagedAuthDelegate(context, tokenLimit: 20);
```

## Configuring the Database

`ManagedAuthDelegate<T>` requires database tables for its users, tokens and clients. Use the [database command-line tool](../db/db_tools.md) on your project to generate migration scripts and execute them against a database. This tool will see the declarations for your user type, `ManagedAuthToken` and `ManagedAuthClient` and create the appropriate tables.
