---
layout: page
title: "1. Routing and Request Handling"
category: tut
date: 2016-06-20 10:35:56
order: 1
---

Installing Dart
---

If you have Homebrew installed, run these commands from terminal:

```bash
brew tap dart-lang/dart
brew install dart
```

If you don't have Homebrew installed or you are on another platform, visit [https://www.dartlang.org/downloads](https://www.dartlang.org/downloads). It'll be quick, promise.

You should really install Atom as well for editing your code, and the Dart support is great. You can get it from [https://atom.io](https://atom.io). Once Atom is installed, install the 'dartlang' package from 'dart-atom' (not any of the other ones).

Creating a Project
---

To start, we'll keep it simple. Create a new directory named `quiz` (ensure that it is lowercase). Within this directory, create a new file named `pubspec.yaml`. Dart uses this file to define your project and its dependencies.

In the pubspec, enter the following markup:

```yaml
name: quiz
description: A quiz web server
version: 0.0.1
author: Me

environment:
  sdk: '>=1.0.0 <2.0.0'

dependencies:
  aqueduct: any  
```

This pubspec now defines a project named `quiz` (all Dart files and project identifiers are snake case), indicates that it uses a version of the Dart SDK between 1.0 and 2.0, and depends on the `aqueduct` package. Save this file in the `quiz` directory.

Next, you will fetch the dependencies of the `quiz` project. If you are using Atom, you'll get a popup that tells you to do this and you can just click the button. (You may also right-click on file in Atom and select 'Pub Get'). If you aren't using Atom, from the command line, run the following from inside the `quiz` directory:

```bash
pub get
```

Dependencies get stored in the directory ~/.pub-cache. Dart creates some project-specific files to reference the dependencies in that global cache in the project directory. You won't have to worry about that, though, since you'll never have to deal with it directly. Sometimes, it's just nice to know where things are. (There is one other file, called `pubspec.lock` that you do care about, but we'll chat about it later.)

With this dependency installed, your project can use `aqueduct`. For this simple getting started guide, we won't structure a full project and just focus on getting an `aqueduct` web server up and running. Create a new directory named `bin` and add a file to it named `quiz.dart`. At the top of this file, import the `aqueduct` package:

```dart
import 'package:aqueduct/aqueduct.dart';

```

Handling Requests
---

The structure of `aqueduct` is like most server-side frameworks: requests go to a router, which then get sent off to a series of request handlers. The most generic request handler is `HTTPController`. We'll create a `HTTPController` subclass that will handle requests by returning a list of questions in JSON. In `quiz.dart`, create this subclass:

```dart
class QuestionController extends HTTPController {
  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @httpGet getAllQuestions() async {
    return new Response.ok(questions);
  }
}
```

The `QuestionController` class defines a property named `questions` that has a list of strings. Then, it defines a 'handler method' called `getAllQuestions`. Handler methods in an `HTTPController` are responsible for responding to a request. To be a handler method, it must be marked with the appropriate metadata, in this case, `@httpGet`, that defines the HTTP method they handle. There are built-in constants for the common HTTP methods - like `@httpPut`, `@httpPost` - which are all instances of `HTTPMethod`.

To respond, a handler method must return an instance of `Response`. A `Response` always has a status code. There are built-in convenience constructors for common status codes. In this example, `Response.ok` creates a `Response` with status code 200. Depending on the convenience constructor used, the argument may mean something different. In the case of `Response.ok`, the argument is an object that will be encoded as the HTTP response body.

