import 'dart:async';

import 'package:aqueduct/src/openapi/openapi.dart';

import '../db/db.dart';
import 'http.dart';

/// A [Controller] that implements basic CRUD operations for a [ManagedObject].
///
/// Instances of this class map a REST API call
/// directly to a database [Query]. For example, this [Controller] handles an HTTP PUT request by executing an update [Query]; the path variable in the request
/// indicates the value of the primary key for the updated row and the HTTP request body are the values updated.
///
/// When routing to a [ManagedObjectController], you must provide the following route pattern, where <name> can be any string:
///
///       router.route("/<name>/[:id]")
///
/// You may optionally use the static method [ManagedObjectController.routePattern] to create this string for you.
///
/// The mapping for HTTP request to action is as follows:
///
/// - GET /<name>/:id -> Fetch Object by ID
/// - PUT /<name>/:id -> Update Object by ID, HTTP Request Body contains update values.
/// - DELETE /<name>/:id -> Delete Object by ID
/// - POST /<name> -> Create new Object, HTTP Request Body contains update values.
/// - GET /<name> -> Fetch instances of Object
///
/// You may use this class without subclassing, but you may also subclass it to modify the executed [Query] prior to its execution, or modify the returned [Response] after the query has been completed.
///
/// The HTTP response body is encoded according to [responseContentType].
///
/// GET requests with no path parameter can take extra query parameters to modify the request. The following are the available query parameters:
///
/// - count (integer): restricts the number of objects fetched to count. By default, this is null, which means no restrictions.
/// - offset (integer): offsets the fetch by offset amount of objects. By default, this is null, which means no offset.
/// - pageBy (string): indicates the key in which to page by. See [Query.pageBy] for more information on paging. If this value is passed as part of the query, either pageAfter or pagePrior must also be passed, but only one of those.
/// - pageAfter (string): indicates the page value and direction of the paging. pageBy must also be set. See [Query.pageBy] for more information.
/// - pagePrior (string): indicates the page value and direction of the paging. pageBy must also be set. See [Query.pageBy] for more information.
/// - sortBy (string): indicates the sort order. The syntax is 'sortBy=key,order' where key is a property of [InstanceType] and order is either 'asc' or 'desc'. You may specify multiple sortBy parameters.
class ManagedObjectController<InstanceType extends ManagedObject>
    extends ResourceController {
  /// Creates an instance of a [ManagedObjectController].
  ManagedObjectController(ManagedContext context) : super() {
    _query = Query<InstanceType>(context);
  }

  /// Creates a new [ManagedObjectController] without a static type.
  ///
  /// This method is used when generating instances of this type dynamically from runtime values,
  /// where the static type argument cannot be defined. Behaves just like the unnamed constructor.
  ///
  ManagedObjectController.forEntity(
      ManagedEntity entity, ManagedContext context)
      : super() {
    _query = Query.forEntity(entity, context);
  }

  /// Returns a route pattern for using [ManagedObjectController]s.
  ///
  /// Returns the string "/$name/[:id]", to be used as a route pattern in a [Router] for instances of [ResourceController] and subclasses.
  static String routePattern(String name) {
    return "/$name/[:id]";
  }

  Query<InstanceType> _query;

  /// Executed prior to a fetch by ID query.
  ///
  /// You may modify the [query] prior to its execution in this method. The [query] will have a single matcher, where the [InstanceType]'s primary key
  /// is equal to the first path argument in the [Request]. You may also return a new [Query],
  /// but it must have the same [InstanceType] as this controller. If you return null from this method, no [Query] will be executed
  /// and [didNotFindObject] will immediately be called.
  FutureOr<Query<InstanceType>> willFindObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after a fetch by ID query that found a matching instance.
  ///
  /// By default, returns a [Response.ok] with the encoded instance. The [result] is the fetched [InstanceType]. You may override this method
  /// to provide some other behavior.
  FutureOr<Response> didFindObject(InstanceType result) {
    return Response.ok(result);
  }

  /// Executed after a fetch by ID query that did not find a matching instance.
  ///
  /// By default, returns [Response.notFound]. You may override this method to provide some other behavior.
  FutureOr<Response> didNotFindObject() {
    return Response.notFound();
  }

  @Operation.get("id")
  Future<Response> getObject(@Bind.path("id") String id) async {
    var primaryKey = _query.entity.primaryKey;
    final parsedIdentifier =
        _getIdentifierFromPath(id, _query.entity.properties[primaryKey]);
    _query.where((o) => o[primaryKey]).equalTo(parsedIdentifier);

    _query = await willFindObjectWithQuery(_query);

    var result = await _query?.fetchOne();

    if (result == null) {
      return didNotFindObject();
    } else {
      return didFindObject(result);
    }
  }

  /// Executed prior to an insert query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no values will be inserted and [didInsertObject] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willInsertObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after an insert query is successful.
  ///
  /// By default, returns [Response.ok]. The [object] is the newly inserted [InstanceType]. You may override this method to provide some other behavior.
  FutureOr<Response> didInsertObject(InstanceType object) {
    return Response.ok(object);
  }

  @Operation.post()
  Future<Response> createObject() async {
    final instance = _query.entity.instanceOf() as InstanceType;
    instance.readFromMap(request.body.as());
    _query.values = instance;

    _query = await willInsertObjectWithQuery(_query);
    var result = await _query?.insert();

    return didInsertObject(result);
  }

  /// Executed prior to a delete query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no delete operation will be performed and [didNotFindObjectToDeleteWithID] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willDeleteObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after an object was deleted.
  ///
  /// By default, returns [Response.ok] with no response body. You may override this method to provide some other behavior.
  FutureOr<Response> didDeleteObjectWithID(dynamic id) {
    return Response.ok(null);
  }

  /// Executed when no object was deleted during a delete query.
  ///
  /// Defaults to return [Response.notFound]. You may override this method to provide some other behavior.
  FutureOr<Response> didNotFindObjectToDeleteWithID(dynamic id) {
    return Response.notFound();
  }

  @Operation.delete("id")
  Future<Response> deleteObject(@Bind.path("id") String id) async {
    var primaryKey = _query.entity.primaryKey;
    final parsedIdentifier =
        _getIdentifierFromPath(id, _query.entity.properties[primaryKey]);
    _query.where((o) => o[primaryKey]).equalTo(parsedIdentifier);

    _query = await willDeleteObjectWithQuery(_query);

    var result = await _query?.delete();

    if (result == 0) {
      return didNotFindObjectToDeleteWithID(id);
    } else {
      return didDeleteObjectWithID(id);
    }
  }

  /// Executed prior to a update query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no values will be inserted and [didNotFindObjectToUpdateWithID] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willUpdateObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after an object was updated.
  ///
  /// By default, returns [Response.ok] with the encoded, updated object. You may override this method to provide some other behavior.
  FutureOr<Response> didUpdateObject(InstanceType object) {
    return Response.ok(object);
  }

  /// Executed after an object not found during an update query.
  ///
  /// By default, returns [Response.notFound]. You may override this method to provide some other behavior.
  FutureOr<Response> didNotFindObjectToUpdateWithID(dynamic id) {
    return Response.notFound();
  }

  @Operation.put("id")
  Future<Response> updateObject(@Bind.path("id") String id) async {
    var primaryKey = _query.entity.primaryKey;
    final parsedIdentifier =
        _getIdentifierFromPath(id, _query.entity.properties[primaryKey]);
    _query.where((o) => o[primaryKey]).equalTo(parsedIdentifier);

    final instance = _query.entity.instanceOf() as InstanceType;
    instance.readFromMap(request.body.as());
    _query.values = instance;

    _query = await willUpdateObjectWithQuery(_query);

    var results = await _query?.updateOne();
    if (results == null) {
      return didNotFindObjectToUpdateWithID(id);
    } else {
      return didUpdateObject(results);
    }
  }

  /// Executed prior to a fetch query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no objects will be fetched and [didFindObjects] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willFindObjectsWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after a list of objects has been fetched.
  ///
  /// By default, returns [Response.ok] with the encoded list of founds objects (which may be the empty list).
  FutureOr<Response> didFindObjects(List<InstanceType> objects) {
    return Response.ok(objects);
  }

  @Operation.get()
  Future<Response> getObjects(
      {

      /// Limits the number of objects returned.
      @Bind.query("count") int count = 0,

      /// An integer offset into an ordered list of objects.
      ///
      /// Use with count.
      ///
      /// See pageBy for an alternative form of offsetting.
      @Bind.query("offset") int offset = 0,

      /// The property of this object to page by.
      ///
      /// Must be a key in the object type being fetched. Must
      /// provide either pageAfter or pagePrior. Use with count.
      @Bind.query("pageBy") String pageBy,

      /// A value-based offset into an ordered list of objects.
      ///
      /// Objects are returned if their
      /// value for the property named by pageBy is greater than
      /// the value of pageAfter. Must provide pageBy, and the type
      /// of the property designated by pageBy must be the same as pageAfter.
      @Bind.query("pageAfter") String pageAfter,

      /// A value-based offset into an ordered list of objects.
      ///
      /// Objects are returned if their
      /// value for the property named by pageBy is less than
      /// the value of pageAfter. Must provide pageBy, and the type
      /// of the property designated by pageBy must be the same as pageAfter.
      @Bind.query("pagePrior") String pagePrior,

      /// Designates a sorting strategy for the returned objects.
      ///
      /// This value must take the form 'name,asc' or 'name,desc', where name
      /// is the property of the returned objects to sort on.
      @Bind.query("sortBy") List<String> sortBy}) async {
    _query.fetchLimit = count;
    _query.offset = offset;

    if (pageBy != null) {
      QuerySortOrder direction;
      String pageValue;
      if (pageAfter != null) {
        direction = QuerySortOrder.ascending;
        pageValue = pageAfter;
      } else if (pagePrior != null) {
        direction = QuerySortOrder.descending;
        pageValue = pagePrior;
      } else {
        return Response.badRequest(body: {
          "error":
              "missing required parameter 'pageAfter' or 'pagePrior' when 'pageBy' is given"
        });
      }

      var pageByProperty = _query.entity.properties[pageBy];
      if (pageByProperty == null) {
        throw Response.badRequest(body: {"error": "cannot page by '$pageBy'"});
      }

      dynamic parsed = _parseValueForProperty(pageValue, pageByProperty);
      _query.pageBy((t) => t[pageBy], direction,
          boundingValue: parsed == "null" ? null : parsed);
    }

    if (sortBy != null) {
      sortBy.forEach((sort) {
        var split = sort.split(",").map((str) => str.trim()).toList();
        if (split.length != 2) {
          throw Response.badRequest(body: {
            "error":
                "invalid 'sortyBy' format. syntax: 'name,asc' or 'name,desc'."
          });
        }
        if (_query.entity.properties[split.first] == null) {
          throw Response.badRequest(
              body: {"error": "cannot sort by '$sortBy'"});
        }
        if (split.last != "asc" && split.last != "desc") {
          throw Response.badRequest(body: {
            "error":
                "invalid 'sortBy' format. syntax: 'name,asc' or 'name,desc'."
          });
        }
        var sortOrder = split.last == "asc"
            ? QuerySortOrder.ascending
            : QuerySortOrder.descending;
        _query.sortBy((t) => t[split.first], sortOrder);
      });
    }

    _query = await willFindObjectsWithQuery(_query);

    var results = await _query?.fetch();

    return didFindObjects(results);
  }

  @override
  APIRequestBody documentOperationRequestBody(
      APIDocumentContext context, Operation operation) {
    if (operation.method == "POST" || operation.method == "PUT") {
      return APIRequestBody.schema(
          context.schema.getObjectWithType(InstanceType),
          contentTypes: ["application/json"],
          required: true);
    }

    return null;
  }

  @override
  Map<String, APIResponse> documentOperationResponses(
      APIDocumentContext context, Operation operation) {
    switch (operation.method) {
      case "GET":
        if (operation.pathVariables.isEmpty) {
          return {
            "200": APIResponse.schema(
                "Returns a list of objects.",
                APISchemaObject.array(
                    ofSchema: context.schema.getObjectWithType(InstanceType))),
            "400": APIResponse.schema("Invalid request.",
                APISchemaObject.object({"error": APISchemaObject.string()}))
          };
        }

        return {
          "200": APIResponse.schema("Returns a single object.",
              context.schema.getObjectWithType(InstanceType)),
          "404": APIResponse("No object found.")
        };
      case "PUT":
        return {
          "200": APIResponse.schema("Returns updated object.",
              context.schema.getObjectWithType(InstanceType)),
          "404": APIResponse("No object found."),
          "400": APIResponse.schema("Invalid request.",
              APISchemaObject.object({"error": APISchemaObject.string()})),
          "409": APIResponse.schema("Object already exists",
              APISchemaObject.object({"error": APISchemaObject.string()})),
        };
      case "POST":
        return {
          "200": APIResponse.schema("Returns created object.",
              context.schema.getObjectWithType(InstanceType)),
          "400": APIResponse.schema("Invalid request.",
              APISchemaObject.object({"error": APISchemaObject.string()})),
          "409": APIResponse.schema("Object already exists",
              APISchemaObject.object({"error": APISchemaObject.string()}))
        };
      case "DELETE":
        return {
          "200": APIResponse("Object successfully deleted."),
          "404": APIResponse("No object found."),
        };
    }

    return {};
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    final ops = super.documentOperations(context, route, path);

    final entityName = _query.entity.name;

    if ((path.parameters
                ?.where((p) => p.location == APIParameterLocation.path)
                ?.length ??
            0) >
        0) {
      ops["get"]?.id = "get$entityName";
      ops["put"]?.id = "update$entityName";
      ops["delete"]?.id = "delete$entityName";
    } else {
      ops["get"]?.id = "get${entityName}s";
      ops["post"]?.id = "create$entityName";
    }

    return ops;
  }

  dynamic _getIdentifierFromPath(
      String value, ManagedPropertyDescription desc) {
    return _parseValueForProperty(value, desc, onError: Response.notFound());
  }

  dynamic _parseValueForProperty(String value, ManagedPropertyDescription desc,
      {Response onError}) {
    if (value == "null") {
      return null;
    }

    try {
      switch (desc.type.kind) {
        case ManagedPropertyType.string:
          return value;
        case ManagedPropertyType.bigInteger:
          return int.parse(value);
        case ManagedPropertyType.integer:
          return int.parse(value);
        case ManagedPropertyType.datetime:
          return DateTime.parse(value);
        case ManagedPropertyType.doublePrecision:
          return double.parse(value);
        case ManagedPropertyType.boolean:
          return value == "true";
        case ManagedPropertyType.list:
          return null;
        case ManagedPropertyType.map:
          return null;
        case ManagedPropertyType.document:
          return null;
      }
    } on FormatException {
      throw onError ?? Response.badRequest();
    }

    return null;
  }
}
