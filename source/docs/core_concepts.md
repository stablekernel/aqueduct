## Resources

Resources are the things your application exposes through its HTTP API. A resource can be anything - a user profile in an application, a temperature sensor in Antarctica, or a high score for a game. For example, the GitHub API exposes organization, repository, issue and pull request resources; a social network API has profiles, posts, and user relationships.

Resources are organized into collections (e.g., all of the posts), for which individual resources within that collection can be uniquely identified (e.g., a single post). Requests are made to an application to retrieve the state of a resource or to provide the desired state of a resource. Most often, resources are represented as JSON arrays and objects. When retrieving a resource, its JSON representation is encoded into the response body. When providing the desired state of a resource, a client sends the JSON representation of the desired resource state in the request body.

## Routing

Resources are identified by the path of an HTTP request. For example, the URL `http://example.com/organizations` identifies the collection of organization resources on the server `http://example.com`. The URL `http://example.com/organizations/1` identifies a single organization.

An application exposes routes for each resource it controls. A route is a string that maps the path of a request to an object that handles operations for a specific type of resource. Routes look like paths, but have some additional syntax. For example, the route `/organizations` will match requests with the path `/organizations`. The route `/organizations/:id` will match the paths `/organizations/1`, `/organizations/2`, and so on.

Complex routes can be formed with additional syntax. See the guide on [routing](http/routing.md) for usage details.

## Controllers

Controllers are objects that handle requests. For example, a controller might fetch rows from a database and send them to the client in the response body. Another controller might verify the username and password of a request's Authorization header are valid.

Controllers are linked together to form a series of actions to take for a request. These linked together controllers are called a *channel*. If the above examples were linked together, the channel they form would 'fetch rows from database, but only if the username and password are valid'.

There are two flavors of controllers. An *endpoint controller* performs operations on a resource and always sends a response. A *middleware controller* validates something about a request, or modifies a response sent by an endpoint controller. A channel is a zero or more middleware controllers, followed by an endpoint controller.

See the guides on [Controllers](http/controller.md) and [ResourceControllers](http/resource_controller.md) for usage details.

## The Application Channel

The application channel is an object that contains all of the controllers in an application. It designates one controller as the first controller to receive every request called its *entry point*. Controllers are linked to the entry point (directly or transitively) to form the entire application channel. In nearly every application, the entry point is a router; this controller splits the channel into sub-channels for a given route.

The application channel is also responsible for initializing the application's services and other startup related tasks. See the guide on the [Application Channel](http/channel.md) for more details.

## Services

A service is an object that encapsulates complex tasks or algorithms, external communication or tasks that will be reused across an application. The purpose of a service object is to provide a simple interface to more detailed behavior. For example, a database connection is a service object; a user of a database connection doesn't know the details of how the connection is made or how to encode the query onto the wire, but it can still execute queries.

The primary user of service objects are controllers. Services are injected into controllers by passing them as arguments to the controller's constructor. The controller keeps a reference to the service, so that it can use it when handling a request.

For more details on injecting services, see the guide on the [Application Channel](http/channel.md).

## Isolates

Isolates are memory-isolated threads; an object created on one isolate can't be referenced by another isolate. When an application starts, one or more isolates containing replicas of your application code are spawned. This behavior effectively 'load balances' your application across multiple threads.

## Bindings

A request might contain headers, query parameters, a body and path parameters that need to be parsed, validated and used in controller code. Bindings are annotations added to method parameters and controller properties that automatically perform these
