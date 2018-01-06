# 1. Getting Started

### Purpose: Become familiar with how Aqueduct works by building an application.

By the end of this tutorial, you will have created an Aqueduct application that serves fictional heroes from a PostgreSQL database. You will learn the following:

- Run an Aqueduct application
- Route HTTP requests to the appropriate handler
- Store and retrieve database data
- Write automated tests for each endpoint

## Installation

To get started, make sure you have the following software installed:

1. Dart ([Install Instructions](https://www.dartlang.org/install))
2. IntelliJ IDEA or any other Jetbrains IDE, including the free Community Edition ([Install Instructions](https://www.jetbrains.com/idea/download/))
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

Create a new project named `heroes`:

```
aqueduct create heroes
```

This creates a `heroes` project directory.

Open this directory with IntelliJ IDEA by dragging the project folder onto IntellIJ IDEA's icon.

In IntelliJ's project view, locate the `lib` directory; this is where your project's code will go. This barebones project has two source files - `heroes.dart` and `channel.dart`.

Open the file `heroes.dart`. Click on the `Enable Dart Support` button in the top right corner of the editor.

## Handling HTTP Requests

In your browser, navigate to [http://aqueduct-tutorial.stablekernel.io](http://aqueduct-tutorial.stablekernel.io). This browser application will fetch heroes by making HTTP requests that your `heroes` application will respond to. At this end of this chapter, our application will be able to handle two types of requests:

1. `GET /heroes` to get a JSON list of heroes
2. `GET /heroes/:id` to get an individual hero by its `id`

!!! warning "HTTP vs HTTPS"
    The browser application is served over HTTP so that it can access your Aqueduct application when it runs locally on your machine. Your browser may warn you about this.

These requests are called *operations*. An operation is the combination of an HTTP method and path. So, `GET /heroes` is an operation that "gets all heroes" and `GET /heroes/:id` is an operation that "gets a single hero by id". You should be able to describe all operations in plain English phrase.

Let's start by writing the code for the `GET /heroes` operation.

Create a new file in `lib/controller/heroes_controller.dart` and add the following code (you may need to create the subdirectory `lib/controller/`):

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:heroes/heroes.dart';

class HeroesController extends RESTController {
  final heroes = [
    {'id': 11, 'name': 'Mr. Nice'},
    {'id': 12, 'name': 'Narco'},
    {'id': 13, 'name': 'Bombasto'},
    {'id': 14, 'name': 'Celeritas'},
    {'id': 15, 'name': 'Magneta'},    
  ];

  @Operation.get()
  Future<Response> getAllHeroes() async {
    return new Response.ok(heroes);
  }
}
```

This code declares a `RESTController` subclass named `HeroesController`. A `RESTController` can handle an incoming HTTP request and create a response. It does this by calling its *operation methods*. An operation method is an instance method of a `RESTController` that creates a `Response` object. A `RESTController` can have many operation methods and a different one will be called depending on the contents of the request.

`HeroesController` has one operation method: `getAllHeroes()`. Like all operation methods, it has an `Operation` annotation and returns a `Future<Response>`. This operation method will only be called if the incoming request method is `GET`; the named constructor `Operation.get()` annotation tells us that. When this method is called, a 200 OK response with a JSON encoded list of heroes.

Our `HeroesController` won't do anything by itself; something has to send it a request. To do that, we need to understand a bit about the general structure of an Aqueduct application.

### Aqueduct Controllers

In Aqueduct, objects called *controllers* handle a request. For example, `HeroesController` handles a `GET` request by sending a 200 OK response. Controllers can do more than just send a response; one might make sure the request is valid and another might associate an authenticated user with the request. Controllers of all kinds are linked together to form a series of steps that a request goes through.

Each controller can do one of two things:

- Send a response for the request.
- Pass the request to the next controller in the series of steps.

Open `channel.dart` and take a look at `HeroesChannel.entryPoint`:

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

This code creates and links together three controllers. The first controller is a `Router` that we instantiate like any other object. The `Router` is returned from `entryPoint`; it will be the first controller to handle a request. You register routes with a `Router`. If a request's path matches a registered route, the `Router` passes it to another controller. If the request path is unknown, the `Router` sends a 404 Not Found response.

Routes are registered by calling `route(route)` on the router. This method creates a new controller and links it to the `Router` for requests that match the route. This 'route controller' is just a dumb pipe - it automatically passes the request on to its next controller. That controller is the one created by calling `listen(handler)` on the 'route controller'. This controller invokes its closure - taking the request as input and returning a response as output.

A `/example` request goes through these controllers in the same order they are created and linked together. Both `route(route)` and `listen(handler)` return the controller they create, allowing us to link controllers together. These are instance methods of a class named `Controller`. Like `Router`, a `RESTController` is also a subclass of `Controller`, so our `HeroesController` can be linked, too.

!!! note "Higher Ordered Functions"
    Methods like `listen` and `route` should be familiar to programmers that use methods like `map` and `where` on collection types like `List` and `Stream`.

Let's create a new route for the path `/heroes` and link our `HeroesController` to it. Import the file that contains our definition of `HeroesController` at the top of `channel.dart`:

```dart
import 'controller/heroes_controller.dart';
```

Then, modify `HeroesChannel.entryPoint`:

```dart
@override
Controller get entryPoint {
  final router = new Router();

  router
    .route("/heroes")
    .link(() => new HeroesController());

  router
    .route("/example")
    .listen((request) async {
      return new Response.ok({"key": "value"});
    });

  return router;
}
```

Like `listen`, `generate` creates and links a controller. The difference between the two is that `listen` takes a closure that handles the request, whereas `generate` takes a closure that *creates a controller object to handle the request*. For quick and dirty request handlers, a `listen` controller is okay, but as your application grows, it is a lot easier to organize your request handling logic into controller objects like `HeroesController`.

With this route hooked up, a request with the path `/heroes` will get routed to a generating controller that creates a new instance of `HeroesController` to handle each request. We now have have fully defined operation for `GET /heroes` and we can run our application.

In the project directory, run the following command from the command-line:

```
aqueduct serve
```

Reload the browser page `http://aqueduct-tutorial.stablekernel.io`. You'll see your heroes in your web browser:

#### Screenshot of Heroes Application

![Aqueduct Heroes First Run](../img/run1.png)

## The Application Channel

As we mentioned, an Aqueduct application is made up of controllers that a request flows through. This group of controllers is called the *application channel*. Every application must subclass `ApplicationChannel` and override `entryPoint` to provide this channel of controllers.

If we were to draw our application in a a diagram, it would look like this:

![Channel Diagram](../img/ChannelDiagram.png)

Recall that the controller returned from this method is the first controller to receive a request; this was our `Router`. Also recall that controllers are added to the channel by invoking methods like `route`, `generate` and `listen`. Each has slightly different behavior:

- `route` is only available for routers - it branches the channel. If the request's path matches the route, it flows to the next step in the branch. If there is no match, it returns a 404 Not Found.
- `listen` adds a simple closure controller to the channel.
- `generate` creates a new instance of a controller for each request.

!!! tip "Why a new instance?"
    `RESTController`s have a lot of internal steps, so they need to temporarily store information about the request during those steps. This information gets stored in properties of the controller. Some of these internal steps are asynchronous; if a new request comes in while we're in the middle of handling another, the properties will be changes to the values for the new request. Generating prevents this by creating a new controller for each request. To re-use the same instance, use `pipe` instead of `generate`.  See [this guide](../http/controller.md) for more details on channel construction.

An application channel is created when your application starts. Your application channel is also where you initialize the things your application will need; this might include configuring a database connection or reading a configuration file. (We'll see how this is done later in the tutorial.) Once your application channel has finished setting up, it doesn't do much itself; its controllers take over to handle requests as they come in.

### Routing

So far, we've created an operation that returns a list of heroes. Now, we are going to create an operation to "gets a single hero by id". The `id` of the hero will be included in the operation's request path; something like `/heroes/2` or `/heroes/10`. The segment of the path that contains the hero's `id` is called a *path variable*; our application can use this value to determine which hero to return.

We can add path variables to a route by adding a path segment prefixed with a colon. Here's what that would look like:

```dart
  router.route("/heroes/:id");
```

For a request to match this route, it must take the form of `/heroes/1`, `/heroes/2`, and so on. When we write code to handle this operation, we can use the value of `id`. The route `/heroes/:id` *does not*, however, match the path `/heroes`. We'd like it to - it would mean that our `HeroesController` can handle the logic for both of our operations, `GET /heroes` and `GET /heroes/:id`. We can wrap a segment in route in square brackets to mark it as optional.

Modify the route in `entryPoint` add an optional `id` path variable to `/heroes`:

```dart
@override
Controller get entryPoint {
  final router = new Router();

  router
    .route("/heroes/[:id]")
    .link(() => new HeroesController());

  router
    .route("/example")
    .listen((request) async {
      return new Response.ok({"key": "value"});
    });

  return router;
}
```

With this change, a `HeroesController` can handle both of our hero-getting operations. In our `HeroesController`, we'll create another operation method for `GET /heroes/:id`. Add that method in `controller/heroes_controller.dart`.

```dart
class HeroesController extends RESTController {
  final heroes = [
    {'id': 11, 'name': 'Mr. Nice'},
    {'id': 12, 'name': 'Narco'},
    {'id': 13, 'name': 'Bombasto'},
    {'id': 14, 'name': 'Celeritas'},
    {'id': 15, 'name': 'Magneta'},  
  ];

  @Operation.get()
  Future<Response> getAllHeroes() async {
    return new Response.ok(heroes);
  }

  @Operation.get('id')
  Future<Response> getHeroByID() async {
    final id = int.parse(request.path.variables['id']);
    final hero = heroes.firstWhere((hero) => hero['id'] == id, orElse: () => null);

    if (hero == null) {
      return new Response.notFound();
    }

    return new Response.ok(hero);
  }
}
```

Both operation methods handle `GET` requests, but the additional `'id'` parameter to `getHeroByID()`'s annotation says that it should be called if the path variable 'id' was found by the `Router`. The other method, `getAllHeroes()`, will only be called if there are no path variables in the request path. The value of 'id' is available in the `request` property - a property that all `RESTController`s have that has a reference to the request being handled.

!!! tip "Naming Operation Methods"
    The plain English phrase for an operation - like 'get hero by id' - is a really good name for an operation method and a good name will be useful when you generate OpenAPI documentation from your code.

Reload the application by hitting Ctrl-C in the terminal that ran `aqueduct serve` and then run `aqueduct serve` again.

In your browser, click on a hero in the dashboard to take you to its details. This will trigger a HTTP request like `GET /heroes/15` that your Aqueduct application will now handle. The detail page will look like this:

![Screenshot of Hero Detail Page](../img/run2.png)

You can also verify this from the server's perspective. In the terminal that is running `aqueduct serve`, you'll see log statements for requests handled:

```
[INFO] aqueduct: GET /heroes 0ms 200   
[INFO] aqueduct: GET /heroes/15 0ms 200  
```

This tells us that both of the requests - `GET /heroes` and `GET /heroes/15` - both yielded a 200 and that they took 0 milliseconds to complete.

!!! warning "Closing the Application"
    Once you're done running an application, stop it with `^C`. Otherwise, the next time you try and start an application, it will fail because your previous application is already listening for requests on the same port.

## REST Bindings

In our `getHeroByID()` method, we make a dangerous assumption that the path variable 'id' can be parsed into an integer. If 'id' were something else, like the string 'foo', `int.parse(s)` would throw an exception. When exceptions are thrown in operation methods, the controller catches it and sends a 500 Server Error response. 500s are bad, they don't tell the client what's wrong. A 404 Not Found is a better response here, but writing the code to catch that exception and create this response is cumbersome.

Instead, we can rely on a feature of operation methods - *request binding*. An operation method can declare parameters and *bind* them to properties of the request. When our operation method gets called, it will be passed values from the request as arguments. Request bindings automatically parse values into the type of the parameter (and return a better error response if parsing fails). Change the method `getHeroByID()`:

```dart
@Operation.get('id')
Future<Response> getHeroByID(@Bind.path('id') int id) async {
  final hero = heroes.firstWhere((hero) => hero['id'] == id, orElse: () => null);

  if (hero == null) {
    return new Response.notFound();
  }

  return new Response.ok(hero);
}
```

The `@Bind` annotation on an operation method parameter tells Aqueduct the value from the request we want bound. You can bind path variables, headers, query parameters and bodies. When binding path variables, we have to specify which path variable with the argument to `@Bind.path(pathVariableName)`.

The More You Know: Multi-threading and Application State
---

In this simple exercise, we used a constant list of heroes as our source of data. For a simple getting-your-feet-wet demo, this is fine. However, in a real application, you'd store this data in a database. That way you could add data to it and not risk losing it when the application was restarted.

More generally, a web server should never hang on to data that can change. While previously just a best practice, stateless web servers are becoming a requirement with the prevalence of containerization and tools like Kubernetes. Aqueduct makes it a bit easier to detect violations of this rule with its multi-threading strategy.

When you run an Aqueduct application, it creates multiple threads. Each of these threads has its own isolated heap in memory; meaning data that exists on one thread can't be accessed from other threads. In Dart, these isolated threads are called *isolates*.

An instance of your application channel is created for each isolate. Each HTTP request is given to just one of the isolates to be handled. In a sense, your one application behaves the same as running your application on multiple servers behind a load balancer. (It also makes your application substantially faster.)

If you are storing any data in your application, you'll find out really quick. Why? A request that changes data will only change that data in one of your application's isolates. When you make a request to get that data again, its unlikely that you'll see the changes - another isolate with different data will probably handle that request.

## [Next Chapter: Reading from a Database](executing-queries.md)
