library aqueduct;

import 'dart:io';
import 'dart:async';
import 'dart:mirrors';
import 'dart:isolate';
import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:pbkdf2/pbkdf2.dart';
import 'dart:math';
import 'package:http_server/http_server.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';
import 'package:matcher/matcher.dart';
import 'package:analyzer/analyzer.dart';
import 'package:yaml/yaml.dart';
import 'package:safe_config/safe_config.dart';

export 'package:http_server/http_server.dart';
export 'package:logging/logging.dart';
export 'package:safe_config/safe_config.dart';

part 'base/resource_pattern.dart';
part 'base/resource_request.dart';
part 'base/router.dart';
part 'base/http_controller.dart';
part 'base/response.dart';
part 'base/application.dart';
part 'base/request_handler.dart';
part 'base/controller_routing.dart';
part 'base/http_response_exception.dart';
part 'base/documentable.dart';
part 'base/pipeline.dart';
part 'base/isolate_supervisor.dart';
part 'base/isolate_server.dart';
part 'base/application_configuration.dart';
part 'base/serializable.dart';
part 'base/cors_policy.dart';

part 'auth/authenticator.dart';
part 'auth/protocols.dart';
part 'auth/token_generator.dart';
part 'auth/client.dart';
part 'auth/auth_controller.dart';
part 'auth/authorization_parser.dart';
part 'auth/authentication_server.dart';

part 'db/model_query.dart';
part 'db/model.dart';
part 'db/model_controller.dart';
part 'db/predicate.dart';
part 'db/query.dart';
part 'db/query_adapter.dart';
part 'db/query_page.dart';
part 'db/sort_descriptor.dart';
part 'db/model_attributes.dart';
part 'db/model_entity.dart';
part 'db/matcher_expression.dart';

// PostgreSQL

part 'db/postgresql/postgresl_query.dart';
part 'db/postgresql/postgresql_helpers.dart';
part 'db/postgresql/postgresql_model_adapter.dart';
part 'db/postgresql/postgresql_schema.dart';
part 'db/postgresql/postgresql_statement.dart';

part 'utilities/test_client.dart';
part 'utilities/mock_server.dart';