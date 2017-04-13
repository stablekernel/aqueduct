# Creating AuthServers to Authenticate and Authorize

An instance of `AuthServer` handles creating, verifying and refreshing authorization tokens. An instance of `AuthServer` is created when an application starts up and is referenced by `Authorizer`s, `AuthCodeController`s and `AuthController`s to manage authorization. `AuthServer` handles the logic of authorization, and when it needs to fetch or store persistent data, it invokes a callback on its `AuthStorage`. Therefore, an `AuthServer` must have `AuthStorage` to persist authorization objects like tokens, clients and resource owners.

## Creating Instances of AuthServer and AuthStorage

One instance of `AuthServer` is created in a `RequestSink`'s constructor along with its instance of `AuthStorage`. `AuthStorage` is an interface and a concrete implementation of it - `ManagedAuthStorage<T>` - exists in an optional library in Aqueduct, `aqueduct/managed_auth`. It is strongly recommended to use an instance of `ManagedAuthStorage<T>` because it has been thoroughly tested and handles cleaning up unused tokens.

`ManagedAuthStorage` declares and uses `ManagedObject`s to represent authorization objects. Therefore, it must have a reference to `ManagedContext` (see [Aqueduct ORM](../db/overview.md)). Initialization looks like this:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config) : super(config) {
    context = new ManagedContext(...);
    var storage = new ManagedAuthStorage<User>(context);
    authServer = new AuthServer(storage);
  }

  AuthServer authServer;
  ManagedContext context;

  ...
}
```

Notice that the `aqueduct/managed_auth` library is imported - this library is not part of `aqueduct/aqueduct` by default and must be imported explicitly. Also notice that `ManagedAuthStorage` has a type argument that will be covered in the next section.

It's important to keep a property reference to an instance of `AuthServer` so that later methods in the initialization process - specifically, `setupRouter` - can use it to protect routes and add routes that grant authorization tokens.

While `AuthServer` has methods for handling authorization tasks, it is rarely used directly. Instead, `AuthCodeController` and `AuthController` are hooked up to routes to grant authorization tokens via the API. Instances of `Authorizer` secure routes when building processing pipelines in `setupRouter`. All of these types have a reference to an `AuthServer` and invoke the appropriate methods to carry out their task.

Therefore, a full authorization implementation rarely extends past a `RequestSink`. Here's an example `RequestSink` subclass that sets up and uses authorization:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config) : super(config) {
    context = new ManagedContext(...);
    var storage = new ManagedAuthStorage<User>(context);
    authServer = new AuthServer(storage);
  }

  AuthServer authServer;
  ManagedContext context;

  void setupRouter(Router router) {
    // Set up auth token route
    router.route("/auth/token").generate(() => new AuthController(authServer));

    // Set up auth code route
    router.route("/auth/code").generate(() => new AuthCodeController(authServer));

    // Set up protected route
    router
      .route("/protected")
      .pipe(new Authorizer.bearer(authServer))
      .generate(() => new ProtectedController());
  }
}
```

For more details on authorization controllers, see [Authorization Controllers](controllers.md). For more details on securing routes, see [Authorizers](authorizer.md).

## Using ManagedAuthStorage

`ManagedAuthStorage<T>` is a concrete implementation of `AuthStorage`, providing storage of authorization tokens and clients for `AuthServer`. Storage is accomplished by Aqueduct's ORM. `ManagedAuthStorage<T>`, by default, is not part of the standard `aqueduct/aqueduct` library. To use this class, an application must import `package:aqueduct/managed_auth.dart`.

The type argument to `ManagedAuthStorage<T>` represents the concept of a 'user' or 'account' in an application - OAuth 2.0 terminology would refer to this concept as a *resource owner*.

The type argument must be a `ManagedObject<T>` subclass that is specific to your application. Its persistent type must *extend* `ManagedAuthenticatable` and the subclass itself must implement `ManagedAuthResourceOwner`. A basic definition may look like this:

```dart
class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner {
  @managedTransientInputAttribute
  void set password(String password) {
    salt = AuthUtility.generateRandomSalt();
    hashedPassword = AuthUtility.generatePasswordHash(password, salt);
  }
}

class _User extends ManagedAuthenticatable {
  @ManagedColumnAttributes(unique: true)
  String email;
}
```

By extending `ManagedAuthenticatable`, the persistent type has an integer primary key, a unique username, a hashed password (and its salt) and a `ManagedSet<T>` of authorization tokens that have been granted by this user. These are the necessary attributes that the type argument to `ManagedAuthStorage<T>` must have for an `AuthServer` to properly store and fetch resource owners. The interface `ManagedAuthResourceOwner` is a requirement that ensures the type argument is both a `ManagedObject<T>` and `ManagedAuthenticatable`, and serves no other purpose than to restrict `ManagedAuthStorage<T>`'s type parameter to an appropriate type.

The purpose of this structure is to allow an application to declare its own resource owner type - with additional attributes and relationships - while still enforcing the needs of Aqueduct's OAuth 2.0 implementation.

Once a resource owner has been defined, instances of `ManagedAuthStorage<T>` can be created and passed to an `AuthServer`:

```dart
var context = new ManagedContext(...);
var storage = new ManagedAuthStorage<User>(context);
var server = new AuthServer(storage);
```

The `aqueduct/managed_auth` library also declares two `ManagedObject<T>` subclasses. `ManagedToken` represents instances of authorization tokens and codes, and `ManagedClient` represents instances of OAuth 2.0 clients. Both of these types must be visible to the `aqueduct db` tool, and so the library must at least be imported in an application's library file. Since these types will at least be referenced by the definition of the resource owner, it makes sense to export `package:aqueduct/managed_auth.dart` from an application's library file. It's rare that these types are referenced elsewhere in an application, since they exist to serve the behavior of `AuthServer`.

`ManagedAuthStorage<T>` will delete authorization tokens and codes when they are no longer in use. This is determined by how many tokens a resource owner has and the tokens expiration dates. Once a resource owner acquires more than 40 tokens/codes, the oldest tokens/codes (determined by expiration date) are deleted. Effectively, the resource owner is limited to 40 tokens. This number can be changed when instantiating `ManagedAuthStorage<T>`:

```dart
var storage = new ManagedAuthStorage(context, tokenLimit: 20);
```
