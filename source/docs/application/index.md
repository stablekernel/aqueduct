## Tasks

An Aqueduct application is centered around an *application channel*; an object that handles initialization tasks. For every application that you write, you create exactly one subclass of `ApplicationChannel` and implement its required methods. These methods prepare any [service objects](../core_concepts.md) (like database connections) and [controllers](../http/controller.md) (objects that handle requests) that your application will use.

You manage loading and reading configuration data - such as development vs. production environment options - from within an application channel.

An application channel is instantiated for each thread your application executes on.

## Guides

- [The Application Channel](channel.md)
- [Configuring an Application](configure.md)
- [Aqueduct Application Structure](structure.md)
- [Performance: Multi-threading](threading.md)
