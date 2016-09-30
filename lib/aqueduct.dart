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
/// See http://stablekernel.github.io/aqueduct for more in-depth tutorials and guides.
library aqueduct;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:mirrors';
import 'dart:collection';

import 'package:analyzer/analyzer.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:matcher/matcher.dart';
import 'package:postgres/postgres.dart';

export 'package:logging/logging.dart';
export 'package:safe_config/safe_config.dart';
export 'package:args/args.dart';

part 'db/data_model_builder.dart';
part 'db/model_backing.dart';
part 'db/ordered_set.dart';
part 'utilities/mirror_helpers.dart';
part 'utilities/pbkdf2.dart';
part 'auth/auth_code_controller.dart';
part 'auth/auth_controller.dart';
part 'auth/authentication_server.dart';
part 'auth/authenticator.dart';
part 'auth/authorization_parser.dart';
part 'auth/client.dart';
part 'auth/protocols.dart';
part 'auth/token_generator.dart';
part 'base/application.dart';
part 'base/application_configuration.dart';
part 'base/body_decoder.dart';
part 'base/controller_routing.dart';
part 'base/cors_policy.dart';
part 'base/documentable.dart';
part 'base/http_controller.dart';
part 'base/http_response_exception.dart';
part 'base/isolate_server.dart';
part 'base/isolate_supervisor.dart';
part 'base/model_controller.dart';
part 'base/parameter_matching.dart';
part 'base/request_sink.dart';
part 'base/request.dart';
part 'base/request_controller.dart';
part 'base/request_path.dart';
part 'base/resource_controller.dart';
part 'base/response.dart';
part 'base/router.dart';
part 'base/serializable.dart';
part 'db/data_model.dart';
part 'db/matcher_expression.dart';
part 'db/model.dart';
part 'db/model_attributes.dart';
part 'db/model_context.dart';
part 'db/model_entity.dart';
part 'db/model_entity_property.dart';
part 'db/persistent_store.dart';
part 'db/persistent_store_query.dart';
part 'db/postgresql/postgresql_persistent_store.dart';
part 'db/postgresql/postgresql_schema_generator.dart';
part 'db/predicate.dart';
part 'db/query.dart';
part 'db/query_page.dart';
part 'db/schema_generator.dart';
part 'db/sort_descriptor.dart';
part 'utilities/mock_server.dart';
part 'utilities/test_client.dart';
part 'utilities/test_matchers.dart';
part 'base/route_node.dart';