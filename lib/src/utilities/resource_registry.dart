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
/// There is one registry per isolate. The order in which registrations are shut down is undefined. [release] triggers shutdown
/// and is automatically invoked by [Application.stop].
///
/// Built-in Aqueduct types that open a stream, like [PersistentStore], automatically register themselves
/// when instantiated. If you are unsure whether an object has been registered for shutdown, you may add it -
/// multiple additions have no effect on the registry, as they will only be shutdown once.
class ResourceRegistry {
  static List<_ResourceRegistration> _registrations = [];

  /// Adds an object to the registry so that it may be shut down when the application stops.
  ///
  /// When shutdown occurs, [onClose] is invoked and passed [object]. [onClose] must return a [Future]
  /// that fires when [object] has successfully shutdown. Example:
  ///
  ///       var streamController = new StreamController();
  ///       ResourceRegistry.add(streamController, (controller) => controller.close());
  ///
  /// If [object] has already been registered, this method does nothing.
  ///
  /// The return value of this is always [object]. This allows for concise registration and allocation:
  ///
  ///       var streamController = ResourceRegistry.add(new StreamController(), (c) => c.close));
  static T add<T>(T object, Future onClose(T object)) {
    if (_registrations.any((r) => identical(r.object, object))) {
      return object;
    }
    _registrations.add(new _ResourceRegistration(object, onClose));
    return object;
  }

  /// Removes an object from the registry.
  static void remove(dynamic object) {
    _registrations.removeWhere((r) => identical(r.object, object));
  }

  /// Closes all registered resources.
  ///
  /// This method is automatically invoked by [Application.stop].
  static Future release() async {
    await Future.wait(_registrations.map((r) => r.close()));
    _registrations = [];
  }
}

typedef Future _CloseFunction<T>(T object);

class _ResourceRegistration<T> {
  _ResourceRegistration(this.object, this.onClose);

  T object;
  _CloseFunction onClose;

  Future close() {
    return onClose(object);
  }
}