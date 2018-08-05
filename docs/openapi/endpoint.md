# Documenting Endpoint Controllers

In this document, you'll learn how to document endpoint controllers.

## ResourceController Auto-Documentation

A `ResourceController` does most of the heavy lifting when it comes to generating OpenAPI documents. It will reflect on the bound variables of operation methods and their documentation comments to provide the majority of an OpenAPI document. You only need to provide the possible responses. You do this by overriding `documentOperationResponses` in your `ResourceController` subclass. The below shows a trivial example of a resource controller that returns a 200 OK with no body for every request.

```dart
class MyController extends ResourceController {
  ...

  Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
    return {"200": APIResponse("Successful response.")};
  }
}
```

This method must return a map, where each key is a string status code and each value is an `APIResponse` object. An `APIResponse` object is highly configurable, but in most cases, you only need to declare the schema of its body. For this purpose, a convenience constructor named `APIResponse.schema` exists. Here is an example where the JSON response body contains a single integer field named 'id':

```dart
Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
  return {
    "200": APIResponse.schema("Successful response.", APISchemaObject.object({
      "id": APISchemaObject.integer()
    }))
  };
}
```

In practice, you'll want to have different responses depending on the request method and path variables. The `operation` argument tells you which operation you are documenting.

```dart
Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
  if (operation.method == "GET") {
    if (operation.pathVariables.contains("id")) {
      return {"200": APIResponse("An object by its id.")};
    } else {
      return {"200": APIResponse("All objects.")};
    }
  }

  return null;
}
```

While a resource controller derives the rest of its documentation from your code, you may at times want to override this behavior. Individual elements may be modified by overriding methods like `documentOperationParameters`, or you may override `documentOperations` to take over the whole process.

If you are not using `ResourceController`, you must override `documentOperations` in your controller and provide all of the operation information yourself.
