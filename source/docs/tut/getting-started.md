# 1. Getting Started

The purpose of this tutorial series is to become familiar with how Aqueduct works by building an application. To get started, make sure you have the following software installed:

1. Dart ([Install Instructions](https://www.dartlang.org/install))
2. IntelliJ IDEA or any other Jetbrains IDE ([Install Instructions](https://www.jetbrains.com/idea/download/))
3. The IntelliJ IDEA Dart Plugin ([Install Instructions](https://www.dartlang.org/tools/jetbrains-plugin))

If at anytime you get stuck, hop on over to the [Aqueduct Slack channel](http://slackaqueductsignup.herokuapp.com).

## Installing Aqueduct

`aqueduct` is a command-line utility for all things Aqueduct - including creating a new project. Install `aqueduct` with the following command:

```
pub global activate aqueduct
```

!!! warning ""
    If you get warning text about your `PATH`, make sure to read it before moving on.

Creating a Project
---

Create a new project named `quiz`:

```
aqueduct create quiz
```

This creates a `quiz` project directory.

Open this directory with IntelliJ IDEA by dragging the project folder onto IntellIJ IDEA's icon).

In IntelliJ's project view, locate the `lib` directory; this is where your project's code will go. This barebones project has two source files - `quiz.dart` and `channel.dart`.

The file `quiz.dart` should automatically be opened (if it is not, select it). Click on the `Enable Dart Support` button in the top right corner of the editor.

## Handling HTTP Requests

In this tutorial, we'll create a Quiz web server that can return questions and their answers. At the end of this tutorial, we'll be able to handle the following HTTP requests:

- `GET /questions` to get a JSON list of questions and their answers
- `GET /questions/:index` to get an individual question and its answer

Let's start by writing the code that will send a 200 OK response for `GET /questions` requests.

Create a new file in `lib/controller/question_controller.dart` and add the following code (you may need to create the subdirectory `lib/controller/`):

```dart
import '../quiz.dart';

class QuestionController extends RESTController {
  final List<String> questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @Bind.get()
  Future<Response> getAllQuestions() async {
    return new Response.ok(questions);
  }
}
```

This creates a new class, `QuestionController`. Its `getAllQuestions()` method is special - it will automatically be called if a `QuestionController` is asked to handle a `GET` request. The `Response` it returns will be the response sent to the client - in this case, a 200 OK response with a body that contains its questions.

A method with this behavior is called an *operation method*. An operation is the combination of an HTTP method and request path - like `GET /questions` or `POST /teams/1/players`. You should be able to describe an operation in plain English phrase - like "get all the questions" or "add a player to a team".

An operation method is invoked to handle a specific operation. For a method to be an operation method, it must meet the following criteria:

- It's declared in an `RESTController` subclass.
- It returns a `Future<Response>`.
- It has an annotation that indicates the HTTP method it handles, e.g. `@Bind.get()`.

!!! tip
    The plain English phrase for an operation is a really good name for an operation method and a good name will be useful when you generate OpenAPI documentation from your code.

So far, we've declared that a `QuestionController` can respond to `GET` requests, but we haven't written code anywhere that indicates this should happen when the path is `/questions`. To understand how to do this, we have to learn a bit about the general structure of an Aqueduct application.

In Aqueduct, objects called *controllers* can act on a request. For example, `QuestionController` acts by sending a 200 OK response if the request method is `GET`. Controllers can do more than just create a response; one might do something to verify the request is valid in some way, the other might add a header just before sending the response. Controllers are linked together to form a series of steps that a request goes through so that it can be responded to.

Each controller can do one of two things:

- Send a response for the request.
- Pass the request to the next controller in the series of steps.

We have a controller that will send a response for a `GET` request, but it needs to be passed any requests with the path `/questions`. A `Router` is a type of controller that passes requests to another controller if the path of the request matches a pre-determined *route*.

Open `channel.dart` and take a look at `QuizChannel.entryPoint`:

```dart
  @override
  Controller get entryPoint {
    final router = new Router();

    router
      .route("/example")
      .listen((request) async {
        return new Response.ok({"key": "value"});
      });

    return router;
  }
```

This code creates a `Router` that is the first controller to receive every request. When the path of the request is `/example`, the `Router` send the request to the closure provided to `listen`. We need to have the `Router` send requests with the path `/questions` to our `QuestionController.`

Import the file that contains our definition of `QuestionController` at the top of `channel.dart`:

```dart
import 'controller/question_controller.dart';
```

Then, modify `QuizChannel.entryPoint` by adding a new route that an instance of `QuestionController` will handle.

```dart
@override
Controller get entryPoint {
  final router = new Router();

  router
    .route("/questions")
    .generate(() => new QuestionController());

  router
    .route("/example")
    .listen((request) async {
      return new Response.ok({"key": "value"});
    });

  return router;
}
```

Before we explain this, let's see it in action. In the project directory, run the following command:

```
aqueduct serve
```

Then, in a browser, enter `http://localhost:8081/questions`. You'll see the following text:

```
["How much wood can a woodchuck chuck?","What's the tallest mountain in the world?"]
```

Now, try entering a path that we didn't add to the `Router`, like `http://localhost:8081/foobar`. You'll get a 404 Not Found error.

## The Application Channel

As we mentioned, an Aqueduct application is made up of controllers that a request flows through. This group of controllers is called the *application channel*. Every application must subclass `ApplicationChannel` and override `entryPoint` to provide this channel of controllers. The controller returned from this method is the first controller to receive a request - in our case, a `Router`.

Controllers are added to the channel by invoking methods like `route`, `generate` and `listen`. Each has slightly different behavior:

- `route` is only available for routers - it branches the channel. If the request's path matches the route, it flows to the next step in the branch. If there is no match, it returns a 404 Not Found.
- `listen` adds a simple closure controller to the channel.
- `generate` creates a new instance of a controller for each request.

If we were to draw our application in a a diagram, it would look like this:

![Channel Diagram](../img/ChannelDiagram.png)

When we make a request for `GET /questions`, the router is the first to receive it. It recognizes the path `/questions`, so a new instance of `QuestionController` is created and is passed the request. The `QuestionController` then calls its `getAllQuestions()` operation method because the request is a `GET` request. This method returns a response that gets sent to the client.


!!! tip "Why a new instance?"
    `RESTController`s have a lot of internal steps, so they need to temporarily store information about the request during those steps. This information gets stored in properties of the controller. Some of these internal steps are asynchronous; if a new request comes in while we're in the middle of handling another, the properties will be changes to the values for the new request. Generating prevents this by creating a new controller for each request. To re-use the same instance, `pipe` is used.  See [this guide](../http/controller.md) for more details on channel construction.

!!! tip
    Constructing the channel should look familiar to to using higher-ordered functions like `map` and `where` on `List`s and `Stream`s.

Adding Another Route
---

So far, we've created an operation that returns a list of questions. Now, we are going to create an operation to "get a single question from that list". This operation's path will be `/questions/0` or `/questions/1`, where the number in the path tells us the index of the question array. This number is a *path variable*; the question returned in the response will depend on the value of this variable.

A path variable captures a value from the request path so that it can be used in our code. A path variable is prefixed with a colon (`:`). The route `/questions/:index` has a variable for the path segment that comes after `/questions`. For example, the path `/questions/0` would match this route and the path variable `index` would be `0`.

By default, a path variable is required - the path `/questions` doesn't match `/questions/:index`. This means that the path `/questions` won't match `/questions/:index`. That's why path segments can be marked as optional.

By wrapping `:index` in square brackets - `/questions/[:index]` - we say that it is optional and the path can be either `/questions` or `/questions/:index`. Both requests will match the route and be sent to a `QuestionController`.

Modify the route in `entryPoint` add an optional `index` route variable to `/questions`:

```dart
@override
Controller get entryPoint {
  final router = new Router();

  router
    .route("/questions/[:index]")
    .generate(() => new QuestionController());

  router
    .route("/example")
    .listen((request) async {
      return new Response.ok({"key": "value"});
    });

  return router;
}
```

Recall that `getAllQuestions()` is the operation method for "getting all the questions"; it runs when the operation is `GET /questions`. There is not an operation method for "get a single question at an index", that is, when the operation is `GET /questions/:index`. Therefore, we must create a new operation method in `QuestionController`:

```dart
class QuestionController extends RESTController {
  final List<String> questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @Bind.get()
  Future<Response> getAllQuestions() async {
    return new Response.ok(questions);
  }

  @Bind.get()
  Future<Response> getQuestionAtIndex(@Bind.path("index") int index) async {
    if (index < 0 || index >= questions.length) {
      return new Response.notFound();
    }

    return new Response.ok(questions[index]);  
  }
}
```

Reload the application by hitting Ctrl-C in the terminal that ran `aqueduct serve` and then run `aqueduct serve` again.

In your browser, enter `http://localhost:8081/questions` and you'll get the list of questions.

Then, enter `http://localhost:8081/questions/0` and you'll get "How much wood can a woodchuck chuck?". If the index not within the list of questions or it something other than an integer, you'll get an 404 Not Found response.

!!! warning "Closing the Application"
    Once you're done running an application, stop it with `^C`. Otherwise, the next time you try and start an application, it will fail because your previous application is already listening for requests on the same port.

## Request Binding

An `RESTController` picks an operation method if both of the following are true:

1. The bound HTTP method matches the incoming request method (e.g., `@Bind.get()` and `GET`)
2. The incoming request path has a value for each argument bound with `Bind.path`.

When the request is `GET /questions/:index`, the `index` path variable has a value. Since `getQuestionAtIndex(index)` has an argument that is bound to this path variable, it will be called. When the request is `GET /questions`, the path variable `index` is missing. The method `getAllQuestions()` binds no path variables, so it will be called.

This binding behavior is specific to `RESTController`. In addition to path variables, you can bind headers, query parameters and bodies. Check out [RESTControllers](../http/rest_controller.md) for more details.

The More You Know: Multi-threading and Application State
---
In this simple exercise, we used a constant list of question as the source of data for the questions endpoint. For a simple getting-your-feet-wet demo, this is fine.

However, in a real application, it is important that we don't keep any mutable state in a `ApplicationChannel` or any `Controller`s. This is for three reasons. First, it's just bad practice - web servers should be stateless. They are facilitators between a client and a repository of data, not a repository of data themselves. A repository of data is typically a database.

Second, the way Aqueduct applications are structured makes it intentionally difficult to keep state. For example, `RESTController` is instantiated each time a new request comes in. Any state they have is discarded after the request is finished processing. This is intentional - you won't run into an issue when scaling to multiple server instances in the future, because the code is already structured to be stateless.

Finally, Aqueduct applications are set up to run on multiple isolates. An isolate is effectively a thread that shares no memory with other threads. If we were to keep track of state in some way, that state would not be reflected across all of the isolates running on this web server. So depending on which isolate grabbed a request, it may have different state than you might expect. Again, Aqueduct forces you into this model on purpose.

Isolates will spread themselves out across CPUs on the host machine. Each isolate will have its own instance of your `ApplicationChannel` subclass. Having multiple isolates running the same stateless web server on one machine allows for faster request handling. Each isolate also maintains its own set of services, like database connections.

## [Next Chapter: Executing Queries](executing-queries.md)
