# Migration from Aqueduct 2 to Aqueduct 3.0

Aqueduct 3 makes a number of breaking changes from Aqueduct 2. Some of these changes are changes to behavior, and others are simple API renaming. This guide demonstrates the changes required for commonly used code.

## RequestSink is now ApplicationChannel

This type has been renamed to `ApplicationChannel` and its methods for initializing an application have changed. The method `setupRouter` has been replaced by the getter `entryPoint`. All controller creating code should be located in this getter, and you must now create the `Router` yourself if you choose to. Additionally, the methods to link together controllers (e.g., `generate`, `pipe`) have been replaced with the `link` method, which always takes a closure.

```dart
class Channel extends ApplicationChannel {
  Service service;

  @override
  Future prepare() async {
    service = Service(options.context["service"]);
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.link(() => MyController(service));
    return router;
  }
}
```

The object returned by this getter is the first controller to receive a request, and does not have to be a router (e.g., it could be global middleware). By default, the closure provided to `link` is invoked once at startup and the same controller instance is reused for all requests. If a `Controller` implements `Recyclable<T>`, the closure is invoke for each new request and a new controller is created to handle the request.

You are no longer required to implement a constructor for `ApplicationChannel`. All of your initialization should be provided by overriding `prepare` in your channel. You will have access to configuration data through an `options` property in both `prepare` and `entryPoint`.

## HTTPController is now ResourceController

The name of this type has changed, and the syntax for identifying operation methods and binding values has improved.

```dart
class MyController extends ResourceController {
  @Operation.get()
  Future<Response> getAll({@Bind.query("filter") String filter}) async {
    ...
  }

  @Operation.put('id')
  Future<Response> updateThing(@Bind.path('id') int id, @Bind.body() Thing thing) async {
    ...    
  }
}
```

Operation methods must now be decorated an `Operation` annotation; this replaces metadata like `@httpGet`. For an operation method to match a request with path variables, the names of those path variables must be arguments to the `Operation` constructor. In previous versions, path variable methods were selected if the method's arguments bound a path variable. This is no longer the case - binding a path variable has no impact on the selection of a method, the path variable *must* be identified in the `Operation`. You no longer have to bind a path variable and can retrieve it through the `request.path`.

Bound parameters are identified by the `Bind` annotation, and the type of binding is identified by the constructor used. This syntax replaces `HTTPQuery.bind()`, etc.

## Query.where syntax has changed

Previously, query filters were applied by assigning expressions like `whereEqualTo` to properties of `Query.where`. This has been replaced with the property selector syntax that is used when joining, sorting or paging by a property.

```dart
final query = Query<User>()
  ..where((u) => u.id).equalTo(1);
```

Methods like `whereEqualTo` no longer exist - all expressions to apply to a selected property are instance methods of the object returned by `where`.

## Test library is now aqueduct_test

The test library is now a separate library named `aqueduct_test` and must be added to your `pubspec.yaml`. Much of its behavior has changed to make writing tests more effective. See the [documentation](testing/tests.md) for more details.

## Swagger -> OpenAPI

Aqueduct had experimental support for Swagger documentation generation. It now has full, tested support for OpenAPI 3 documentation generation. See the [documentation](openapi/index.md) for more details.

### Renames

The following common signatures are a non-exhaustive list of simple API renaming:

```
Authorization.resourceOwnerIdentifier -> Authorization.ownerID
Request.innerRequest -> Request.raw
AuthStorage -> AuthServerDelegate
AuthServer.storage -> AuthServer.delegate
ApplicationConfiguration -> ApplicationOptions
Application.configuration -> Application.options
ServiceRegistry -> ServiceRegistry
ManagedTableAttributes -> Table
ManagedRelationshipDeleteRule -> DeleteRule
ManagedRelationship -> Relate
ManagedColumnAttributes -> Column
managedPrimaryKey -> primaryKey
ManagedTransientAttribute -> Serialize
Serialize now replaces managedTransientAttribute, managedTransientInputAttribute, and managedTransientOutputAttribute.
RequestController -> Controller
RequestController.processRequest -> Controller.handle
HTTPController -> ResourceController
Router.unhandledRequestController -> Router.unmatchedController
```
