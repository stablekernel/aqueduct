# Granular Authorization with OAuth 2.0 Scopes

A simple Aqueduct Auth implementation grants access tokens and protects resources by ensuring a request has a valid access token. As an application grows, it may need more granular protection than simply, "Oh, you have a token? Ok, access whatever you want!" For example, an ordinary user shouldn't be able to access administration resources.

One approach to granular authorization is using *roles*. A role - like `admin` and `user` - exist in a hierarchical model for granting permission. An `admin` can access everything a `user` can and more. This approach is a valid part of a granular authorization scheme, but a simple `admin > user` model falls apart as permissions diverge. Likewise, it is difficult to integrate third party applications that should only have access to a subset of a user's data.

For example, Google offers lots of services - from email, to analytics data, to document hosting - all of this is accessible to users identified by their Gmail address. These services have their own application, and third party applications may access these services on behalf of the user. As a user, I do not want an third-party application that presents my documents from Google Drive to also have access my email. But I still want to login to both services with the same email and password.

OAuth 2.0 solves this problem with *scope*. A scope is a string that identifies access to some resource or action. For example, the scope to read, send and delete your email might be simply called "gmail". But another scope, "gmail.readonly", can only read email - it can't send or delete it. Likewise, the "analytics" scope may let me read analytic data for my websites, but it'll never see my email, much less send one.

Scope is different than a role because it belongs to the access token, not the user. A user can have multiple access tokens for different applications, each with different scope and therefore different access control.

## Scope Format and Hierarchy

There is no definitive guide on what a scope string should look like, other than being restricted to alphanumeric characters and some symbols. Aqueduct, however, imposes a simple scoping structure.

Hierarchy is specified by the `:` character. For example, the following is a hierarchy of scopes related to a user and its belongings:

- `user`
- `user:email`
- `user:documents`
- `user:documents:spreadsheets`

Notice how these scopes form a hierarchy. Each segment makes the scope more restrictive. A scope that begins with the same segments has access to a scope with more segments, e.g. `user:documents` has access to `user:documents:spreadsheets`, but `user:documents` cannot access `user:email`. The `user` scope can access email, documents and anything else a user might have.

Scopes are validated by the method `Authorization.authorizedForScope()`. Once a `Request` passes through an `Authorizer`, it will have a valid `authorization` property. If the access token has scopes, this method can be used to ensure it has the appropriate scope for the resource or action. For example, the following will verify that a request has at least `user:email` access - either `user:email` *or* the `user` scope.

```dart
@Operation.get()
Future<Response> getInbox() async {
  if (!request.authorization.authorizedForScope("user:email")) {
    return new Response.unauthorized();
  }

  ...
}
```

It is often the case where a scope might have further restrictions - like readonly vs. write. You may introduce scopes like `user:email:read` and `user:email:write`, but `user:email:write` would not have access to `user:email:read` following the previous logic.

This is where *scope modifiers* come in. A scope modifier is a `.`-prefixed string at the end of a scope. For example, `user:email.readonly` grants readonly access to a user's email. An access token without a modifier has access to a scope with the same hierarchy and *any* modifier. Thus, `user` and `user:email` can both access `user:email.readonly` protected resources and actions, but `user:email.readonly` cannot access things protected by `user:email`.

A scope modifier is only valid for the last segment of a scope string. That is, `user:documents.readonly:spreadsheets` is not valid, but `user:documents:spreadsheets.readonly` is.

## Requesting Scope

Scope is requested by a client application when it is authenticating a user. For example, the form data to request the `user:email` scope on behalf of `bob@stablekernel.com` looks like this:

`username=bob@stablekernel.com&password=foobarxyz123&grant_type=password&scope=user:email`

Multiple scopes can be requested for an access token, which *must* be separated by spaces. (Note these query parameters must be percent-encoded, but are shown here without percent-encoding to aid visibility.)

`username=bob@stablekernel.com&password=foobarxyz123&grant_type=password&scope=user:email user:documents`

When using the authorization code flow, the requested scope is provided by the third party application in the query string of the initial `GET /auth/code`:

`GET /auth/code?grant_type=code&client_id=com.foo.bar&state=k3j4kjas&scope=user:email`

The webpage served by from this endpoint should alert the user to the scopes the application is requesting.

## Adding and Managing Scope

An `AuthServer` validates that the scopes requested for an access token are valid for the authenticating client application. Therefore, each client identifier (a `ManagedAuthClient`) may have a list of allowed scopes. The allowed scopes are configured with the [aqueduct auth command-line tool](cli.md). For example, the following creates a new client identifier with access to the scopes `user:email` and `user:documents`, and then later adds `user:location`:

