import 'dart:async';
import '../application/application.dart';
import '../db/persistent_store/persistent_store.dart';

/// An object that manages the cleanup of service objects when an application is stopped.
///
/// You register objects with the registry to provide automatic cleanup of service objects.
/// When an application is stopped (typically during testing), all registered objects are
/// destroyed in an object-specific way.
///
/// Services that open ports will stop an application from stopping gracefully, so it is important
/// that your application releases them when stopping.
///
/// There is one registry per isolate. The order in which registrations are shut down is undefined. [close] triggers shutdown
/// and is automatically invoked by [Application.stop].
///
/// Built-in Aqueduct types that open a stream, like [PersistentStore], automatically register themselves
/// when instantiated. If you are unsure whether an object has already been registered, you may re-register it -
/// multiple registrations have no effect.
class ServiceRegistry {
  static final ServiceRegistry defaultInstance = ServiceRegistry();

  List<_ServiceRegistration> _registrations = [];

  /// Register [object] to be destroyed when your application is stopped.
  ///
  /// When [close] is invoked on this instance, [onClose] will be invoked with [object]. The registered
  /// object is removed so that subsequent invocations of [close] do not attempt to release a resource again.
  ///
  /// This method returns [object]. This allows for concise registration and allocation:
  ///
  /// Example:
  ///       var controller = ServiceRegistry.defaultInstance.register(
  ///         new StreamController(), (c) => c.close());
  ///
  /// If [object] has already been registered, this method does nothing and [onClose] will only be invoked once.
  T register<T>(T object, FutureOr onClose(T object)) {
    if (_registrations.any((r) => identical(r.object, object))) {
      return object;
    }
    _registrations.add(_ServiceRegistration<T>(object, onClose));
    return object;
  }

  /// Removes an object from the registry.
  ///
  /// You must clean up [object] manually.
  void unregister(dynamic object) {
    _registrations.removeWhere((r) => identical(r.object, object));
  }

  /// Cleans up all registered objects.
  ///
  /// This method invokes the 'onClose' method for each object that has been [register]ed.
  ///
  /// Registered objects are removed so that subsequent invocations of this method have no effect.
  Future close() async {
    await Future.wait(_registrations.map((r) => r.close()));
    _registrations = [];
  }
}

typedef _CloseFunction<T> = FutureOr Function(T object);

class _ServiceRegistration<T> {
  _ServiceRegistration(this.object, this.onClose);

  T object;
  _CloseFunction<T> onClose;

  Future close() async {
    await onClose(object);
  }
}
