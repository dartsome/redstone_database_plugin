// Copyright (c) 2016, the DartSome project authors.  Please see the AUTHORS file

import 'dart:io';

import 'package:di/di.dart';
import 'package:redstone_database_plugin//database.dart';
import 'package:redstone/redstone.dart';
import 'package:shelf/shelf.dart' as shelf;

/**
 * An annotation to define a target parameter.
 *
 * Parameters annotated with this annotation
 * can be decoded from the request's body or
 * query parameters.
 *
 * If [fromQueryParams] is true, then this parameter will be decoded from
 * the query parameters.
 *
 * Example:
 *
 *     @app.Route('/services/users/add', methods: const[app.POST])
 *     addUser(@Decode() User user) {
 *       ...
 *     }
 */
class Decode {
  final bool fromQueryParams;
  const Decode({bool this.fromQueryParams: false});
}

/**
 * An annotation to define routes whose response
 * can be encoded.
 *
 * Example:
 *
 *     @app.Route('/services/users/list')
 *     @Encode()
 *     List<User> listUsers() {
 *       ...
 *     }
 *
 */
class Encode {
  const Encode();
}

/**
 * Get and configure the redstone_database plugin.
 *
 * If [db] is provided, then the plugin will initialize a database connection for
 * every request, and save it as a request attribute. If [dbPathPattern] is
 * provided, then the database connection will be initialized only for routes
 * that match the pattern.
 *
 * Usage:
 *
 *      import 'package:redstone/redstone.dart' as app;
 *      import 'package:redstone_database_plugin/plugin.dart';
 *
 *      main() {
 *
 *        app.addPlugin(getDatabasePlugin());
 *        ...
 *        app.start();
 *
 *      }
 *
 */
RedstonePlugin getDatabasePlugin([DatabaseManager db, String dbPathPattern = r'/.*']) {
  return (Manager manager) {
    if (db != null) {
      manager.addInterceptor(new Interceptor(dbPathPattern), "database connection manager",
          (Injector injector, Request request) async {
        var conn = await db.getConnection();
        request.attributes[dbConnectionAttribute] = conn;
        var resp = await chain.next();
        db.closeConnection(conn, error: chain.error);
        return resp;
      });

      manager.addParameterProvider(Decode, (dynamic metadata, Type paramType,
          String handlerName, String paramName, Request request,
          Injector injector) {
        var data;
        if (metadata.fromQueryParams) {
          var params = request.queryParameters;
          data = {};
          params.forEach((String key, List<String> value) {
            data[key] = value[0];
          });
        } else {
          data = request.body;
        }

        try {
          if (request.bodyType == JSON || request.bodyType == FORM) {
            return db.serializer.fromMap(data, paramType);
          }
          if (request.bodyType == BINARY) {
            data = new String.fromCharCodes(data as Iterable<int>);
          }
          return db.serializer.decode(data, paramType);

        } catch (e) {
          throw new ErrorResponse(HttpStatus.BAD_REQUEST, "$handlerName: Error parsing '$paramName' parameter: $e");
        }
      });

      manager.addResponseProcessor(Encode, (dynamic metadata, String handlerName, Object response, Injector injector) {
        if (response == null || response is shelf.Response) {
          return response;
        }

        return db.serializer.encode(response);
      }, includeGroups: true);
    }
  };
}
