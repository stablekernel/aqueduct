import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/runtime/orm/entity_builder.dart';
import 'package:aqueduct/src/utilities/mirror_cast.dart';
import 'package:aqueduct/src/utilities/sourcify.dart';
import 'package:runtime/runtime.dart';

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime
    implements SourceCompiler {
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
  String getPropertyName(Invocation invocation, ManagedEntity entity) {
    // It memberName is not in symbolMap, it may be because that property doesn't exist for this object's entity.
    // But it also may occur for private ivars, in which case, we reconstruct the symbol and try that.
    return entity.symbolMap[invocation.memberName] ??
      entity.symbolMap[Symbol(MirrorSystem.getName(invocation.memberName))];
  }

  @override
  dynamic dynamicConvertFromPrimitiveValue(
      ManagedPropertyDescription property, dynamic value) {
    return runtimeCast(value, reflectType(property.type.type));
  }
  
  String _getValidators(
      BuildContext context, ManagedPropertyDescription property) {
    var inverseType = "null";
    if (property is ManagedRelationshipDescription) {
      inverseType = "${property.destinationEntity.instanceType}";
    }

    // If type extends other types, we have to look for those as well.
    final findField = (ClassMirror classMirror) {
      final klass = context.analyzer.getClassFromFile(
          MirrorSystem.getName(classMirror.simpleName),
          context.resolveUri(classMirror.location.sourceUri));
      return klass.getField("${property.name}");
    };

    var type = EntityBuilder.getTableDefinitionForType(property.entity.instanceType); 
    var field = findField(type);
    while (field == null) {
      type = type.superclass;
      if (type.reflectedType == Object) {
        break;
      }
      field = findField(type);
    }

    final metadata = field.metadata.where((a) {
      final type = (RuntimeContext.current as MirrorContext).types.firstWhere(
          (t) => MirrorSystem.getName(t.simpleName) == a.name.name,
          orElse: () => null);
      return type?.isSubtypeOf(reflectType(Validate)) ?? false;
    });

    return metadata.map((m) {
      return """"() {
  final validator = ${m.toSource().substring(1)};
  final state = validator.compile(${property.type}, relationshipInverseType: $inverseType);
  return ManagedValidator(validator, state);
}()
    """;
    }).join(", ");
  }

  String _getManagedTypeInstantiator(ManagedType type) {
    if (type == null) {
      return "null";
    }

    final elementStr = type.elements == null
        ? "null"
        : _getManagedTypeInstantiator(type.elements);

    final enumStr = type.enumerationMap == null
        ? "null"
        : "{${type.enumerationMap.keys.map((k) {
            var vStr = sourcifyValue(type.enumerationMap[k]);
            return "'$k': $vStr";
          }).join(",")}}";

    return "ManagedType.make<${type.type}>(${type.kind}, $elementStr, $enumStr)";
  }

  String _getDefaultValueLiteral(ManagedAttributeDescription attribute) {
    final value = attribute.defaultValue;
    return sourcifyValue(value,
        onError:
            "The default value for '${attribute.entity.instanceType}.${attribute.name}' "
            "contains both double and single quotes");
  }

  String _getAttributeInstantiator(
      BuildContext ctx, ManagedAttributeDescription attribute) {
    final transienceStr = attribute.isTransient
        ? "Serialize(input: ${attribute.transientStatus.isAvailableAsInput}, output: ${attribute.transientStatus.isAvailableAsOutput})"
        : null;
    final validatorStr =
        attribute.isTransient ? "null" : "[${_getValidators(ctx, attribute)}]";

    return """
ManagedAttributeDescription.make<${attribute.declaredType}>(entity, '${attribute.name}',
    ${_getManagedTypeInstantiator(attribute.type)}, 
    transientStatus: $transienceStr,
    primaryKey: ${attribute.isPrimaryKey},
    defaultValue: ${_getDefaultValueLiteral(attribute)},
    unique: ${attribute.isUnique},
    indexed: ${attribute.isIndexed},
    nullable: ${attribute.isNullable},
    includedInDefaultResultSet: ${attribute.isIncludedInDefaultResultSet},
    autoincrement: ${attribute.autoincrement},
    validators: $validatorStr)    
    """;
  }

  String _getRelationshipInstantiator(
      BuildContext ctx, ManagedRelationshipDescription relationship) {
    return """
ManagedRelationshipDescription.make<${relationship.declaredType}>(
  entity,
  '${relationship.name}',
  ${_getManagedTypeInstantiator(relationship.type)},
  dataModel.entities.firstWhere((e) => e.name == '${relationship.destinationEntity.name}'),
  ${relationship.deleteRule},
  ${relationship.relationshipType},
  '${relationship.inverseKey}',
  unique: ${relationship.isUnique},
  indexed: ${relationship.isIndexed},
  nullable: ${relationship.isNullable},
  includedInDefaultResultSet: ${relationship.isIncludedInDefaultResultSet},
  validators: [${_getValidators(ctx, relationship)}])
    """;
  }

  String _getEntityConstructor(BuildContext context) {
    final attributesStr = entity.attributes.keys.map((name) {
      return "'$name': ${_getAttributeInstantiator(context, entity.attributes[name])}";
    }).join(", ");

    final uniqueStr = entity.uniquePropertySet == null
        ? "null"
        : "[${entity.uniquePropertySet.map((u) => "'${u.name}'").join(",")}]";

    final symbolMapBuffer = StringBuffer();
    entity.properties.forEach((str, val) {
      final sourcifiedKey = sourcifyValue(str);
      symbolMapBuffer.write("Symbol($sourcifiedKey): $sourcifiedKey,");
      symbolMapBuffer.write("Symbol(${sourcifyValue("$str=")}): $sourcifiedKey,");
    });

    final tableDef = EntityBuilder.getTableDefinitionForType(entity.instanceType).reflectedType.toString();

    return """() {    
final entity = ManagedEntity('${entity.tableName}', ${entity.instanceType}, ${sourcifyValue(tableDef)});
  return entity
    ..uniquePropertySet = $uniqueStr
    ..primaryKey = '${entity.primaryKey}'
    ..symbolMap = {${symbolMapBuffer.toString()}}
    ..attributes = {$attributesStr};
}()""";
  }

  String _getSetTransientValueForKeyImpl(BuildContext ctx) {
    final cases = entity.attributes.values
        .where((attr) => attr.isTransient)
        .where((attr) => attr.transientStatus.isAvailableAsInput)
        .map((attr) {
      return "case '${attr.name}': (object as ${instanceType.reflectedType}).${attr.name} = value as ${attr.declaredType}; break;";
    }).join("\n");

    return """switch (key) {
    $cases
}""";
  }

  String _getGetTransientValueForKeyImpl(BuildContext ctx) {
    final cases = entity.attributes.values
        .where((attr) => attr.isTransient)
        .where((attr) => attr.transientStatus.isAvailableAsOutput)
        .map((attr) {
      return "case '${attr.name}': return (object as ${instanceType.reflectedType}).${attr.name};";
    }).join("\n");

    return """switch (key) {
    $cases
}""";
  }

  String _getDynamicConvertFromPrimitiveValueImpl(BuildContext ctx) {
    return """/* this needs to be improved to use the property's type to fix the implementation */
return value;
    """;
  }

  String _getGetPropertyNameImpl(BuildContext ctx) {
    return "return entity.symbolMap[invocation.memberName];";
  }

  @override
  String compile(BuildContext ctx) {
    final className = "${MirrorSystem.getName(instanceType.simpleName)}";
    final originalFileUri = instanceType.location.sourceUri.toString();
    final relationshipsStr = entity.relationships.keys.map((name) {
      return "'$name': ${_getRelationshipInstantiator(ctx, entity.relationships[name])}";
    }).join(", ");

    return """
import 'package:aqueduct/aqueduct.dart';
import '$originalFileUri';

final instance = ManagedEntityRuntimeImpl();

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime {
  ManagedEntityRuntimeImpl() {
   _entity = ${_getEntityConstructor(ctx)};
  }

  ManagedEntity _entity;

  @override
  ManagedEntity get entity => _entity; 

  @override
  void finalize(ManagedDataModel dataModel) {
    _entity.relationships = {$relationshipsStr};
  }

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
    ${_getSetTransientValueForKeyImpl(ctx)}
  }
  
  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    return ManagedSet<$className>.fromDynamic(objects); 
  }
  
  @override
  dynamic getTransientValueForKey(ManagedObject object, String key) {
    ${_getGetTransientValueForKeyImpl(ctx)}
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
  String getPropertyName(Invocation invocation, ManagedEntity entity) {
    ${_getGetPropertyNameImpl(ctx)}    
  }
  
  @override
  dynamic dynamicConvertFromPrimitiveValue(ManagedPropertyDescription property, dynamic value) {
    ${_getDynamicConvertFromPrimitiveValueImpl(ctx)}  
  }
}   
    """;
  }
}
