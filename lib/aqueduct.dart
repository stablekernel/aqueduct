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

import 'dart:io';
import 'dart:async';
import 'dart:mirrors';
import 'dart:isolate';
import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:pbkdf2/pbkdf2.dart';
import 'dart:math';
import 'package:logging/logging.dart';
import 'package:postgresql/postgresql.dart';
import 'package:matcher/matcher.dart';
import 'package:analyzer/analyzer.dart';

export 'package:logging/logging.dart';
export 'package:safe_config/safe_config.dart';

part 'base/request_path.dart';
part 'base/request.dart';
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
part 'base/resource_controller.dart';
part 'base/model_controller.dart';
part 'base/body_decoder.dart';

part 'auth/authenticator.dart';
part 'auth/protocols.dart';
part 'auth/token_generator.dart';
part 'auth/client.dart';
part 'auth/auth_controller.dart';
part 'auth/auth_code_controller.dart';
part 'auth/authorization_parser.dart';
part 'auth/authentication_server.dart';

part 'db/schema_generator.dart';
part 'db/data_model.dart';
part 'db/model_entity_property.dart';
part 'db/model_query.dart';
part 'db/model.dart';
part 'db/predicate.dart';
part 'db/query.dart';
part 'db/query_page.dart';
part 'db/sort_descriptor.dart';
part 'db/model_attributes.dart';
part 'db/model_entity.dart';
part 'db/matcher_expression.dart';
part 'db/persistent_store.dart';
part 'db/model_context.dart';
part 'db/persistent_store_query.dart';

// PostgreSQL

part 'db/postgresql/postgresql_persistent_store.dart';
part 'db/postgresql/postgresql_schema_generator.dart';

part 'utilities/test_client.dart';
part 'utilities/mock_server.dart';
part 'utilities/test_matchers.dart';
