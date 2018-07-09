## Resources

Resources are the things your application exposes through its HTTP API. A resource can be anything - a user profile in an application, a temperature sensor in Antarctica, or a high score for a game. For example, the GitHub API exposes organization, repository, issue and pull request resources; a social network API has profiles, posts, and user relationships.

Resources are organized into collections (e.g., all of the posts), for which individual resources within that collection can be uniquely identified (e.g., a single post). Requests are made to an application to retrieve the state of a resource or to provide the desired state of a resource. Most often, resources are represented as JSON arrays and objects. When retrieving a resource, its JSON representation is encoded into the response body. When providing the desired state of a resource, a client sends the JSON representation of the desired resource state in the request body.

For more details on the concept of a resource, see the [RFC Specification for HTTP/1.1](https://tools.ietf.org/html/rfc7231).

## Routing

Resources are identified by the path of an HTTP request. For example, the URL `http://example.com/organizations` identifies the collection of organization resources on the server `http://example.com`. The URL `http://example.com/organizations/1` identifies a single organization.

An application exposes *routes* for each resource it manages. A route is a string that matches the path of a request. When a request's path matches a route, the associated handler is invoked to handle the request. Routes look like paths, but have some additional syntax. For example, the route `/organizations` will match requests with the path `/organizations`. The route `/organizations/:id` will match the paths `/organizations/1`, `/organizations/2`, and so on.

Complex routes can be formed with additional syntax. See the guide on [routing](http/routing.md) for usage details.

## Controllers

Controllers are objects that handle requests. For example, a controller might fetch rows from a database and send them to the client in the response body. Another controller might verify the username and password of a request's Authorization header are valid.

Controllers are linked together to form a series of actions to take for a request. These linked together controllers are called a *channel*. If the above examples were linked together, the channel would check if a request were authorized before it sent a response containing database rows.

There are two flavors of controllers. An *endpoint controller* performs operations on a resource or resource collection, and always sends a response. Endpoint controllers *fulfill* requests by returning the state of a resource or by changing the state of a resource. You write most of your application-specific logic endpoint controllers.

A *middleware controller* takes an action for a request, but isn't responsible for fulfilling the request. Middleware controllers can do many different things and are often reusable in many channels. Most often, a middleware controller validates something about a request before it reaches an endpoint controller. Middleware controllers can send a response for a request, and doing so prevents any other controller in that channel from handling the request.

A channel must have exactly one endpoint controller. It can be preceded by zero or more middleware controllers. See the guides on [Controllers](http/controller.md) and [ResourceControllers](http/resource_controller.md) for usage details.

## The Application Channel

The application channel is an object that contains all of the controllers in an application. It designates one controller as the first controller to receive every request called its *entry point*. Controllers are linked to the entry point (directly or transitively) to form the entire application channel. In nearly every application, the entry point is a router; this controller splits the channel into sub-channels for a given route.

The application channel is also responsible for initializing the application's services, reading configuration files and other startup related tasks. See the guide on the [Application Channel](http/channel.md) for more details.

## Services

A service is an object that encapsulates complex tasks or algorithms, external communication or tasks that will be reused across an application. The purpose of a service object is to provide a simple interface to more detailed behavior. For example, a database connection is a service object; a user of a database connection doesn't know the details of how the connection is made or how to encode the query onto the wire, but it can still execute queries.

The primary user of service objects are controllers. Services are injected into controllers by passing them as arguments to the controller's constructor. The controller keeps a reference to the service, so that it can use it when handling a request.

For more details on injecting services, see the guide on the [Application Channel](http/channel.md).

## Isolates

Isolates are memory-isolated threads; an object created on one isolate can't be referenced by another isolate. When an application starts, one or more isolates containing replicas of your application code are spawned. This behavior effectively 'load balances' your application across multiple threads.

A benefit to this structure is that each isolate has its own set of services, like database connections. This eliminates the need for techniques like 'database connection pooling', because the entire application is effectively 'pooled'.

## Bindings

A request might contain headers, query parameters, a body and path parameters that need to be parsed, validated and used in controller code. Bindings are annotations added to variables that perform this parsing and validation automatically. Appropriate error responses are sent when a bound value can't be parsed into expected type or validation fails.

Bindings cut down on boiler plate code and reduce testing surface, making development faster and code easier to reason about. For more information on bindings, see the guide on [Resource Controllers](http/resource_controller.md).

## Queries and Data Models

Application store information in databases for persistence. Writing database queries by hand is error-prone and doesn't leverage static analysis tools that are so valuable in a Dart application. Aqueduct's ORM (Object-Relational Mapping) provides statically-typed queries that are easy to write and test.

Your application's data model is defined by creating Dart classes. Each class is mapped to a database table, and each property of that class is mapped to a column in that table. Aqueduct's command-line tool generates database migration files that detect changes in your data model that can be applied to a live, versioned database. A data model can also be represented as a JSON object to build tools on top of your application.

For more details, see the guide on [Authorization](auth/index.md).

## Authorization

OAuth 2.0 is a standardized authorization framework. Aqueduct contains a specification-compliant implementation of an OAuth 2.0 server that can be integrated directly into your application, or stood up alone to provide an authorization server for federated services. This implementation is easily customizable - it can store authorization artifacts - like tokens and client identifiers - in different types of databases or use stateless authorization mechanisms like JWT. The default implementation leverages the Aqueduct ORM to store artifacts in PostgreSQL.

For more details, see the guide on [Databases](db/index.md).

## Documentation

OpenAPI 3.0 is a standardized documentation format for HTTP APIs. Many built-in Aqueduct objects support 'automatic' documentation. Objects that are specific to your application can build on top of this to immediately document your application for every change you make.

For more details, see the guide on [OpenAPI Documentation](openapi/index.md).
