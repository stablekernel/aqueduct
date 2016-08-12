// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// wildfire
///
/// A web server.
library wildfire;

import 'dart:io';
import 'dart:async';
import 'dart:mirrors';
import 'package:aqueduct/aqueduct.dart';
import 'package:scribe/scribe.dart';

export 'package:aqueduct/aqueduct.dart';
export 'package:scribe/scribe.dart';

part 'src/model/token.dart';
part 'src/model/user.dart';
part 'src/pipeline.dart';
part 'src/controller/user_controller.dart';
part 'src/controller/identity_controller.dart';
part 'src/controller/register_controller.dart';
part 'src/utilities/auth_delegate.dart';
