# aqueduct changelog

## 2.0.1

- Fixes issue where some types of join queries would access the wrong properties
- Fixes issue where an object cannot be inserted without values; this matters when the inserted values will be created by the database.

## 2.0.0

- Added `RequestController.letUncaughtExceptionsEscape` for better debugging during tests.
- Persistent types for `ManagedObject`s can now have superclasses.
- `ManagedRelationship`s now have a `.deferred()` constructor. This allows `ManagedObject`s to have relationships to `ManagedObject`s in other packages.
- Added `RequestSink.initializeApplication` method to do one-time startup tasks that were previously done in a start script.
- `RequestSink` constructor now takes `ApplicationConfiguration`, instead of `Map`.
- Added `configurationFilePath` to `ApplicationConfiguration`.
- Improved error reporting from failed application startups.
- Automatically lowercase headers in `Response` objects so that other parts of an application can accurately read their values during processing.
- Added `HTTPBody` object to represent HTTP request bodies in `Request`. Decoders are now added to this type.


- ORM: Renamed `Query.matchOn` to `Query.where`.
- ORM: Removed `includeInResultSet` for `Query`'s, instead, added `joinOn` and `joinMany` which create subqueries that can be configured further.
- ORM: Allow `Query.where` to reference properties in related objects without including related objects in results, i.e. can fetch `Parent` objects and filter them by values in their `Child` relationships.
- ORM: Joins can now be applied to belongsTo relationship properties.
- ORM: Matchers such as `whereNull` and `whereNotNull` can be applied to a relationship property in `Query.where`.
- ORM: Renamed `ManagedSet.matchOn` to `ManagedSet.haveAtLeastOneWhere`.
- ORM: Added matchers for case-insensitive string matching, and added case-insensitive option to `whereEquals` and `whereNotEquals`.

- Auth: Added `aqueduct/managed_auth` library. Implements storage of OAuth 2.0 tokens using `ManagedObject`s. See API reference for more details.
- Auth: Improved error and response messaging to better align with the OAuth 2.0 spec, especially with regards to the authorization code flow.
- Auth: Added distinction between public and confidential clients, as defined by OAuth 2.0 spec.
- Auth: Improved class and property naming.

- Tooling: Added `aqueduct auth` tool to create client ID and secrets and add them to a database for applications using the `aqueduct/managed_auth` package.
- Tooling: Added more user-friendly configuration options for `aqueduct db` tool.
- Tooling: Added `aqueduct setup --heroku` for setting up projects to be deployed to Heroku.
- Tooling: Added `aqueduct serve` command for running Aqueduct applications without having to write a start script.
- Tooling: Added `aqueduct document` command to generate OpenAPI specification for Aqueduct applications, instead of relying on a script that came with the template.


## 1.0.4
- BREAKING CHANGE: Added new `Response.contentType` property. Adding "Content-Type" to the headers of a `Response` no longer has any effect; use this property instead.
- `ManagedDataModel`s now scan all libraries for `ManagedObject<T>` subclasses to generate a data model. Use `ManagedDataModel.fromCurrentMirrorSystem` to create instances of `ManagedDataModel`.
- The *last* instantiated `ManagedContext` now becomes the `ManagedContext.defaultContext`; prior to this change, it was the first instantiated context. Added `ManagedContext.standalone` to opt out of setting the default context.
- @HTTPQuery parameters in HTTPController responder method will now only allow multiple keys in the query string if and only if the argument type is a List.

## 1.0.3
- Fix to allow Windows user to use `aqueduct setup`.
- Fix to CORS processing.
- HTTPControllers now return 405 if there is no responder method match for a request.

## 1.0.2
- Fix type checking for transient map and list properties of ManagedObject.
- Add flags to `Process.runSync` that allow Windows user to use `aqueduct` executable.

## 1.0.1
- Change behavior of isolate supervision. If an isolate has an uncaught exception, it logs the exception but does not restart the isolate.

## 1.0.0
- Initial stable release.
