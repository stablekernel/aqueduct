/*
Copyright (c) 2016, Stable Kernel LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/// A server-side framework built for productivity and testability.
///
/// This library is made up of a handful of modules for common functionality needed in building a web server.
///
/// There are four primary modules in this library.
///
/// auth: Has classes for implementing OAuth 2.0 behavior. Classes in this module all begin with the word 'Auth'.
///
/// db: Exposes an ORM. Classes in this module begin with 'Managed', 'Schema', 'Query' and 'Persistent'.
///
/// http: Classes for building HTTP request and response logic. Classes in this module often begin with 'HTTP'.
///
/// application: Classes in this module begin with 'Application' and are responsible for starting and stopping web servers on a number of isolates.
library aqueduct;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:mirrors';

import 'package:meta/meta.dart';
import 'package:analyzer/analyzer.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:matcher/matcher.dart';
import 'package:postgres/postgres.dart';
import 'package:safe_config/safe_config.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as pathLib;

export 'package:logging/logging.dart';
export 'package:safe_config/safe_config.dart';

part 'application/application.dart';
part 'application/application_configuration.dart';
part 'application/isolate_server.dart';
part 'application/isolate_supervisor.dart';
part 'auth/auth_code_controller.dart';
part 'auth/auth_controller.dart';
part 'auth/authentication_server.dart';
part 'auth/authorizer.dart';
part 'auth/authorization_parser.dart';
part 'auth/client.dart';
part 'auth/protocols.dart';
part 'commands/cli_command.dart';
part 'commands/migration_runner.dart';
part 'commands/setup_command.dart';
part 'commands/template_creator.dart';
part 'db/managed/attributes.dart';
part 'db/managed/backing.dart';
part 'db/managed/context.dart';
part 'db/managed/data_model.dart';
part 'db/managed/data_model_builder.dart';
part 'db/managed/entity.dart';
part 'db/managed/object.dart';
part 'db/managed/property_description.dart';
part 'db/managed/set.dart';
part 'db/persistent_store/persistent_store.dart';
part 'db/persistent_store/persistent_store_query.dart';
part 'db/postgresql/postgresql_persistent_store.dart';
part 'db/postgresql/postgresql_schema_generator.dart';
part 'db/query/matcher_expression.dart';
part 'db/query/page.dart';
part 'db/query/predicate.dart';
part 'db/query/query.dart';
part 'db/query/sort_descriptor.dart';
part 'db/schema/migration.dart';
part 'db/schema/schema.dart';
part 'db/schema/schema_builder.dart';
part 'db/schema/schema_column.dart';
part 'db/schema/schema_table.dart';
part 'http/body_decoder.dart';
part 'http/controller_routing.dart';
part 'http/cors_policy.dart';
part 'http/documentable.dart';
part 'http/http_controller.dart';
part 'http/http_response_exception.dart';
part 'http/query_controller.dart';
part 'http/parameter_matching.dart';
part 'http/request.dart';
part 'http/request_controller.dart';
part 'http/request_path.dart';
part 'http/request_sink.dart';
part 'http/resource_controller.dart';
part 'http/response.dart';
part 'http/route_node.dart';
part 'http/router.dart';
part 'http/serializable.dart';
part 'utilities/mirror_helpers.dart';
part 'utilities/mock_server.dart';
part 'utilities/pbkdf2.dart';
part 'utilities/source_generator.dart';
part 'utilities/test_client.dart';
part 'utilities/test_matchers.dart';
part 'utilities/token_generator.dart';