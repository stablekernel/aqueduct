import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/runtime/orm/orm.dart';
import 'package:aqueduct/src/runtime/runtime.dart';

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime {
  ManagedEntityRuntimeImpl(this.instanceType, this.entity);

  final ClassMirror instanceType;

  @override
  final ManagedEntity entity;

  @override
  ManagedObject instanceOfImplementation({ManagedBacking backing}) {
    final object = instanceType.newInstance(const Symbol(""), []).reflectee
    as ManagedObject;
    if (backing != null) {
      object.backing = backing;
    }
    return object;
  }

  @override
  void setTransientValueForKey(
    ManagedObject object, String key, dynamic value) {
    reflect(object).setField(Symbol(key), value);
  }

  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    final type =
    reflectType(ManagedSet, [instanceType.reflectedType]) as ClassMirror;
    return type.newInstance(const Symbol("fromDynamic"), [objects]).reflectee
    as ManagedSet;
  }

  @override
  dynamic getTransientValueForKey(ManagedObject object, String key) {
    return reflect(object).getField(Symbol(key)).reflectee;
  }

  @override
  bool isValueInstanceOf(dynamic value) {
    return reflect(value).type.isAssignableTo(instanceType);
  }

  @override
  bool isValueListOf(dynamic value) {
    final type = reflect(value).type;

    if (!type.isSubtypeOf(reflectType(List))) {
      return false;
    }

    return type.typeArguments.first.isAssignableTo(instanceType);
  }

  @override
  dynamic dynamicAccessorImplementation(Invocation invocation, ManagedEntity entity, ManagedObject object) {
    if (invocation.isGetter) {
      if (invocation.memberName == #haveAtLeastOneWhere) {
        return this;
      }

      return object[_getPropertyNameFromInvocation(invocation, entity)];
    } else if (invocation.isSetter) {
      object[_getPropertyNameFromInvocation(invocation, entity)] =
        invocation.positionalArguments.first;

      return null;
    }

    throw NoSuchMethodError.withInvocation(object, invocation);
  }

  @override
  dynamic dynamicConvertFromPrimitiveValue(ManagedPropertyDescription property, dynamic value) {
    return Runtime.current.cast(value, runtimeType: property.type.type);
  }

  String _getPropertyNameFromInvocation(Invocation invocation, ManagedEntity entity) {
    // It memberName is not in symbolMap, it may be because that property doesn't exist for this object's entity.
    // But it also may occur for private ivars, in which case, we reconstruct the symbol and try that.
    var name = entity.symbolMap[invocation.memberName] ??
      entity.symbolMap[Symbol(MirrorSystem.getName(invocation.memberName))];

    if (name == null) {
      throw ArgumentError("Invalid property access for '${entity.name}'. "
        "Property '${MirrorSystem.getName(invocation.memberName)}' does not exist on '${entity.name}'.");
    }

    return name;
  }

  @override
  String get source {
    final className = "${MirrorSystem.getName(instanceType.simpleName)}";
    final originalFileUri = instanceType.location.sourceUri.toString();

    return """
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/runtime/orm/orm.dart';
import 'package:aqueduct/src/runtime/runtime.dart';
import '$originalFileUri';
/* need to import actual model type */

final instance = ManagedEntityRuntimeImpl();

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime {
  ManagedEntityRuntimeImpl() {
   /* _entity = ManagedEntity.complete(...);*/
  }

  ManagedEntity _entity;

  @override
  String get source => throw UnsupportedError('This method is not implemented for compiled applications.');
  
  @override
  ManagedEntity get entity => _entity; 

  @override
  ManagedObject instanceOfImplementation({ManagedBacking backing}) {
    final object = $className();
    if (backing != null) {
      object.backing = backing;
    }
    return object;
  }
  
  @override
  void setTransientValueForKey(ManagedObject object, String key, dynamic value) {
    $_setTransientValueForKeyImpl;
  }
  
  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    return ManagedSet<$className>.fromDynamic(objects); 
  }
  
  @override
  dynamic getTransientValueForKey(ManagedObject object, String key) {
    $_getTransientValueForKeyImpl;
  }
  
  @override
  bool isValueInstanceOf(dynamic value) {
    return value is $className;
  }
  
  @override
  bool isValueListOf(dynamic value) {
    return value is List<$className>;
  }
  
  @override
  dynamic dynamicAccessorImplementation(Invocation invocation, ManagedEntity entity, ManagedObject object) {
    if (invocation.isGetter) {
      return null;     
      // return object[_getPropertyNameFromInvocation(invocation, entity)];
    } else if (invocation.isSetter) {
      //object[_getPropertyNameFromInvocation(invocation, entity)] =
        //invocation.positionalArguments.first;

      return null;
    }

    throw NoSuchMethodError.withInvocation(object, invocation);
  }
  
  @override
  dynamic dynamicConvertFromPrimitiveValue(ManagedPropertyDescription property, dynamic value) {
  /* this needs to be improved to use the property's type to fix the implementation */
    return Runtime.current.cast(value, runtimeType: property.type.type);
  }
}   
    """;
  }


  String get _setTransientValueForKeyImpl {
    // switch statement for each property key
    return "";
  }

  String get _getTransientValueForKeyImpl {
    // switch statement for each property key
    return "";
  }
}
