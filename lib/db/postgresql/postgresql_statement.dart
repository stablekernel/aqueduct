part of monadart;

class _PostgresqlStatement {
  QueryType command;
  String tableName;
  List<_PostgresqlStatement> joinStatements;
  Map<String, dynamic> insertValueMap;
  Map<String, dynamic> queryValueMap;
  List<String> resultColumnNames;
  List<SortDescriptor> sortDescriptors;
  String whereClause;
  int limitCount;
  int offsetCount;

  String joinType;
  String joinTableName;
  String joinTableForeignKey;
  String joinTableReferenceKey;

  String formatString;
  Map<String, dynamic> formatParameters;

  void compile() {
    switch (command) {
      case QueryType.fetch: formatString = _selectStatement; break;
      case QueryType.insert: formatString = _insertStatement; break;
      case QueryType.update: formatString = _updateStatement; break;
      case QueryType.delete: formatString = _deleteStatement; break;
      case QueryType.join: formatString = _joinStatement; break;
      case QueryType.count: formatString = ""; break;
    }
  }

  String get _selectStatement {
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("select ${resultColumnNames.join(",")} from $tableName ");

    var joinedFormatParameters = {};
    joinStatements?.forEach((join) {
      join.compile();
      queryStringBuffer.write(" ${join.formatString} ");
      if (join.formatParameters != null) {
        joinedFormatParameters .addAll(join.formatParameters);
      }
    });

    if (whereClause != null && whereClause.length > 0) {
      queryStringBuffer.write("where ${whereClause} ");
    }

    var orderingString = _orderByString;
    if (orderingString != null) {
      queryStringBuffer.write(" $orderingString ");
    }

    if (limitCount != 0) {
      queryStringBuffer.write("limit ${limitCount} ");
    }

    if (offsetCount != 0) {
      queryStringBuffer.write("offset ${offsetCount} ");
    }

    formatParameters = queryValueMap ?? {};
    formatParameters.addAll(joinedFormatParameters);

    return queryStringBuffer.toString();
  }

  String get _insertStatement {
    var orderedKeys = insertValueMap.keys;
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("insert into $tableName (${orderedKeys.join(",")}) values (${orderedKeys.map((key) => "@$key").join(",")}) ");

    if (resultColumnNames != null && resultColumnNames.length > 0) {
      queryStringBuffer.write("returning ${resultColumnNames.join(",")} ");
    }

    formatParameters = insertValueMap;

    return queryStringBuffer.toString();
  }

  String get _updateStatement {
    var insertKeys = insertValueMap.keys.toList();
    var setPairs = insertKeys.map((k) => "$k=@u_$k").toList();

    insertKeys.forEach((k) {
      var value = insertValueMap.remove(k);
      insertValueMap["u_$k"] = value;
    });

    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("update $tableName set ${setPairs.join(",")} ");

    if (whereClause != null && whereClause.length > 0) {
      queryStringBuffer.write("where ${whereClause} ");
    }

    if (resultColumnNames != null && resultColumnNames.length > 0) {
      queryStringBuffer.write("returning ${resultColumnNames.join(",")} ");
    }

    formatParameters = insertValueMap;
    if (queryValueMap != null) {
      formatParameters.addAll(queryValueMap);
    }

    return queryStringBuffer.toString();
  }

  String get _deleteStatement {
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("delete from $tableName ");

    if (whereClause != null && whereClause.length > 0) {
      queryStringBuffer.write("where $whereClause ");
    }

    formatParameters = queryValueMap;

    return queryStringBuffer.toString();
  }

  String get _joinStatement {
    var queryStringBuffer = new StringBuffer();
    queryStringBuffer.write("$joinType join $joinTableName on (");
    queryStringBuffer.write("$tableName.$joinTableReferenceKey=$joinTableName.$joinTableForeignKey");

    if (whereClause != null && whereClause.length > 0) {
     queryStringBuffer.write(" and $whereClause ");
    }

    queryStringBuffer.write(")");
    print("JOIN QVM: $queryValueMap");
    formatParameters = queryValueMap;

    return queryStringBuffer.toString();
  }

  String get _orderByString {
    if (sortDescriptors == null || sortDescriptors.length == 0) {
      return null;
    }
    var transformFunc = (SortDescriptor sd) => "${sd.key} ${(sd.order == SortDescriptorOrder.ascending ? "asc" : "desc")}";
    var joinedSortDescriptors = sortDescriptors.map(transformFunc).join(",");

    return "order by $joinedSortDescriptors";
  }

}