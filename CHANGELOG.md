# aqueduct changelog

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
