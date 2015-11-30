part of monadart;

class ModelController<T extends Model> extends HttpController {
  QueryAdapter adapter;

  ModelController(this.adapter) : super() {

  }

  String idPathVariableName = "id";
  T requestModel;
  Query<T> query = new Query<T>();

  @override
  void willProcessRequest(ResourceRequest req) {
    var idValue = req.path.variables[idPathVariableName];

    if (idValue != null) {
      var reflectedModel = reflectClass(T).newInstance(new Symbol(""), []);
      var actualModel = (reflectedModel.reflectee as T);
      var pk = actualModel.primaryKey;
      if (pk == null) {
        throw new QueryException(500, "$T does not have primary key", -1);
      }

      var backingType = actualModel.backingType;
      var primaryKeyDecl = backingType.declarations[new Symbol(pk)];
      var primaryKeyType = primaryKeyDecl.type;

      if (primaryKeyType.isSubtypeOf(reflectType(idValue.runtimeType))) {
        reflectedModel.setField(new Symbol(pk), idValue);
      } else {
        var sym = new Symbol("parse");
        var parseDecl = (primaryKeyType as ClassMirror).declarations[sym];
        if (parseDecl != null) {
          var value = primaryKeyType
            .invoke(sym, [idValue])
            .reflectee;

          reflectedModel.setField(new Symbol(pk), value);
        } else {
          throw new HttpResponseException(500, "Attempting to interpret ${idPathVariableName} path parameter as primary key of type $primaryKeyType");
        }
      }

      query.predicateObject = reflectedModel.reflectee;
    }
    super.willProcessRequest(req);
  }

  @override
  void didDecodeRequestBody(Map <String, dynamic> bodyMap) {
    // The bodyMap can't define the id.
    if (bodyMap[idPathVariableName] != null) {
      throw new HttpResponseException(400, "HTTP Request body may not define the primary key of a model object.");
    }

    var reflectedModel = reflectClass(T).newInstance(new Symbol(""), []);
    requestModel = reflectedModel.reflectee;
    query.valueObject = requestModel;

    requestModel.readMap(bodyMap);
  }
}