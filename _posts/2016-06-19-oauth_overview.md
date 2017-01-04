---
layout: page
title: "Overview"
category: auth
date: 2016-06-19 21:22:35
order: 1
---

Aqueduct has built-in classes to manage authentication and authorization according to the [OAuth 2.0 specification](https://tools.ietf.org/html/rfc6749). Some of the major components related to this topic are:

- Creating `AuthServer` instances to handle the logic of authentication.
- Implementing `AuthDelegate` to manage storage of authorization artifacts, e.g. storing tokens in a database.
- Adding `Authorizer`s to a series of `RequestController`s to allow only appropriately authorized requests to be responded to.
- Storing passwords securely using PBKDF2.
- Parsing Authorization headers
- Using built-in `RequestController`s, `AuthCodeController` and `AuthController`, to expose endpoints for exchanging credentials for authorization tokens.

## Guides

- [Creating and Using AuthServers](auth_server.html)
- [Securing Routes with Authorizer](authorizer.html)
- [Controllers for Adding Auth Endpoints](auth_controllers.html)
- [Passwords and the Authorization Header](password_request.html)
