import 'dart:async';
import '../application/application.dart';
import '../db/persistent_store/persistent_store.dart';

/// Mechanism to release port-consuming resources like database connections and streams.
///
/// Aqueduct applications may open many streams as part of their operation. During testing, an application
/// must be shut down gracefully to complete the tests - this includes shutting down open streams like database
/// connections so that the isolate can complete. This class allows closable instances to be registered for shutdown.
/// When shutdown of an application occurs, the registered objects are closed, thus releasing the resource they consume
/// that prevent the isolate from shutting down.
///
/// There is one registry per isolate. The order in which registrations are shut down is undefined. [close] triggers shutdown
/// and is automatically invoked by [Application.stop].
///
/// Built-in Aqueduct types that open a stream, like [PersistentStore], automatically register themselves
/// when instantiated. If you are unsure whether an object has been registered for shutdown, you may add it -
/// multiple additions have no effect on the registry, as they will only be shutdown once.
class ServiceRegistry {
  static final ServiceRegistry defaultInstance = new ServiceRegistry();

  static List<_ServiceRegistration> _registrations = [];

  /// Adds an object to the registry, registered objects are closed when [close] is invoked.
  ///
  /// When [close] is invoked on this instance, [onClose] will be invoked with [object] and [object] will be removed.
  /// This method returns [object]. This allows for concise registration and allocation:
  ///
  /// Example:
  ///       ServiceRegistry.defaultInstance.register(
  ///         new StreamController(), (c) => c.close());
  ///
  /// If [object] has already been registered, this method does nothing and [onClose] will only be invoked once.
  T register<T>(T object, FutureOr onClose(T object)) {
    if (_registrations.any((r) => identical(r.object, object))) {
      return object;
    }
    _registrations.add(new _ServiceRegistration(object, onClose));
    return object;
  }

  /// Removes an object from the registry.
  void unregister(dynamic object) {
    _registrations.removeWhere((r) => identical(r.object, object));
  }

  /// Closes all registered resources.
  ///
  /// Invokes the closing method for each object that has been [register]ed.
  Future close() async {
    await Future.wait(_registrations.map((r) => r.close()));
    _registrations = [];
  }
}

@Deprecated("3.0; renamed to ServiceRegistry")
class ResourceRegistry {
  static T add<T>(T object, FutureOr onClose(T object)) =>
      ServiceRegistry.defaultInstance.register(object, onClose);

  static void remove(dynamic object) =>
      ServiceRegistry.defaultInstance.unregister(object);

  static Future release() =>
      ServiceRegistry.defaultInstance.close();
}

typedef FutureOr _CloseFunction<T>(T object);

class _ServiceRegistration<T> {
  _ServiceRegistration(this.object, this.onClose);

  T object;
  _CloseFunction onClose;

  Future close() {
    return onClose(object);
  }
}