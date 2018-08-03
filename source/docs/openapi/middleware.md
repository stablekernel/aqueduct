# Documenting Middleware Controllers

In this document, you'll learn how to document middleware controllers.

## Adding to an Operation

For the purposes of documentation, a middleware controller does not create operation request and responses. Rather, it modifies the operation details provided by its endpoint controller. When writing middleware controllers, you must override `documentOperations` and call the superclass' implementation. This allows the middleware's linked controller to document its operations, which will eventually reach an endpoint controller.

Once the endpoint controller returns the meat of the operation document, a middleware controller can modify it. For example, a middleware that requires a query parameter named 'key' would like like so:

```dart
class Middleware extends Controller {
  ...

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext context, String route, APIPath path) {
    final ops = super.documentOperations(context, route, path);

    // ops has been filled out by an endpoint controller,
    // add 'key' query parameter to each operation.
    ops.forEach((method, op) {
      op.addParameter(APIParameter.query("key", schema: APISchemaObject.string()));
    });

    return ops;
  }
}
```

Each string key in an operations map is the lowercase name of an HTTP method, e.g. 'get' or 'post'. An `APIOperation` encapsulates its request parameters and responses. 
