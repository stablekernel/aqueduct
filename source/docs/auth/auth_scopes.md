# Granular Authorization with OAuth 2.0 Scopes

In many applications, operations have varying levels of access control. For example, a user may need special permission to create 'notes', but every user can read notes. In OAuth 2.0, permissions for operations are determined by an access token's *scope*. Operations can be defined to require certain scopes, and a request may only invoke those operations if its access token was granted with those scopes.

A scope is a string identifier, like `notes` or `notes.readonly`. When a client application authenticates on behalf of a user, it requests one or more of these scope identifiers to be granted to the access token. Valid scopes will be stored with the access token, so that the scope can be referenced by subsequent uses of the access token.

# Scope Usage in Aqueduct

An access token's scope is determined when a user authenticates. During authentication, a client application indicates the requested scope, and the Aqueduct application determines if that scope is permissible for the client application and the user. This scope information is attached to the access token.

When a request is made with an access token, an `Authorizer` retrieves the token's scope. After the request is validated, the `Authorizer` stores scope information in `Request.authorization`. Linked controllers can use this information to determine how the request is handled. In general, a controller will reject a request and send a 403 Forbidden response when an access token has insufficient scope for an operation.

Therefore, adding scopes to an application consists of three steps:

1. Adding scope restrictions to operations.
2. Adding permissible scopes for OAuth2 client identifiers (and optionally users).
3. Updating client applications to request scope when authenticating.

## Adding Scope Restrictions to Operations  

When an `Authorizer` handles a request with an access token, it creates an `Authorization` object that is attached to the request. An `Authorization` object has a `scopes` property that contains every scope granted for the access token. It also has a convenience method for checking if a particular scope is valid for that list of scopes:

```dart
class NoteController extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    if (!request.authorization.authorizedForScope("notes")) {
      return new Response.forbidden();
    }

    return new Response.ok(await getAllNotes());
  }
}
```

!!! warning "Use an Authorizer"
    The `authorization` property of `Request` is only valid after the request is handled by an `Authorizer`. It is `null` otherwise.

An `Authorizer` may also validate the scope of a request before letting it pass to its linked controller.

```dart
router
  .route('/notes')
  .link(() => new Authorizer.bearer(authServer, scopes: ['notes']))
  .link(() => new NoteController());
```

In the above, the `NoteController` will only be reached if the request's bearer token has 'notes' scope. If there is insufficient scope, a 403 Forbidden response is sent. This applies to all operations of the `NoteController`.

It often makes sense to have separate scope for different operations on the same resource. The `Scope` annotation may be added to `ResourceController` operation methods for this purpose.

```dart
class NoteController extends ResourceController {
  @Scope(['notes.readonly'])
  @Operation.get()
  Future<Response> getNotes() async => ...;

  @Scope(['notes'])
  @Operation.post()
  Future<Response> createNote(@Bind.body() Note note) async => ...;
}
```

If a request does not have sufficient scope for the intended operation method, a 403 Forbidden response is sent. When using `Scope` annotations, you must link an `Authorizer` prior to the `ResourceController`, but it is not necessary to specify `Authorizer` scopes.  

If a `Scope` annotation or `Authorizer` contains multiple scope entries, an access token must have scope for each of those entries. For example, the annotation `@Scope(['notes', 'user'])` requires an access token to have both 'notes' and 'user' scope.

## Defining Permissible Scope

When a client application authenticates on behalf of a user, it includes a list of request scopes for the access token. An Aqueduct application will grant the requested scopes to the  token if the scopes are permissible for both the authenticating client identifier and the authenticating user.

To add permissible scopes to an authenticating client, you use the `aqueduct auth` command-line tool. When creating a new client identifier, include the `--allowed-scopes` options:

```bash
aqueduct auth add-client \
  --id com.app.mobile \
  --secret myspecialsecret \
  --allowed-scopes 'notes users' \
  --connect postgres://user:password@dbhost:5432/db_name
```

When modifying an existing client identifier, use the command `aqueduct auth set-scope`:

```bash
aqueduct auth set-scope \
  --id com.app.mobile \
  --scopes 'notes users' \
  --connect postgres://user:password@dbhost:5432/db_name
```

Each scope is a space-delimited string; the above examples allow clients authenticating with the `com.app.mobile` client ID to grant access tokens with 'notes' and 'users' scope. If a client application requests scopes that are not available for that client application, the granted access token will not contain that scope. If none of the request scopes are available for the client identifier, no access token is granted. When adding scope restrictions to your application, you must ensure that all of the client applications that have access to those operations are able to grant that scope.

Scopes may also be limited by some attribute of your application's concept of a 'user'. This user-level filtering is done by overriding `allowedScopesForAuthenticatable` in `AuthDelegate`. By default, this method returns `AuthScope.Any` - which means there are no restrictions. If the client application allows the scope, then any user that logs in with that application can request that scope.

