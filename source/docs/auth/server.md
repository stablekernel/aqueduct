# Creating AuthServers to Authenticate and Authorize

An instance of `AuthServer` handles creating, verifying and refreshing authorization tokens. They are created in a `ApplicationChannel` constructor and are used by instances of `Authorizer`, `AuthController` and `AuthCodeController`.

An `AuthServer` must persist the data it uses and creates - like client identifiers and access tokens. Storage is often performed by a database, but it can be in memory, a cache or some files. For that reason, an `AuthServer` doesn't perform any storage itself - it relies on an instance of `AuthDelegate` specific to your use case.

This allows storage to be independent of verification logic.

## Creating Instances of AuthServer and AuthDelegate

An instance of `AuthServer` is created in a `ApplicationChannel`'s constructor along with its instance of `AuthDelegate`. `AuthDelegate` is just an interface - storage is implemented by providing an implementation for each of its methods.

Because storage can be quite complex and sensitive, the type `ManagedAuthDelegate<T>` implements storage with `ManagedObject<T>`s and `Query<T>`s. It is highly recommended to use this type instead of implementing your own storage because it has been thoroughly tested and handles cleaning up expired data correctly.

`ManagedAuthDelegate<T>` is declared in a sub-library, `managed_auth`, that is part of the `aqueduct` package but not part of the `aqueduct` library. Therefore, it must be explicitly imported. Here's an example of creating an `AuthServer` and `ManagedAuthDelegate<T>`:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class MyApplicationChannel extends ApplicationChannel {  
  AuthServer authServer;

  @override
  Future prepare() async {
    final context = new ManagedContext(...);
    final delegate = new ManagedAuthDelegate<User>(context);
    authServer = new AuthServer(delegate);
  }

  ...
}
```

(Notice that `ManagedAuthDelegate` has a type argument - this will be covered in the next section.)

While `AuthServer` has methods for handling authorization tasks, it is rarely used directly. Instead, `AuthCodeController` and `AuthController` are hooked up to routes to grant authorization tokens via the API. Instances of `Authorizer` secure routes in channels. All of these types invoke the appropriate methods on the `AuthServer`.

Therefore, a full authorization implementation rarely extends past a `ApplicationChannel`. Here's an example `ApplicationChannel` subclass that sets up and uses authorization:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class MyApplicationChannel extends ApplicationChannel {
  AuthServer authServer;
  ManagedContext context;

  @override
  Future prepare() async {
    context = new ManagedContext(...);
    final delegate = new ManagedAuthDelegate<User>(context);
    authServer = new AuthServer(delegate);
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    // Set up auth token route- this grants and refresh tokens
    router.route("/auth/token").generate(() => new AuthController(authServer));

    // Set up auth code route- this grants temporary access codes that can be exchanged for token
    router.route("/auth/code").generate(() => new AuthCodeController(authServer));

    // Set up protected route
    router
      .route("/protected")
      .pipe(new Authorizer.bearer(authServer))
      .generate(() => new ProtectedController());

    return router;
  }
}
```

For more details on authorization controllers like `AuthController`, see [Authorization Controllers](controllers.md). For more details on securing routes, see [Authorizers](authorizer.md).

## Using ManagedAuthDelegate

`ManagedAuthDelegate<T>` is a concrete implementation of `AuthDelegate`, providing storage of authorization tokens and clients for `AuthServer`. Storage is accomplished by Aqueduct's ORM. `ManagedAuthDelegate<T>`, by default, is not part of the standard `aqueduct/aqueduct` library. To use this class, an application must import `package:aqueduct/managed_auth.dart`.

The type argument to `ManagedAuthDelegate<T>` represents the application's concept of a 'user' or 'account' - OAuth 2.0 terminology would refer to this type as a *resource owner*.

The type argument must be a `ManagedObject<T>` subclass that is specific to your application. Its persistent type *must extend* `ManagedAuthenticatable` and the instance type must implement `ManagedAuthResourceOwner`. A basic definition may look like this:

```dart
class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner {
}

class _User extends ManagedAuthenticatable {
  @Column(unique: true)
  String email;
}
```

By extending `ManagedAuthenticatable`, the database table has the following four columns:

- an integer primary key named `id`
- a unique string `username`
- a password hash
- a salt used to generate the password hash

A `ManagedAuthenticatable` also has a `ManagedSet` of `tokens` for each token that has been granted on its behalf.

The interface `ManagedAuthResourceOwner` is a requirement that ensures the type argument is both a `ManagedObject<T>` and `ManagedAuthenticatable`, and serves no other purpose than to restrict `ManagedAuthDelegate<T>`'s type parameter.

This structure allows an application to declare its own 'user' type while still enforcing the needs of Aqueduct's OAuth 2.0 implementation.

The `managed_auth` library also declares two `ManagedObject<T>` subclasses. `ManagedAuthToken` represents instances of authorization tokens and codes, and `ManagedAuthClient` represents instances of OAuth 2.0 clients. This means that an Aqueduct application that uses `ManagedAuthDelegate<T>` has a minimum of three database tables: users, tokens and clients.

`ManagedAuthDelegate<T>` will delete authorization tokens and codes when they are no longer in use. This is determined by how many tokens a resource owner has and the tokens expiration dates. Once a resource owner acquires more than 40 tokens/codes, the oldest tokens/codes (determined by expiration date) are deleted. Effectively, the resource owner is limited to 40 tokens. This number can be changed when instantiating `ManagedAuthDelegate<T>`:

```dart
final delegate = new ManagedAuthDelegate(context, tokenLimit: 20);
```

## Configuring the Database

`ManagedAuthDelegate<T>` requires database tables for its users, tokens and clients. Use the [database command-line tool](../db/db_tools.md) on your project to generate migration scripts and execute them against a database. This tool will see the declarations for your user type, `ManagedAuthToken` and `ManagedAuthClient` and create the appropriate tables.