Therefore, when a HTTP GET gets routed to a `QuestionController`, a response with status code 200 and body containing a list of questions will be sent. By default, the response object - here, `questions` - gets encoded as JSON before being sent. (We'll see how that customize that much later.)

Right now, this `QuestionController` doesn't do anything. We need to listen for HTTP requests and feed them to instances of `QuestionController` so that it may respond.

`aqueduct` takes care of the heavy lifting here. Within the `aqueduct` package, there is a class called `Application`. An application instance manages starting up an HTTP listener. An application needs an `ApplicationPipeline` - a pipeline is the entry point into application-specific code for each request. It defines how those requests get routed and eventually responded to. At the bottom of `quiz.dart`, create a `ApplicationPipeline` subclass:

```dart
class QuizPipeline extends ApplicationPipeline {
  QuizPipeline(Map options) : super (options);
}
```

A pipeline must have a constructor that takes a `Map` of options and forward it on to its superclass' constructor. In the future, we'll actually do stuff in this constructor,
but for now, we just have to match the signature.

Aside from the constructor, a pipeline must implement the method `addRoutes`. Every pipeline has an instance of `Router`. A router matches the path of an HTTP request against registered routes to determine where the request goes to be handled. We'll set up a route so that HTTP requests with the path `/questions` get routed to an instance of `QuestionController`. Implement `addRoutes` in `QuizPipeline`:

```dart
class QuizPipeline extends ApplicationPipeline {
  QuizPipeline(Map options) : super (options);

  @override
  void addRoutes() {
    router
      .route("/questions")
      .next(() => new QuestionController());
  }
}
```

Routes are registered with a router using the method `route`. If a HTTP request's path matches that route, the request is forwarded on to the 'next' handler. We've defined 'next' here to be a closure that creates a new instance of `QuestionController`. We'll get to the specifics of all of that in a moment, but we're almost to the point that we can run this web server, and that seems more exciting.

With a pipeline and a route hooked up, we can write code that starts the web server. At the top of `quiz.dart`, underneath the import, define a `main` function like so:

```
import 'package:aqueduct/aqueduct.dart';

void main() {
  var app = new Application<QuizPipeline>();
  app.start();
}
```

To run the application if you are using Atom, you can right-click on `quiz.dart` and select 'Run Application'. If you wish to run from the command line, run the following from the `quiz` directory:

```bash
pub run quiz
```

In a browser, open the URL `http://localhost:8080/questions`. You'll see the list of questions! (You can shut down the server by hitting Ctrl-C in the command line.)

Magic is for children - so what happened?
---

Every Dart application starts in a `main` function. In most languages, the program will terminate once main is done executing, but Dart is not most languages. Instead, if there are any open `Stream`s still listening for events, the program will continue to run after main has finished. Therefore, main is more of a 'start' than anything else. Your `main` function creates an instance of `Application`, which opens a specific kind of `Stream`, an `HttpServer`.

When an application is started, it creates an instance of its pipeline, which is defined by its type argument; in this case, `QuizPipeline`. The `QuizPipeline` is a subclass of `ApplicationPipeline`, which is a subclass of `RequestHandler`. `RequestHandler`s are a very important class in `aqueduct` - they handle requests by either responding to them or passing them on to another `RequestHandler`. There are lots of types of `RequestHandler`s built-in to `aqueduct` - including `Router`, `HTTPController` and `Authenticator`. (You may also build your own pretty easily.)

With the exception of routers, `RequestHandler`s are chained through their `next` method. This method takes the next `RequestHandler` as an argument and returns that same `RequestHandler` as a result. This allows for chaining together of `RequestHandlers`:

```dart
handlerA
	.next(handlerB)
	.next(handlerC)
	.next(handlerD);
```

This chaining is *always* declared in the `addRoutes` method of a pipeline. Every argument for `next` must be either an instance of `RequestHandler` (or one of its subclasses) or a closure that returns a new instance of `RequestHandler`.

```dart
handlerA
	.next(handlerB)
	.next(() => new HandlerC());
```

For `HTTPController`s, it is required that you always create a new instance for every request. That's because the controller keeps a bit of state about the request that you can access in your handler methods. If we reused the same controller for each request, really bad things would happen - especially because more than one request can be processed at once! (This is why your `QuestionController` is wrapped in a closure.)

Don't worry though, `HTTPController`s are marked with `@cannotBeReused` metadata, so if you forget to wrap it in a closure, your application will throw an error immediately and tell you to wrap it in a closure.

Routers are slightly different. Instead of having just one `next`, they contain a collection of "nexts", set through the `route` method. `route` generates an instance of a `RouteHandler` that is added to the router. Because `RouteHandler` is a subclass of `RequestHandler`, you can chain handlers off it.
If a router gets a request for which it has a matching route, it sends it to that `RouteHandler`, which then immediately forwards it to its `next`. If a router can't find a route that matches the incoming request, it responds to the request with a 404.

![Pipeline Diagram](../images/ch01/pipelinediagram.png)

Therefore, an HTTP request sent to your server starts at your pipeline, gets delivered to your router, then to the route handler you created in `addRoutes`, which then makes its way to `QuestionController` before it is responded to.

Routing and Another Route
---

So far, we've added a route that matches the constant string `/questions`. Routers can do more than match a constant string, they can also include path variables, optional path components, regular expression matching and the wildcard character. We'll add to the existing `/questions` route by allowing requests to get a specific question.

In `quiz.dart`, modify the code in the pipeline's `addRoutes` method by adding "/[:index]" to the route.

```dart
  @override
  void addRoutes() {
	   router
		   .route("/questions/[:index]")
		   .next(() => new QuestionController());
	...
```

The square brackets indicate that part of the path is optional, and the colon indicates that it is a path variable. A path variable matches anything. Therefore, this route will match if the path is `/questions` or `/questions/2` or `/questions/foo`.

When using path variables, you may optionally restrict which values they match with a regular expression. The regular expression syntax goes into parentheses after the path variable name. Let's restrict the `index` path variable to only numbers:

```dart
  @override
  void addRoutes() {
	   router
		   .route("/questions/[:index(\\d+)]")
		   .next(() => new QuestionController());
	...
```

Now, there are two types of requests that will get forwarded to a `QuestionController` - a request for all questions (`/questions`) and and a request for a specific question at some index (`/questions/1`). We need to add a new handler method to `QuestionController`:

```dart
class QuestionController extends HTTPController {
  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @httpGet getAllQuestions() async {
    return new Response.ok(questions);
  }

  @httpGet getQuestionAtIndex(int index) async {
    if (index < 0 || index >= questions.length) {
      return new Response.notFound();
    }

    return new Response.ok(questions[index]);  
  }
}
```

Make sure you've stopped the application from running, and then run the application again. In your browser, enter http://localhost:8000/questions and you'll get the list of questions. Then, enter http://localhost:8000/questions/0 and you'll get the first question. If you enter an index not within the list of questions or something other than an integer, you'll get a 404.

Now, there isn't any magic here. There is an instance of [Request] that represents each request as it passes through different `RequestHandler`s.
When a route has a path variable and a request comes in that matches that path variable, the router will extract that path variable and store it in the `Request`'s `path` property (which is just a glorified `Map`).
The key of the path variable in the `path` will be the name of the path variable configured in the route (in this case, 'index'). The value is the path segment of the specific request.

As you know, an `HTTPController` already looks at the HTTP method of an incoming request to determine which handler method to use. When the request has path variables, the `HttpController` also looks at the arguments to each of your handler methods.
It then looks at the name of the argument - `getQuestionAtIndex` has an argument named `index` - and if that argument name matches the key of the path variable in `route`, it selects that method to handle the request.

The More You Know: Multi-threading and Application State
---
In this simple exercise, we used a constant list of question as the source of data for the questions endpoint. For a simple getting-your-feet-wet demo, this is fine.

However, in a real application, it is important that we don't keep any mutable state in a pipeline or any request handlers. This is for three reasons. First, it's just bad practice - web servers should be stateless. They are facilitators between a client and a repository of data, not a repository of data themselves. A repository of data is typically a database.

Second, the way `aqueduct` applications are structured makes it really difficult to keep state. For example, `HTTPController` is instantiated each time a new request comes in. Any state they have is discarded after the request is finished processing. This is intentional - you won't run into an issue when scaling to multiple server instances in the future, because the code is already structured to 'statelessly' run across a number of isolates.

Finally, isolates. `aqueduct` is set up to run on multiple isolates (the `numberOfInstances` argument for the `Application`'s `start` method). An isolate is effectively a thread that shares no memory with other isolates. If we were to keep track of state in some way, that state would not be reflected across all of the isolates running on this web server. So depending on which isolate grabbed a request, it may have different state than you might expect. Again, `aqueduct` forces you into this model on purpose.

Isolates will spread themselves out across CPUs on the host machine. Having multiple isolates running the same stateless web server on one machine allows for faster request handling. Each isolate also maintains its own set of resources, like database connections.
