# 1. Getting Started

By the end of this tutorial, you will have created an Aqueduct application that serves fictional heroes from a PostgreSQL database. You will learn the following:

- Run an Aqueduct application
- Route HTTP requests to the appropriate handler in your code
- Store and retrieve database data
- Write automated tests for each endpoint

!!! tip "Getting Help"
    If at anytime you get stuck, hop on over to the [Aqueduct Slack channel](http://slackaqueductsignup.herokuapp.com).

## Installation

To get started, make sure you have the following software installed:

1. Dart ([Install Instructions](https://www.dartlang.org/install))
2. IntelliJ IDEA or any other Jetbrains IDE, including the free Community Edition ([Install Instructions](https://www.jetbrains.com/idea/download/))
3. The IntelliJ IDEA Dart Plugin ([Install Instructions](https://www.dartlang.org/tools/jetbrains-plugin))

Install the `aqueduct` command line tool by running the following command in your shell:

```
pub global activate aqueduct
```

!!! warning ""
    If you get warning text about your `PATH`, make sure to read it before moving on.

Creating a Project
---

Create a new project named `heroes` by entering the following in your shell:

```
aqueduct create heroes
```

This creates a `heroes` project directory. Open this directory with IntelliJ IDEA by dragging the project folder onto IntellIJ IDEA's icon.

In IntelliJ's project view, locate the `lib` directory; this is where your project's code will go. This project has two source files - `heroes.dart` and `channel.dart`. Open the file `heroes.dart`. Click `Enable Dart Support` in the top right corner of the editor.

## Handling HTTP Requests

In your browser, navigate to [http://aqueduct-tutorial.stablekernel.io](http://aqueduct-tutorial.stablekernel.io). This browser application is a 'Hero Manager' - it allows a user to view, create, delete and update heroes. (It is a slightly modified version of the [AngularDart Tour of Heroes Tutorial](https://webdev.dartlang.org/angular/tutorial).) It will make HTTP requests to `http://localhost:8888` to fetch and manipulate hero data. The application you will build in this tutorial respond to those requests.

!!! warning "Running the Browser Application Locally"
    The browser application is served over HTTP so that it can access your Aqueduct application when it runs locally on your machine. Your browser may warn you about navigating to an insecure webpage, because it is in fact insecure. You can run this application locally by grabbing the source code from [here](https://github.com/stablekernel/tour-of-heroes-dart).

In this first chapter, you will write code to handle two requests: one to get a list of heroes, and the other to get a single hero by its identifier. These two requests take the following form:

1. `GET /heroes` to the list of heroes
2. `GET /heroes/:id` to get an individual hero

!!! tip "HTTP Operation Shorthand"
      An HTTP request always contains an HTTP method (e.g., `GET`, `POST`) and a URL (e.g., `http://localhost:8888/heroes`). Since you can host an application on another server and `http` is implied, we can reference requests by their method and path alone. The above two requests are an example of this shorthand reference. The ':id' segment is a variable: it can be 1, 2, 3, and so on.

### Controller Objects Handle Requests

Requests are handled by *controller objects*. A controller object evaluates a request and takes some action on it. This might be responding to the request, validating it in some way, or any number of other tasks. Controllers are linked together, such that each of their actions are applied to a single request. This allows applications to construct powerful request handling logic from a few building blocks. A series of linked together controllers is called a *channel*.

Our application will link two controllers:

- a `Router` that makes sure the request path is `/heroes` or `/heroes/:id`
- a `HeroesControllers` that construct a response with hero information in the body

Controllers are linked together in an *application channel*. An application channel is an object that is created when your application first starts up. It handles the initialization of your application, including linking controllers.

![ApplicationChannel entryPoint](../img/entrypoint.png)

You create an application channel by subclassing `ApplicationChannel`. This subclass is declared in `lib/channel.dart` by the template. Navigate to that file and note the current implementation of `ApplicationChannel.entryPoint`:

```dart
  @override
  Controller get entryPoint {
    final router = Router();

    router
      .route('/example')
      .linkFunction((request) async {
        return Response.ok({'key': 'value'});
      });

    return router;
  }
```

The controller returned from `entryPoint` is the first controller to receive every request in an application - in our case, this is a `Router`. Controllers are linked to the router; the template has one linked function controller that is called when a request's path is `/example`. We need to link a yet-to-be-created `HeroesController` to the router when the path is `/heroes`.

First, we need to define `HeroesController` and how it handles requests. Create a new file in `lib/controller/heroes_controller.dart` and add the following code (you may need to create the subdirectory `lib/controller/`):

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:heroes/heroes.dart';

class HeroesController extends Controller {
  final _heroes = [
    {'id': 11, 'name': 'Mr. Nice'},
    {'id': 12, 'name': 'Narco'},
    {'id': 13, 'name': 'Bombasto'},
    {'id': 14, 'name': 'Celeritas'},
    {'id': 15, 'name': 'Magneta'},    
  ];

  @override
  Future<RequestOrResponse> handle(Request request) async {
    return Response.ok(_heroes);
  }
}
```

Notice that `HeroesController` is a subclass of `Controller`; this allows it to be linked to other controllers and handle requests. It overrides its `handle` method by returning a `Response` object. This particular response object has a 200 OK status code, and it body contains a JSON-encoded list of hero objects. When a controller returns a `Response` object from its `handle` method, that response is sent to the client.

As it stands right now, our `HeroesController` will never be used. We need to link it to the entry point of our application for it to receive requests. First, import the file with our controller at the top of `channel.dart`.

```dart
import 'controller/heroes_controller.dart';
```

Then link this `HeroesController` to the `Router` for the request's with the path `/heroes` by modifying `entryPoint`.

```dart
@override
Controller get entryPoint {
  final router = Router();

  router
    .route('/heroes')
    .link(() => HeroesController());

  router
    .route('/example')
    .linkFunction((request) async {
      return new Response.ok({'key': 'value'});
    });

  return router;
}
```

We now have a simple, functioning application that will return a list of heroes. In the project directory, run the following command from the command-line:

```
aqueduct serve
```

This will start your application running locally. Reload the browser page `http://aqueduct-tutorial.stablekernel.io`. It will make a request to `http://localhost:8888/heroes` and your application will serve it. You'll see your heroes in your web browser:

#### Screenshot of Heroes Application

![Aqueduct Heroes First Run](../img/run1.png)

You can also see the actual response of your request by entering the following into your shell:

```bash
curl -X GET http://localhost:8888/heroes
```

You'll get JSON output like this:

```json
[
  {"id":11,"name":"Mr. Nice"},
  {"id":12,"name":"Narco"},
  {"id":13,"name":"Bombasto"},
  {"id":14,"name":"Celeritas"},
  {"id":15,"name":"Magneta"}
]
```

You'll also see this request logged in the shell that you started `aqueduct serve` in.

!!! tip "Browser Clients"
    In addition to `curl`, you can create a SwaggerUI browser application that executes requests against your locally running application. In your project directory, run `aqueduct document client` and it will generate a file named `client.html`. Open this file in your browser for a UI that constructs and executes requests that your application supports.

## Linking Controllers

When a controller handles a request, it can either send a response or let one of its linked controllers handle the request. By default, a `Router` will send a 404 Not Found response for any request. Adding a route to a `Router` creates an entry point to a new channel that controllers can be linked to. In our application, `HeroesController` is linked to the route `/heroes`.

Controllers come in two different flavors: endpoint and middleware. Endpoint controllers, like `HeroesController`, always send a response. They implement the behavior that a request is seeking. Middleware controllers, like `Router`, handles requests before they reach an endpoint controller. A router, for example, handles a request by directing it to the right controller. Controllers like `Authorizer` verify the authorization of the request. You can create all kinds of controllers to provide any behavior you like.

A channel can have zero or many middleware controllers, but must end in an endpoint controller. Most controllers can only have one linked controller, but a `Router` allows for many. For example, a larger application might look like this:

```dart
@override
Controller get entryPoint {
  final router = Router();

  router
    .route('/users')
    .link(() => APIKeyValidator())
    .link(() => Authorizer.bearer())
    .link(() => UsersController());

  router
    .route('/posts')
    .link(() => APIKeyValidator())
    .link(() => PostsController());

  return router;
}
```

Each of these objects is a subclass of `Controller`, giving them the ability to be linked together to handle requests. A request goes through controllers in the order they are linked. A request for the path `/users` will go through an `APIKeyValidator`, an `Authorizer` and finally a `UsersController`. Each of these controllers has an opportunity to respond, preventing the next controller from receiving the request.

## Advanced Routing

Right now, our application handles `GET /heroes` requests. The browser application uses the this list to populate its hero dashboard. If we click on an individual hero, the browser application will display an individual hero. When navigating to this page, the browser application makes a request to our server for an individual hero. This request contains the unique id of the selected hero in the path, e.g. `/heroes/11` or `/heroes/13`.

Our server doesn't handle this request yet - it only handles requests that have exactly the path `/heroes`. Since a request for individual heroes will have a path that changes depending on the hero, we need our route to include a *path variable*.

A path variable is a segment of route that matches a value for the same segment in the incoming request path. A path variable is a segment prefixed with a colon (`:`). For example, the route `/heroes/:id` contains a path variable named `id`. If the request path is `/heroes/1`, `/heroes/2`, and so on, the request will be sent to our `HeroesController`. The `HeroesController` will have access to the value of the path variable to determine which hero to return.

There's one hiccup. The route `/heroes/:id` no longer matches the path `/heroes`. It'd be a lot easier to organize our code if both `/heroes` and `/heroes/:id` went to our `HeroesController`; it does heroic stuff. For this reason, we can declare the `:id` portion of our route to be optional by wrapping it in square brackets. In `channel.dart`, modify the `/heroes` route:

```dart
router
  .route('/heroes/[:id]')
  .link(() => HeroesController());
```

Since the second segment of the path is optional, the path `/heroes` still matches the route. If the path contains a second segment, the value of that segment is bound to the path variable named `id`. We can access path variables through the `Request` object. In `heroes_controller.dart`, modify `handle`:

```dart
// In just a moment, we'll replace this code with something even better,
// but it's important to understand where this information comes from first!
@override
Future<RequestOrResponse> handle(Request request) async {
  if (request.path.variables.containsKey('id')) {
    final id = int.parse(request.path.variables['id']);
    final hero = _heroes.firstWhere((hero) => hero['id'] == id, orElse: () => null);
    if (hero == null) {
      return Response.notFound();
    }

    return Response.ok(hero);
  }

  return Response.ok(_heroes);
}
```

In your shell currently running the application, hit Ctrl-C to stop the application. Then, run `aqueduct serve` again. In the browser application, click on a hero and you will be taken to a detail page for that hero.

![Screenshot of Hero Detail Page](../img/run2.png)

You can verify that your server is responding correctly by executing `curl -X GET http://localhost:8888/heroes/11` to view the single hero object. You can also trigger a 404 Not Found response by getting a hero that doesn't exist.

## ResourceControllers and Operation Methods

Our `HeroesController` is OK right now, but it'll soon run into a problem: what happens when we want to create a new hero? Or update an existing hero's name? Our `handle` method will start to get unmanageable, quickly.

That's where `ResourceController` comes in. A `ResourceController` allows you to create a distinct method for each operation that we can perform on our heroes. One method will handle getting a list of heroes, another will handle getting a single hero, and so on. Each method has an annotation that identifies the HTTP method and path variables the request must have to trigger it.

In `heroes_controller.dart`, replace `HeroesController` with the following:

```dart
class HeroesController extends ResourceController {
  final _heroes = [
    {'id': 11, 'name': 'Mr. Nice'},
    {'id': 12, 'name': 'Narco'},
    {'id': 13, 'name': 'Bombasto'},
    {'id': 14, 'name': 'Celeritas'},
    {'id': 15, 'name': 'Magneta'},
  ];

  @Operation.get()
  Future<Response> getAllHeroes() async {
    return Response.ok(_heroes);
  }

  @Operation.get('id')
  Future<Response> getHeroByID() async {
    final id = int.parse(request.path.variables['id']);
    final hero = _heroes.firstWhere((hero) => hero['id'] == id, orElse: () => null);
    if (hero == null) {
      return Response.notFound();
    }

    return Response.ok(hero);
  }
}
```

Notice that we didn't have to override `handle` in `ResourceController`. A `ResourceController` implements this method to call one of our *operation methods*. An operation method - like `getAllHeroes` and `getHeroByID` - must have an `Operation` annotation. The named constructor `Operation.get` means these methods get called when the request's method is GET. An operation method must also return a `Future<Response>`.

`getHeroByID`'s annotation also has an argument - the name of our path variable `id`. If that path variable exists in the request's path, `getHeroByID` will be called. If it doesn't exist, `getAllHeroes` will be called.

!!! tip "Naming Operation Methods"
    The plain English phrase for an operation - like 'get hero by id' - is a really good name for an operation method and a good name will be useful when you generate OpenAPI documentation from your code.

Reload the application by hitting Ctrl-C in the terminal that ran `aqueduct serve` and then run `aqueduct serve` again. The browser application should still behave the same.

## Request Binding

In our `getHeroByID` method, we make a dangerous assumption that the path variable 'id' can be parsed into an integer. If 'id' were something else, like a string, `int.parse` would throw an exception. When exceptions are thrown in operation methods, the controller catches it and sends a 500 Server Error response. 500s are bad, they don't tell the client what's wrong. A 404 Not Found is a better response here, but writing the code to catch that exception and create this response is cumbersome.

Instead, we can rely on a feature of operation methods called *request binding*. An operation method can declare parameters and *bind* them to properties of the request. When our operation method gets called, it will be passed values from the request as arguments. Request bindings automatically parse values into the type of the parameter (and return a better error response if parsing fails). Change the method `getHeroByID()`:

```dart
@Operation.get('id')
Future<Response> getHeroByID(@Bind.path('id') int id) async {
  final hero = _heroes.firstWhere((hero) => hero['id'] == id, orElse: () => null);

  if (hero == null) {
    return Response.notFound();
  }

  return Response.ok(hero);
}
```

The value of the path variable `id` will be parsed as an integer and be available to this method in the `id` parameter. The `@Bind` annotation on an operation method parameter tells Aqueduct the value from the request we want bound. Using the named constructor `Bind.path` binds a path variable, and the name of that variable is indicated in the argument to this constructor.

You can bind path variables, headers, query parameters and bodies. When binding path variables, we have to specify which path variable with the argument to `@Bind.path(pathVariableName)`.

!!! tip "Bound Parameter Names"
    The name of a bound parameter doesn't have to match the name of the path variable. We could have declared it as `@Bind.path('id') int heroID`. Only the argument to `Bind`'s constructor must match the actual name of the path variable. This is valuable for other types of bindings, like headers, that may contain characters that aren't valid Dart variable names, e.g. `X-API-Key`.

The More You Know: Multi-threading and Application State
---

In this simple exercise, we used a constant list of heroes as our source of data. For a simple getting-your-feet-wet demo, this is fine. However, in a real application, you'd store this data in a database. That way you could add data to it and not risk losing it when the application was restarted.

More generally, a web server should never hang on to data that can change. While previously just a best practice, stateless web servers are becoming a requirement with the prevalence of containerization and tools like Kubernetes. Aqueduct makes it a bit easier to detect violations of this rule with its multi-threading strategy.

When you run an Aqueduct application, it creates multiple threads. Each of these threads has its own isolated heap in memory; meaning data that exists on one thread can't be accessed from other threads. In Dart, these isolated threads are called *isolates*.

An instance of your application channel is created for each isolate. Each HTTP request is given to just one of the isolates to be handled. In a sense, your one application behaves the same as running your application on multiple servers behind a load balancer. (It also makes your application substantially faster.)

If you are storing any data in your application, you'll find out really quick. Why? A request that changes data will only change that data in one of your application's isolates. When you make a request to get that data again, its unlikely that you'll see the changes - another isolate with different data will probably handle that request.

## [Next Chapter: Reading from a Database](executing-queries.md)
