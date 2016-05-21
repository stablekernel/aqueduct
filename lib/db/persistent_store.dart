part of aqueduct;

abstract class PersistentStore {
  String foreignKeyForRelationshipDescription(RelationshipDescription desc) {
    return "${desc.name}_${desc.destinationEntity.primaryKey}";
  }

//  String typeStringForPropertyDescription(PropertyDescription desc) {
//    switch (desc.type) {
//      case PropertyType.integer: {
//        if (desc.autoincrement) {
//          return "serial";
//        } else {
//          return "int";
//        }
//      } break;
//      case PropertyType.doublePrecision: return "double precision";
//      case PropertyType.bigInteger: {
//        if (desc.autoincrement) {
//          return "bigserial";
//        } else {
//          return "bigint";
//        }
//      } break;
//      case PropertyType.boolean: return "boolean";
//      case PropertyType.datetime: return "timestamp";
//      case PropertyType.string: return "text";
//    }
//
//    throw new DataModelException("Unknown data type ${desc.type} for ${desc.name} on ${desc.entity.tableName}");
//  }
}

class DefaultPersistentStore extends PersistentStore {

}