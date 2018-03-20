# Securing Routes with Authorizer

Instances of `Authorizer` are added to an application channel to verify HTTP request's authorization information before passing the request onwards. They protect channel access and typically come right after `route`. Here's an example:

```dart
@override
Controller get entryPoint {
  final router = Router();

  router
    .route("/protected")
    .link(() => Authorizer.bearer(authServer))
    .link(() => ProtectedController());

  router
    .route("/other")
    .link(() => Authorizer.basic(authServer))
    .link(() => OtherProtectedController());

  return router;
}
```

An `Authorizer` parses the Authorization header of an HTTP request. The named constructors of `Authorizer` indicate the required format of Authorization header. The `Authorization.bearer()` constructor expects an OAuth 2.0 bearer token in the header, which has the following format:

```
Authorization: Bearer 768iuzjkx82jkasjkd9z9
```

`Authorizer.basic` expects HTTP Basic Authentication, where the username and password are joined with the colon character (`:`) and Base 64-encoded:

```
// 'dXNlcjpwYXNzd29yZA==' is 'user:password'
Authorization: Basic dXNlcjpwYXNzd29yZA==
```

If the header can't be parsed, doesn't exist or is in the wrong format, an `Authorizer` responds to the request with a 401 status code and prevents the next controller from receiving the request.

Once parsed, an `Authorizer` sends the information - either the bearer token, or the username and password - to its `AuthServer` for verification. If the `AuthServer` rejects the authorization info, the `Authorizer` responds to the request with a 401 status code and prevents the next controller from receiving the request. Otherwise, the request continues to the next controller.

For `Authorizer.bearer`, the value in a request's header must be a valid, unexpired access token. These types of authorizers are used when an endpoint requires a logged in user.

For `Authorizer.basic` authorizers, credentials are verified by finding an OAuth 2.0 client identifier and ensuring its client secret matches. Routes with this type of authorizer are known as *client authenticated* routes. These types of authorizers are used when an endpoint requires a valid client application, but not a logged in user.

### Authorizer and OAuth 2.0 Scope

An `Authorizer` may restrict access to controllers based on the scope of the request's bearer token. By default, an `Authorizer.bearer` allows any valid bearer token to pass through it. If desired, an `Authorizer` is initialized with a list of required scopes. A request may only pass the `Authorizer` if it has access to *all* scopes listed in the `Authorizer`. For example, the following requires at least `user:posts` and `location` scope:

```dart
router
  .route("/checkin")
  .link(() => Authorizer.bearer(authServer, scopes: ["user:posts", "location"]))
  .link(() => CheckInController());
```

Note that you don't have to use an `Authorizer` to restrict access based on scope. A controller has access to scope information after the request has passed through an `Authorizer`, so it can use the scope to make more granular authorization decisions.

### Authorization Objects

A bearer token represents a granted authorization - at some point in the past, a user provided their credentials and the token is the proof of that. When a bearer token is sent in the authorization header of an HTTP request, the application can look up which user the token is for and the client application it was issued for. This information is stored in an instance of `Authorization` after the token has been verified and is assigned to `Request.authorization`.

Controllers protected by an `Authorizer` can access this information to further determine their behavior. For example, a social networking application might have a `/news_feed` endpoint protected by an `Authorizer`. When an authenticated user makes a request for `/news_feed`, the controller will return that user's news feed. It can determine this by using the `Authorization`:

```dart
class NewsFeedController extends ResourceController {
  NewsFeedController(this.context);

  ManagedContext context;

  @Operation.get()
  Future<Response> getNewsFeed() async {
    var forUserID = request.authorization.resourceOwnerIdentifier;

    var query = Query<Post>(context)
      ..where((p) => p.author).identifiedBy(forUserID);

    return Response.ok(await query.fetch());
  }
}
```

In the above controller, it's impossible for a user to access another user's posts.

`Authorization` objects also retain the scope of an access token so that a controller can make more granular decisions about the information/action in the endpoint. Checking whether an `Authorization` has access to a particular scope is accomplished by either looking at the list of its `scopes` or using `authorizedForScope`:

```dart
class NewsFeedController extends ResourceController {
  NewsFeedController(this.context);

  ManagedContext context;

  @Operation.get()
  Future<Response> getNewsFeed() async {
    if (!request.authorization.authorizedForScope("user:feed")) {
      return Response.unauthorized();
    }

    var forUserID = request.authorization.resourceOwnerIdentifier;

    var query = Query<Post>(context)
      ..where((p) => p.author).identifiedBy(forUserID);

    return Response.ok(await query.fetch());
  }
}
```

### Using Authorizers Without AuthServer

Throughout this guide, the argument to an instance of `Authorizer` has been referred to as an `AuthServer`. This is true - but only because `AuthServer` implements `AuthValidator`. `AuthValidator` is an interface for verifying bearer tokens and username/password credentials.

You may use `Authorizer` without using `AuthServer`. For example, an application that doesn't use OAuth 2.0 could provide its own `AuthValidator` interface to simply verify the username and password of every request:

```dart
class BasicValidator implements AuthValidator {
  @override
  FutureOr<Authorization> validate<T>(AuthorizationParser<T> parser, T authorizationData, {List<AuthScope> requiredScope}) {}
    var user = await userForName(usernameAndPassword.username);
    if (user.password == hash(usernameAndPassword.password, user.salt)) {
      return Authorization(...);
    }

    // Will end up creating a 401 Not Authorized Response
    return null;
  }
}
```

The `validate` method must return an `Authorization` if the credentials are valid, or null if they are not. The `parser` lets the validator know the format of the Authorization header (e.g., 'Basic' or 'Bearer') and `authorizationData` is the meaningful information in that header. There are two concrete types of `AuthorizationParser<T>`: `AuthorizationBasicParser` and `AuthorizationBearerParser`. The authorization data for a basic parser is an instance of `AuthBasicCredentials` that contain the username and password, while the bearer parser's authorization data is the bearer token string.
