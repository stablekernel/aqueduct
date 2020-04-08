## 3.3.0-b1

- Adds 'aqueduct build' command that generates an executable binary of an Aqueduct app, with some known issues
    - Windows is not currently supported.
    - Compilation will fail for files that import relative URIs and declare at least one type that is a subclass of any of `ManagedObject`, `ApplicationChannel`, `Controller`, `ResourceController`, `Configuration`.
        - Convert relative URI imports to package imports to resolve.
    - Body decoding behaviors such as `RequestBody.as<T>` `RequestBody.decode<T>` have restrictions when running in compiled mode:
        - The type parameter `T` may be any of the five primitive types `int`, `double`, `num`, `String`, `bool`; `Map<String, T>` where `T` is a primitive, and `List<T>` where `T` is a primitive or `Map<String, dynamic>`.
        - These restrictions apply to the type of a `@Bind.body` parameter (you may also bind `Serializable` and `List<Serializable>`).

## 3.2.2-dev

- [#723](https://github.com/stablekernel/aqueduct/pull/723) Fixes issue that prevented the `AuthServer` from granting tokens with sub-scopes when the servers `AuthServerDelegate.getAllowedScopes()` didn't return `AuthScope.any`.
- Deprecates `AuthScope.allowsScope()`, use `AuthScope.isSubsetOrEqualTo()` instead.

## 3.2.1

- Fixes issue when using `QueryReduce` inside a transaction.
- Fixes issue when generating an OpenAPI document with ManagedObjects that have enumerated properties
- Fixes issue when generating an OpenAPI document with List<Serializable> bound to a request body

## 3.2.0

- Adds `read` method to `Serializable` for filtering, ignoring or rejecting keys.
- Fixes issues with Dart 2.1.1 mirror type checking changes
- Adds `like` matcher expression
- Escapes postgres special characters in LIKE expressions for all other string matcher expressions
- Fixes security vulnerability where a specific authorization header value would be associated with the wrong token in rare cases (credit to Philipp Schiffmann)
- Adds `Validate.constant` to properties that use the `@primaryKey` annotation.
- Allows `Validate` annotations to be added to belongs-to relationship properties; the validation is run on the foreign key.
- Allows any type - e.g. `Map<String, dynamic>` - to be bound with `Bind.body`.

## 3.1.0

- Adds the implicit authorization grant flow via the `AuthRedirectController` type.
- Deprecates `AuthCodeController` in favor of `AuthRedirectController`.
- Improves speed of many database CLI commands
- Improves error messaging of the CLI; no longer includes stack trace for expected errors.
- Allows self-referencing and cyclical relationships between managed objects
- Fixes bug where ManagedObjects cannot have mixins
- Adds `ManagedContext.insertObject`, `ManagedContext.insertObjects` and `ManagedContext.fetchObjectWithID`.

## 3.0.2

- Fix regression when generating OpenAPI documentation for `ManagedObject`s
- Adds `--resolve-relative-urls` flag to `document` commands to improve client applications
- Adds `Serializable.documentSchema` instance method. Removes `Serializable.document` static method.
- Adds optional `values` argument to `Query` constructor

## 3.0.1

- `Controller` is now an abstract class that requires implementing `handle`. This is a minor breaking change that should not have an impact.
- 'Serializable' can now implement static 'document' method to override component documentation behavior
- Removes `aqueduct setup --heroku=<name>` and instead points to documentation.
- Fixes issue ORM had with transformed values (e.g. enums) and nullable columns

## 3.0.0

- Adds `BodyDecoder.decode<T>` and `BodyDecoder.as<T>`. This replaces existing `decodeAs*` and `as*` methods.
- Adds `AuthDelegate.addClient` and `AuthServer.addClient`.
- Adds `ManagedContext.transaction` to enable queries to be run in a database transaction.
- Adds 'Scope' annotation to add granular scoping to `ResourceController` methods.
- Adds `Recyclable<T>` to control whether controllers are instantiated per request or are reused.
- Adds support for storing PostgreSQL JSONB data with `Document` data type.
- Adds `Query.insertObject`.
- Adds support for OpenAPI 3.0.0 documentation generation.
    - Adds `APIComponentDocumenter`, `APIOperationDocumenter`, `APIDocumentContext`.
    - Removes `PackagePathResolver`, `ApplicationOptions.isDocumenting` and `APIDocumentable`.
- Adds `MockHTTPServer.queueHandler` and `MockHTTPServer.queueOutage`.
- `Query.where` behavior has changed to consistently use property selector syntax.
    - Removes methods like `whereEqualTo` and replaced with `QueryExpression`.
- `Controller.generate` renamed to `Controller.link`. Removed `Controller.pipe`.
- `package:aqueduct/test` moved to `package:aqueduct_test/aqueduct_test`, which is a separate dependency from `aqueduct`.
- Renames methods in `AuthDelegate` to provide consistency.
- Removes `ManagedContext.defaultContext`; context usage must be explicit.
- Removes `HTTPResponseException`. Responses can now be thrown instead.
- `QueryException`s are no longer thrown for every ORM exception. If a store chooses to interpret an exception, it will still throw a `QueryException`. Otherwise, the underlying driver exception will be thrown.
- Default constructor for `PostgreSQLPersistentStore` now takes connection info instead of closure.
- `Controller.listen` renamed `Controller.linkFunction`.
- Change default port for `aqueduct serve` to 8888.
- Binding metadata - `HTTPPath`, `HTTPBody`, `HTTPQuery` and `HTTPHeader` - have been changed to `Bind.path`, `Bind.body`, `Bind.query` and `Bind.header`, respectively.
- Remove `@httpGet` (and other `HTTPMethod` annotations) constants. Behavior replaced by `@Operation`.
- Removes `runOnMainIsolate` from `Application.start()` and added `Application.startOnMainIsolate()` as replacement.
- Removes `ManagedSet.haveAtLeastOneWhere`.
- Renames `RequestSink` to `ApplicationChannel`.
    - Replace constructor and `willOpen` with `prepare`.
    - Replace `setupRouter` with `entryPoint`.
- Replaces `AuthCodeController.renderFunction` with `AuthCodeControllerDelegate`.
- Removes `AuthStrategy` in place of `AuthorizationParser<T>`.
    - Adds concrete implementations of `AuthorizationParser<T>`, `AuthorizationBearerParser` and `AuthorizationBasicParser`.
- Removes `AuthValidator.fromBearerToken` and `AuthValidator.fromBasicCredentials` and replaces with `AuthValidator.validate<T>`.
- Renames the following:
    - `Authorization.resourceOwnerIdentifier` -> `Authorization.ownerID`
    - `Request.innerRequest` -> `Request.raw`
    - `AuthStorage` -> `AuthServerDelegate`
    - `AuthServer.storage` -> `AuthServer.delegate`
    - `ApplicationConfiguration` -> `ApplicationOptions`
    - `Application.configuration` -> `Application.options`
    - `HTTPFileController` -> `FileController`
    - `HTTPSerializable` -> `Serializable`
    - `HTTPCachePolicy` -> `CachePolicy`
    - `HTTPCodecRepository` -> `CodecRegistry`
    - `requiredHTTPParameter` -> `requiredBinding`
    - `ManagedTableAttributes` -> `Table`
    - `ManagedRelationshipDeleteRule` -> `DeleteRule`
    - `ManagedRelationship` -> `Relate`
    - `ManagedColumnAttributes` -> `Column`
    - `managedPrimaryKey` -> `primaryKey`
    - `ManagedTransientAttribute` -> `Serialize`
        - `Serialize` now replaces `managedTransientAttribute`, `managedTransientInputAttribute`, and `managedTransientOutputAttribute`.
    - `RequestController` -> `Controller`
    - `RequestController.processRequest` -> `Controller.handle`
    - `HTTPController` -> `ResourceController`

## 2.5.0

- Adds `aqueduct db schema` to print an application's data model.
- Adds `aqueduct document serve` that serves the API documentation for an application.
- Adds `--machine` flag to `aqueduct` tool to only emit machine-readable output.
- Adds `defaultDelay` to `MockHTTPServer`. Defaults to null for no delay.
- Adds `defaultResponse` to `MockHTTPServer`. Defaults to a 503 response instead of a 200.
- Adds option to set a custom delay for a specific response in `MockHTTPServer`'s `queueResponse` function.
- Performance improvements

## 2.4.0

- Adds `HTTPRequestBody.maxSize` to limit HTTP request body sizes. Defaults to 10MB.
- Adds `ManagedTableAttributes` to configure underlying database table to use multiple columns to test for uniqueness.

## 2.3.2

- Adds `Request.addResponseModifier` to allow middleware to modify responses.

## 2.3.1

- Adds `Response.bufferOutput` to control whether the HTTP response bytes are buffered.
- Adds `whereNot` to apply an inverse to other `Query.where` expression, e.g. `whereNot(whereIn(["a", "b"]))`.
- Fixes bug where subclassing `ManagedObjectController` didn't work.
- Renames `ResourceRegistry` to `ServiceRegistry`.
- Improves feedback and interface for `package:aqueduct/test.dart`.

## 2.3.0

- Adds `Request.acceptableContentTypes` and `Request.acceptsContentType` for convenient usage of Accept header.
- Adds `AuthStorage.allowedScopesForAuthenticatable` to provide user attribute-based scoping, e.g. roles.
- Adds `Query.forEntity` and `ManagedObjectController.forEntity` to dynamically instantiate these types, i.e. use runtime values to build the query.
- Adds `PersistentStore.newQuery` - allows a `PersistentStore` implementation to provide its own implementation of `Query` specific to its underlying database.
- Adds `Query.reduce` to perform aggregate functions on database tables, e.g. sum, average, maximum, etc.
- `enum`s may be used as persistent properties in `ManagedObject<T>`. The underlying database will store them a strings.
- Speed of generating a template project has been greatly improved.

## 2.2.2

- Adds `ApplicationMessageHub` to send cross-isolate messages.

## 2.2.1

- Allow `HTTPCodecRepository.add` to use specify default charset for Content-Type if a request does not specify one.

## 2.2.0

- The default template created by `aqueduct create` is now mostly empty. Available templates can be listed with `aqueduct create list-templates` and selected with the command-line option `--template`.
- Bug fixes where `aqueduct auth` would fail to insert new Client IDs.
- `joinMany` and `joinOne` are deprecated, use `join(set:)` and `join(object:)` instead.
- `HTTPCodecRepository` replaces `Response.addEncoder` and `HTTPBody.addDecoder`.
- `Stream`s may now be `Response` bodies.
- Request bodies may be bound in `HTTPController` with `HTTPBody` metadata.
- Adds file serving with `HTTPFileController`.
- Adds `HTTPCachePolicy` to control cache headers for a `Response`.
- `Request.body` has significantly improved behavior and has been optimized.
- Content-Length is included instead of `Transfer-Encoding: chunked` when the size of the response body can be determined efficiently.

## 2.1.1

- Adds `ResourceRegistry`: tracks port-consuming resources like database connections to ensure they are closed when an application shuts down during testing.

## 2.1.0

- Fixes race condition when stopping an application during test execution
- Adds validation behavior to `ManagedObject`s using `Validate` and `ManagedValidator` and `ManagedObject.validate`.
- `ManagedObject`s now have callbacks `willUpdate` and `willInsert` to modify their values before updating and inserting.
- Fixes issue with `aqueduct serve` on Windows.

## 2.0.3

- Fixes issue with `aqueduct document` for routes using `listen`
- Fixes issue when using `TestClient` to execute requests with public OAuth2 client
- Enables database migrations past the initial `aqueduct db generate`.
- CLI tools print tool version, project version (when applicable)

## 2.0.2

- Allow binding to system-assigned port so tests can be run in parallel
- Change `aqueduct serve` default port to 8081 so can develop in parallel to Angular2 apps that default to 8080
- Remove `SecurityContext` reference from `ApplicationConfiguration`. SSL configured via new `aqueduct serve` arguments `ssl-key-path` and `ssl-certificate-path`, or overriding `securityContext` in `RequestSink`.

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