This method may return a list of `AuthScope`s that are valid for the authenticating user. The following example shows a `ManagedAuthDelegate<T>` subclass that allows any scope for `@stablekernel.com` usernames, no scopes for `@hotmail.com` addresses and some limited scope for everyone else:

```dart
class DomainBasedAuthDelegate extends ManagedAuthDelegate<User> {
  DomainBasedAuthDelegate(ManagedContext context, {int tokenLimit: 40}) :
        super(context, tokenLimit: tokenLimit);

  @override
  List<AuthScope> allowedScopesForAuthenticatable(covariant User user) {
    if (user.username.endsWith("@stablekernel.com")) {
      return AuthScope.Any;
    } else if (user.username.endsWith("@hotmail.com")) {
      return [];
    } else {
      return [new AuthScope("user")];
    }
  }      
}
```

The `user` passed to `allowedScopesForAuthenticatable` is the user being authenticated. It will have previously been fetched by the `AuthServer`. The `AuthServer` fetches this object by invoking `AuthDelegate.fetchAuthenticatableByUsername()`. The default implementation of this method for `ManagedAuthDelegate<T>` only fetches the `id`, `username`, `salt` and `hashedPassword` of the user.

When using some other attribute of an application's user object to restrict allowed scopes, you must also override `fetchAuthenticatableByUsername` to fetch these attributes. For example, if your application's user has a `role` attribute, you must fetch it and the other four required properties. Here's an example implementation:

```dart
class RoleBasedAuthDelegate extends ManagedAuthDelegate<User> {
  RoleBasedAuthDelegate(ManagedContext context, {int tokenLimit: 40}) :
        super(context, tokenLimit: tokenLimit);

  @override
  Future<User> fetchAuthenticatableByUsername(
      AuthServer server, String username) {
    var query = new Query<User>(context)
      ..where.username = whereEqualTo(username)
      ..returningProperties((t) =>
        [t.id, t.username, t.hashedPassword, t.salt, t.role]);

    return query.fetchOne();
  }

  @override
  List<AuthScope> allowedScopesForAuthenticatable(covariant User user) {
    var scopeStrings = [];
    if (user.role == "admin") {
      scopeStrings = ["admin", "user"];
    } else if (user.role == "user") {
      scopeStrings = ["user:email"];
    }

    return scopeStrings.map((str) => new AuthScope(str)).toList();
  }
}
```

## Client Application Integration

Client applications that integrate with your scoped Aqueduct application must include a list of requested scopes when performing authentication. When authenticating through `AuthController`, a `scope` parameter must be added to the form data body. This parameter's value must be a space-delimited, URL-encoded list of requested scopes.

```
username=bob&password=foo&grant_type=password&scope=notes%20users
```

When authenticating via an `AuthCodeController`, this same query parameter is added to the initial `GET` request to render the login form.

When authentication is complete, the list of granted scopes will be available in the JSON response body as a space-delimited string.

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "bearer",
  "expires_in": 3600,
  "scopes": "notes users"
}
```

# Scope Format and Hierarchy

There is no definitive guide on what a scope string should look like, other than being restricted to alphanumeric characters and some symbols. Aqueduct, however, provides a simple scoping structure - there are two special symbols, `:` and `.`.

Hierarchy is specified by the `:` character. For example, the following is a hierarchy of scopes related to a user and its sub-resources:

- `user` (can read/write everything a user has)
- `user:email` (can read/write a user's email)
- `user:documents` (can read/write a user's documents)
- `user:documents:spreadsheets` (can read/write a user's spreadsheet documents)

Notice how these scopes form a hierarchy. Each segment makes the scope more restrictive. For example, if an access token has `user:email` scope, it only allows access to a user's email. However, if the access token has `user` scope, it allows access to everything a user has, including their email.

As another example, an access token with `user:documents` scope can access all of a user's documents, but the scope `user:documents:spreadsheets` is limited to only spreadsheet documents.

Scope is often used to indicate read vs. write access. At first glance, it might sound like a good idea to use the hierarchy operator, e.g. `user:email:read` and `user:email:write`. However, an access token with `user:email:write` *does not* have permission to read email and this is likely unintended.

This is where *scope modifiers* come in. A scope modifier adds a

A scope modifier is added after a `.` at the end of a scope string. For example, `user:email.readonly` grants readonly access to a user's email whereas `user:email` grants read and write access.

An access token without a modifier has permission *any* modifier. Thus, `user` and `user:email` can both access `user:email.readonly` protected resources and actions, but `user:email.readonly` cannot access resources protected by `user:email`.

A scope modifier is only valid for the last segment of a scope string. That is, `user:documents.readonly:spreadsheets` is not valid, but `user:documents:spreadsheets.readonly` is.
