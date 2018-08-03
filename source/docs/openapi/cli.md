# Creating OpenAPI Documents

In this document, you'll learn how to use the `aqueduct` command line tool to generate an OpenAPI document for your application.

## OpenAPI Documents

OpenAPI documents describe the details of every request and possible response your application has. These documents are JSON objects that follow a specification. This specification defines which properties the document can (or must) have. By following this specification, your application can take advantage of tools such as documentation viewers and source code generators.

The two most important objects in an OpenAPI document are components and path operations. A path operation contains an expected request and possible responses. Components are reusable definitions that you can use in a path operation. For example, a 400 Bad Request response component can be reused across path operations that may send this response.

Most of the documentation process revolves around registering components and creating path operations.

## The aqueduct document Command

Documents can be written by hand, but it takes a lot of time and is hard to keep in sync with your code. Aqueduct analyzes your code to build (most) of a document for you. You run the `aqueduct document` command in your project's directory, and it prints the JSON document to your console.

```bash
cd my_project/
aqueduct document

-- Aqueduct CLI Version: 3.0.0
-- Aqueduct project version: 3.0.0
{"openapi":"3.0.0","info":...
```

You may copy the output to use it in another tool; for example, by entering it into [Swagger Editor](https://editor.swagger.io). If you want to build a tool that runs this command, but don't want to parse the version info from the output, use the `--machine` flag.

```bash
aqueduct document --machine
{"openapi":"3.0.0","info":...
```

Much of the metadata in an OpenAPI document - such as title or version - is derived from your application's `pubspec.yaml`. If you want to override the derived values, or provide values that can't be derived, use options like `--title` or `--license-name`. See `aqueduct document --help` for all options.

## How Applications are Documented

When you run the `aqueduct document` command, it creates an empty `APIDocument` that objects in your application will populate. Your application goes through its normal initialization process (i.e., `prepare` and `entryPoint`). Controllers and service objects are then told to register components. For example, all `ManagedObject`s register themselves as a reusable schema component. After components are registered, the controllers in an application are told to create path operations that define the requests they handle.

!!! note "Configuration Files"
    Because your application goes through initialization as if it were going to run the application, you must have a valid configuration file when documenting. This defaults to 'config.yaml.src', the same file you use for running tests. See `aqueduct document --help` to use a different file.

### Documenting Components

Objects that register components implement `APIComponentDocumenter.documentComponents`. Controllers - which implement this method - automatically document their components as long as they are linked to your application's entry point. Other types of objects that implement this method will be automatically documented if they are declared as a property of your `ApplicationChannel`.

For example, in the following code, the `AuthServer`, `Router` and `PathController` all automatically document their components.

```dart
class MyChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = new AuthServer(...);
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/path").link(() => new PathController());
    return router;
  }
}
```

In most applications, the automatically documented objects are the only objects that register components. If you have an object that needs to register components, but aren't automatically documented, override `documentComponents` in your app channel to tell that object to register components. You must call the superclass' implementation.

```dart
class MyChannel extends ApplicationChannel {
  ...
  @override
  void documentComponents(APIDocumentContext context) {
    super.documentComponents(context);

    objectWithComponents.documentComponents(context);
  }
}
```

You can override `documentComponents` in controllers and services that you create. Read the [guide on component documentation](components.md) for more details.

### Document Path Operations

A path operation is the expected request and possible responses for a path (e.g., `/users`) and its request method (e.g., `GET`). Each operation describes how to send a request to the server, like which headers or query parameters to include. Responses describe the status code, headers and body that can be sent. Each controller implements `APIOperationDocumenter.documentOperations` to define this information for the requests it handles.

Built-in controllers like `Authorizer` and `ResourceController` already implement this method. You typically only override this method when creating your own middleware. For more information on documenting middleware, see [this guide](middleware.md).

When creating documentation for `ResourceController`s, request parameters are derived from your bindings, but you still need to provide the possible responses. For more information on documenting endpoint controllers, see [this guide](endpoint.md).
