# Manage OAuth 2.0 Clients

The `aqueduct auth` command line tool creates OAuth 2.0 client application identifiers and inserts them into an application's database. To use this tool, you must use `ManagedAuthDelegate<T>` and
your database must be contain the tables to support it (see [this guide](server.md) for more details).

Exchanging a username and password for an authorization token requires a registered client identifier. A token belongs to both the authenticating user and the client application. Clients are represented by instances of `ManagedAuthClient` from `aqueduct/managed_auth`. Authenticating clients must provide their client ID (and client secret, if applicable) in the Authorization header when requesting access tokens.

An OAuth 2.0 client must have a string identifier that uniquely identifies the client. For example, `com.food_app.mobile` may be a client identifier for the mobile applications for some 'Food App'.

To create a simple OAuth 2.0 client, the following command line utility can be run:

```
aqueduct auth add-client \
  --id com.food_app.mobile \
  --connect postgres://user:password@dbhost:5432/food_app
```

The `connect` option identifies the database for the application, which this tool will connect to and insert a record into the `ManagedAuthClient` database table. The identifier is provided through the `id` option.

An OAuth 2.0 client created in this way is a *public* client; there is no client secret. An OAuth 2.0 client that uses the resource owner grant flow, but cannot secure its client secret, should use this type of client. An application can't secure its client secret if its source code is viewable - like any JavaScript application. It is suggested that native mobile applications also use public clients because their source code could potentially be disassembled to reveal a client secret, but isn't necessarily required.

When making requests to client authenticated endpoints (those protected with `Authorizer.basic`), the client secret is omitted from the authorization header. The string to base64 encode is `clientID:`, where the colon (`:`) is required. For example, to generate an authorization header in Dart for a public client:

```
var clientID = "com.foobar.xyz";
var clientCredentials = Base64Encoder().convert("$clientID:".codeUnits);
var header = "Basic $clientCredentials";
```

## Confidential Clients

An OAuth 2.0 client is *confidential* if it has a client secret. Client secrets can be provided with the `auth` tool:

```
aqueduct auth add-client \
  --id com.food_app.mobile \
  --secret myspecialsecret \
  --connect postgres://user:password@dbhost:5432/food_app
```

Client secrets are hashed (many times) with a randomly generated salt before they are stored. Therefore, their actual value must be stored securely elsewhere. (We use LastPass, for example.)

## Redirect URIs

To allow the authorization code flow (provided by `AuthCodeController`), a client must have a redirect URI. This is the URI that an authenticating user's browser will be redirected to after entering their username and password. A client must be a confidential client to have a redirect URI.

```
aqueduct auth add-client \
  --id com.food_app.mobile \
  --secret myspecialsecret \
  --redirect-uri https://someapp.com/callback \
  --connect postgres://user:password@dbhost:5432/food_app
```

## Scopes

If an application is using OAuth 2.0 scopes, a client can have scopes that it allows tokens to have access to. This allows scopes to be restricted by the client they are authenticating with.

```
aqueduct auth add-client \
  --id com.food_app.mobile \
  --secret myspecialsecret \
  --allowed-scopes 'scopeA scopeB scopeC.readonly' \
  --connect postgres://user:password@dbhost:5432/food_app
```

Scopes are space-delimited and must be enclosed in quotes so that your shell will treat the entire string as one value.

Scope may be set after a client has already been created with `aqueduct auth set-scope`:

```
aqueduct auth set-scope \
  --id com.food_app.mobile \
  --scopes 'scopeA scopeC' \
  --connect postgres://user:password@dbhost:5432/food_app
```

## Other Info

Like all `aqueduct` commands that send commands to a database, the `connect` option can be replaced by a `database.yaml` file in the project directory with the following format:

```
username: "user"
password: "password"
host: "host"
port: 5432
databaseName: "my_app"
```
