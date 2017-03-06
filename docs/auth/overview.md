## Tasks

Aqueduct has built-in classes to manage authentication and authorization according to the [OAuth 2.0 specification](https://tools.ietf.org/html/rfc6749).  To manage authentication and authorization, the following tasks are required/suggested:

- Creating `AuthServer` instances to enable OAuth 2.0 in an Aqueduct application
- Using `aqueduct/managed_auth` to manage storage of authorization objects, e.g. storing tokens in a database.
- Using `AuthCodeController` and `AuthController` to expose endpoints for exchanging credentials for authorization tokens.
- Adding `Authorizer`s to a series of `RequestController`s to allow only authorized requests.
- Creating OAuth 2.0 Client Identifiers through the `aqueduct auth` tool

![Authorization Objects](../img/authobjects.png)

## Guides

- [What is OAuth 2.0?](what_is_oauth.md)
- [Creating and Using AuthServers](server.md)
- [Securing Routes with Authorizer](authorizer.md)
- [Adding Auth Endpoints](controllers.md)
- [Creating OAuth 2.0 Client IDs](cli.md)