```bash
aqueduct auth add-client \
  --id com.app.mobile \
  --secret myspecialsecret \
  --allowed-scopes 'user:email user:documents' \
  --connect postgres://user:password@dbhost:5432/db_name

aqueduct auth set-scope \
  --id com.app.mobile \
  --scopes 'user:email user:documents user:location' \
  --connect postgres://user:password@dbhost:5432/db_name
```

Once a client has scopes, any access token request from this client *must* contain a list of desired scopes. Aqueduct does not implicitly grant scopes when a request omits them.

The `AuthServer` will only grant scopes that the client has access to. If some of the scopes in a request aren't valid for the client, the token may still be granted, but any disallowed scopes will be removed. For example, requesting the scopes `user:email` and `user:settings` would return an access token that only granted `user:email`:

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "bearer",
  "expires_in": 3600,
  "scopes": "user:email"
}
```


If none of the requested scopes are allowed, the access token will *not* be granted and the request will yield an error response.

If the client identifier has not been configured with scopes - either because the application doesn't use scopes or this particular client doesn't have any - scopes specified in an authenticating request are ignored. A token will be granted in this scenario, but will have no scope. The `scope` key is omitted from the token payload.

It is important to ensure that an application that uses scope has protections on its resources (see [a later section](#using-scope-to-protect-resources)).

### User-based Scope Management

Adding scopes to client identifiers is a requirement for any application that wishes to use scoping. An application may optionally add restrictions to scope depending on some attribute(s) of the user. When authenticating, the server first filters the list of requested scopes by what is allowed for the client, and then filters the resulting list by what is allowed for the user.

This user-level filtering is done by overriding `allowedScopesForAuthenticatable` in `AuthStorage`. By default, this method returns `AuthScope.Any` - which means there are no restrictions. If the client application allows the scope, then any user that logs in with that application can request that scope.

This method may return a list of `AuthScope`s that are valid for the authenticating user. The following example shows a `ManagedAuthStorage<T>` subclass that allows any scope for `@stablekernel.com` usernames, no scopes for `@hotmail.com` addresses and some limited scope for everyone else:

```dart
class DomainBasedAuthStorage extends ManagedAuthStorage<User> {
  DomainBasedAuthStorage(ManagedContext context, {int tokenLimit: 40}) :
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

The `user` passed to `allowedScopesForAuthenticatable` is the user being authenticated. It will have previously been fetched by the `AuthServer`. The `AuthServer` fetches this object by invoking `AuthStorage.fetchAuthenticatableByUsername()`. The default implementation of this method for `ManagedAuthStorage<T>` only fetches the `id`, `username`, `salt` and `hashedPassword` of the user. This is for two reasons:

- These properties are needed to verify and grant an access token.
- The `AuthServer` can only guarantee that the `User` implements `Authenticatable`, and those are the only properties it has.

When using some other attribute of an application's user object to restrict allowed scopes, you must also override `fetchAuthenticatableByUsername` to fetch these attributes. For example, if your application's user has a `role` attribute, you must fetch it and the other four required properties. Here's an example implementation:

```dart
class RoleBasedAuthStorage extends ManagedAuthStorage<User> {
  RoleBasedAuthStorage(ManagedContext context, {int tokenLimit: 40}) :
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

If you do not fetch the four required properties declared in `Authenticatable`, an `AuthServer` will fail in spectacular ways.

## Using Scope to Protect Resources

An `Authorizer.bearer()` can require an access token to have certain scopes before passing it down the channel:

```dart
router
  .route("/email_attachments")
  .pipe(new Authorizer.bearer(authServer, scopes: ["user:email", "user:documents"]))
  .generate(() => new SecureStuffController());
```

A request's token must have all of the scopes declared by the `Authorizer` - in this case, *both* "user:email" and "user:documents" (or "user", of course).

This type of protection is often useful, but within a particular controller you may want finer control. For example, you may want to require a different level of access to `POST` than `GET`. You may check if an authorization has valid scopes at any time:

```dart
class EmailController extend RESTController {
  @Operation.get()
  Future<Response> getEmail() async {
    if (!request.authorization.authorizedForScope("user:email.readonly")) {
      return new Response.unauthorized();
    }

    var inbox = await emailForUser(request.authorization.resourceOwnerIdentifier);
    return new Response.ok(inbox);
  }

  @Operation.post()
  Future<Response> sendEmail(@Bind.body() Email email) async {
    if (!request.authorization.authorizedForScope("user:email")) {
      return new Response.unauthorized();
    }
    await sendEmail(email);

    return new Response.accepted();
  }
}
```

Note that scopes are not the only way to secure resources, even if they are being used. For example, you may want to restrict the endpoint `/user/1/settings` to only allow the user with `id=1` to access it:

```dart
@Operation.get('id')
Future<Response> getUserSettings(@Bind.path('id') int id) async {
  if (request.authorization.resourceOwnerIdentifier != id) {
    return new Response.unauthorized();
  }

  return new Response.ok(await settingsForUser(id));
}
```
