# Document Components

In this document, you'll learn how to register and use OpenAPI components in your application's documentation.

## Registering Components with APIDocumentContext

When your application is being documented, a single instance of `APIDocumentContext` is created and passed to every documentation method. The context stores the document being created, but more importantly, is a container for reusable components. You may register components by implementing `APIComponentDocumenter` and implementing its abstract method. For example, the following code registers a reusable schema object:

```dart
class SourceRepository implements APIComponentDocumenter {
  @override
  void documentComponents(APIDocumentContext context) {
    super.documentComponents(context);

    context.schema.register("SourceRepository",
        APISchemaObject.object({
          "id": APISchemaObject.integer(),
          "name": APISchemaObject.string()
        });          
  }
}
```

A "SourceRepository" is an object that contains two fields, "id" (an integer) and "name" (a string). This component can be used anywhere a schema object can be used. Schema objects are one type of component that document what is typically considered to be a 'model object'. You most often see schema objects in request and response bodies. By default, each of your `ManagedObject`s are registered as schema objects. The other types of components are: responses, request bodies, parameters, headers, security schemes, and callbacks.

Components must be registered with a name, but can additionally be registered with a type. This allows users of a component to reference it by its Dart type. Including a type reference for an object is an optional argument when registering.

```dart
context.schema.register("SourceRepository",
    APISchemaObject.object({
      "id": APISchemaObject.integer(),
      "name": APISchemaObject.string()
    }, representation: SourceRepository);          
```

The order in which components are registered and referenced does not matter. If you reference a component that is created later in the documentation process, it will be resolved prior to the document being completed. If a referenced component is never registered, an error is thrown and your document will fail to generate.

## Using Components

Components can be used when declaring path operations, or as part of other components. For example, if you were to describe a response whose body was a component named "SourceRepository", it would look like this:

```dart
class RepositoryController extends ResourceController {
  ...

  @override
  Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
    if (operation.method == "GET") {
      return {
        "200": APIResponse.schema(context.schema["SourceRepository"])
      };
    }
    return null;
  }  
}
```

If an object has been registered by its type, you may use `getObjectWithType`.

```dart
class RepositoryController extends ResourceController {
  ...

  @override
  Map<String, APIResponse> documentOperationResponses(APIDocumentContext context, Operation operation) {
    if (operation.method == "GET") {
      return {
        "200": APIResponse.schema(context.schema.getObjectWithType(SourceRepository))
      };
    }
    return null;
  }  
}
```

## Component Discovery

All controllers are can document components when they are linked to the entry point. Objects other than controllers will automatically document their components if they implement `APIComponentDocumenter` *and* are declared properties of your `ApplicationChannel`. (See [this guide](cli.md) for other options.)

Built-in Aqueduct types will register any applicable components. This includes the types that handle OAuth2 as well as all `ManagedObject` subclasses in your application. 
