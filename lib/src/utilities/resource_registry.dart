import 'dart:async';

class ResourceRegistry {
  static List<_ResourceRegistration> _registrations = [];

  static T add<T>(T object, Future onClose(T object)) {
    if (_registrations.any((r) => identical(r.object, object))) {
      return object;
    }
    _registrations.add(new _ResourceRegistration(object, onClose));
    return object;
  }

  static void remove(dynamic object) {
    _registrations.removeWhere((r) => identical(r.object, object));
  }

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