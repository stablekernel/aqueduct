# aqueduct changelog

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
