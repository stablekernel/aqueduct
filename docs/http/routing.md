# Routing

Every HTTP request has a URL. A URL identifies a *resource* on a computer. In the early days of the Internet, a resource was a file. For example, the URL `http://www.geocities.com/my_page/image.jpg` would return the file `image.jpg` from the folder `my_page` on the webserver located at `www.geocities.com`. In a web application today, resources come from many other sources of data, like a database or a connected device. The job of a web application is to provide a resource for a URL, wherever that resource might come from.

A URL is made up of many parts, some of which are optional. The typical URL we see as humans looks like this: `http://stablekernel.com/about`. Most people recognize that typing this URL into a browser would take them to our company's "About" page. In other words, our "About" page is a resource and the URL identifies it.

More generally, the "About" page URL has the three required components of a URL: a *scheme* (`http`), a *host* (`stablekernel.com`) and a *path* (`/about`). The host specifies the computer responsible for providing the resource, the path indicates the 'name' of the resource and the scheme lets both the requester and the host know how they should exchange information.

An Aqueduct application receives requests when the scheme is `http` (or `https`) and the host refers to a machine where the application is running. Therefore, once the application gets the request, it only cares about the remaining component: the path.

In Aqueduct, a `Router` splits a stream of `Request`s coming into the application based on their path. This process is known as *routing*. When an application starts up, routes are registered in a subclass of `RequestSink`. Each registered route creates a new stream of requests that `RequestController`s can listen to.

When an incoming request's path matches a route, the router will send the request to the next listener for that route. Typically, routing is the first processing step a request goes through in an Aqueduct application.

## Route Specifications Match HTTP Request Paths

A route is registered by invoking `Router.route`. This method takes a *route specification* - a `String` with some syntax rules that will match the path of a request. This registration occurs when an application first starts by overriding `RequestSink.setupRouter`. For example:

```dart
class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config): super(config);

  @override
  void setupRouter(Router router) {
    router
      .route("/users")
      .listen((req) {...});
  }
}
```

The argument to `route` is the route specification string. This particular route matches the path `/users`. That is, a request for the URL `http://myserver.com/users` will be sent to the `listen` closure. (Leading and trailing slashes are stripped out when routes are compiled, so including them has no effect, but it is good style to show a leading slash.)

A path can have multiple segments (the characters between slashes). For example, the path `/users/foo` has two path segments: `users` and `foo`. Routes, too, have segments. A router matches each segment of a path against each segment of a route specification. The path and the route must also have the same number of segments. Thus, the route specification `/users/foo` would match the path `/users/foo`, but not `/users`, `/users/7` or `/users/foo/1`.

A route specification can have *path variables*. A path variable is a route segment that always succeeds in matching a path segment, and that segment is stored so that later controllers can use its value. In a route specification, a path variable starts with a colon (`:`). The name of the variable follows this colon. For example, consider the following route that declares a path variable named `userID`:

```dart
router.route("/users/:userID")
```

This route specification will match `/users/1`, `/users/2`, `/users/foo`, etc. The value of `userID` is `1`, `2` and `foo`, respectively. This route won't match `/users` or `/users/1/2`.

Routes may have optional path segments. This allows a group of routes that all refer to the same resource collection to go to the same controller. For example, the requests `/users` and `/users/1` can both be covered by a single route specification.

An optional path segment has square brackets (`[]`) around it. The brackets can go before or after slashes. For example, the following two syntaxes register a route that accepts both `/users` and `/users/:userID`:

```dart
route("/users/[:userID]")
route("/users[/:userID]")
```

Conceptually, a request with a path of `/users/1` identifies a single user, where `/users` identifies all users. Optional segments are used to create better code structure by forwarding requests that deal with a specific type of resource to the same request controller. Therefore, the code to handle one user or multiple users is written in the same place.

You may have any number of optional segments in a route specification. Each optional segment must be nested. The following route would match `/a`, `/a/b` and `/a/b/c` (but not `/a/c`):

```dart
route("/a/[b/[c]]")
```

It's pretty rare to have more than one optional segment in a route. In most circumstances, a good API has routes with just one optional segment. The first segment is the type of the resource and the second segment is an optional unique identifier for a specific resource of that type. More generally, a typical route is `/type/[:id]`. It is also fairly rare to have an optional literal segment - optionals are typically used for path variables only.

Path variables may restrict their possible values with a regular expression. The expression comes in parentheses following the path variable name. For example, the following route specification limits `userID` to numbers only:

```dart
route("/users/:userID([0-9]+)")
```

This regular expression would only apply to the `:userID` segment. Note that capture groups and parentheses in general can't be included in a route's regular expression.

Everything in between the parentheses is evaluated as the regular expression. Therefore, any additional spaces or characters will be a part of the regular expression. Since spaces aren't valid in a URL, you don't want spaces in a regular expression.

Finally, a route specification may have a special 'match-all' token, the asterisk (`*`). This token allows for any remaining request path to be matched, regardless of its contents or length. For example, the route specification `/users/*` would match the following paths:

```
/users
/users/1
/users/foo
/users/foo/bar
/users/foo/bar/something/else/and/this/goes/on/forever
```

This token is used when another medium is going to interpret the URL. For example, a request controller that reads a file might have a route `/file/*`. It uses everything after `/file` to figure out the path on the filesystem.

## Accessing Path Variables

Information that a router parses from a request path - like path variables - are stored in a `Request`'s `path`. As a `Request` passes through a `Router`, its `path` is set to an instance of this type. Later controllers access the `path` of a `Request` to help determine which resource the request is referring to. The `path` is an instance of `HTTPRequestPath`.

The `variables` of an `HTTPRequestPath` are a `Map<String, String>`, where the key is the name of the variable in the route specification and the value is the matching path segment in an incoming request. For example, consider a route specification `/users/:id`. When a request with path `/users/1` is routed, this specification will match. So, a controller would access it like so:

```dart
var identifier = request.path.variables["id"];
// identifier = "1"
```

The values in `variables` are always `String`s, since a request path is a `String`. `RequestController`s may parse path variables into types like `int`.

[HTTPController](http_controller.md) uses path variables to select a responder method to handle a request.

## Failed Matches Return 404

A `Router` will return a `Response.notFound` - a response with status code 404 - if it receives a request that no route is registered for. The router will not send this request downstream to further listeners. This behavior may be overridden by providing a closure to `Router.unhandledRequestController`, but the use-case is rare.
