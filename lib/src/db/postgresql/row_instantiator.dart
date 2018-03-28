import 'package:aqueduct/src/db/managed/relationship_type.dart';

import '../db.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';

class RowInstantiator {
  RowInstantiator(this.rootTableBuilder, this.returningValues);

  final TableBuilder rootTableBuilder;
  final List<Returnable> returningValues;

  Map<TableBuilder, Map<dynamic, ManagedObject>> distinctObjects = {};

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    try {
      return rows
          .map((row) => instanceFromRow(row.iterator, returningValues.iterator))
          .where((wrapper) => wrapper.isNew)
          .map((wrapper) => wrapper.instance)
          .toList();
    } on ValidationException catch (e) {
      throw new StateError("Database error when retrieving value. ${e.toString()}");
    }
  }

  InstanceWrapper instanceFromRow(Iterator<dynamic> rowIterator, Iterator<ColumnBuilder> mappingIterator,
      {TableBuilder forTableMapper}) {
    forTableMapper ??= rootTableBuilder;

    // Inspect the primary key first.  We are guaranteed to have the primary key come first in any rowIterator.
    rowIterator.moveNext();
    mappingIterator.moveNext();

    var primaryKeyValue = rowIterator.current;
    if (primaryKeyValue == null) {
      exhaustNullInstanceIterator(rowIterator, mappingIterator);
      return null;
    }

    var alreadyExists = true;
    var instance = getExistingInstance(forTableMapper, primaryKeyValue);
    if (instance == null) {
      alreadyExists = false;
      instance = createInstanceWithPrimaryKeyValue(forTableMapper, primaryKeyValue);
    }


    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is! TableBuilder) {
        rowIterator.moveNext();
        applyColumnValueToProperty(instance, mapper, rowIterator.current);
      } else if (mapper is TableBuilder) {
        applyRowValuesToInstance(instance, mapper as TableBuilder, rowIterator);
      }
    }

    return new InstanceWrapper(instance, !alreadyExists);
  }

  ManagedObject createInstanceWithPrimaryKeyValue(TableBuilder tableMapper, dynamic primaryKeyValue) {
    var instance = tableMapper.entity.newInstance();

    instance[tableMapper.entity.primaryKey] = primaryKeyValue;

    var typeMap = distinctObjects[tableMapper];
    if (typeMap == null) {
      typeMap = {};
      distinctObjects[tableMapper] = typeMap;
    }

    typeMap[instance[instance.entity.primaryKey]] = instance;

    return instance;
  }

  ManagedObject getExistingInstance(TableBuilder tableMapper, dynamic primaryKeyValue) {
    var byType = distinctObjects[tableMapper];
    if (byType == null) {
      return null;
    }

    return byType[primaryKeyValue];
  }

  void applyRowValuesToInstance(ManagedObject instance, TableBuilder builder, Iterator<dynamic> rowIterator) {
    if (builder.flattenedColumnsToReturn.isEmpty) {
      return;
    }

    var innerInstanceWrapper =
        instanceFromRow(rowIterator, builder.returning.iterator, forTableMapper: builder);

    if (builder.joinedBy.relationshipType == ManagedRelationshipType.hasMany) {
      // If to many, put in a managed set.
      ManagedSet list = instance[builder.joinedBy.name] ?? new ManagedSet();
      if (innerInstanceWrapper != null && innerInstanceWrapper.isNew) {
        list.add(innerInstanceWrapper.instance);
      }
      instance[builder.joinedBy.name] = list;
    } else {
      var existingInnerInstance = instance[builder.joinedBy.name];

      // If not assigned yet, assign this value (which may be null). If assigned,
      // don't overwrite with a null row that may come after. Once we have it, we have it.

      // Now if it is belongsTo, we may have already populated it with the foreign key object.
      // In this case, we do need to override it
      if (existingInnerInstance == null) {
        instance[builder.joinedBy.name] = innerInstanceWrapper?.instance;
      }
    }
  }

  void applyColumnValueToProperty(ManagedObject instance, ColumnBuilder mapper, dynamic value) {
    var desc = mapper.property;

    if (desc is ManagedRelationshipDescription) {
      // This is a belongsTo relationship (otherwise it wouldn't be a column), keep the foreign key.
      if (value != null) {
        var innerInstance = desc.destinationEntity.newInstance();
        innerInstance[desc.destinationEntity.primaryKey] = value;
        instance[desc.name] = innerInstance;
      } else {
        // If null, explicitly add null to map so the value is populated.
        instance[desc.name] = null;
      }
    } else if (desc is ManagedAttributeDescription) {
      instance[desc.name] = mapper.convertValueFromStorage(value);
    }
  }

  void exhaustNullInstanceIterator(Iterator<dynamic> rowIterator, Iterator<ColumnBuilder> mappingIterator) {
    while (mappingIterator.moveNext()) {
      var mapper = mappingIterator.current;
      if (mapper is TableBuilder) {
        var _ = instanceFromRow(rowIterator, (mapper as TableBuilder).returning.iterator);
      } else {
        rowIterator.moveNext();
      }
    }
  }
}

class InstanceWrapper {
  InstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
