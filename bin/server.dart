import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';

import 'package:course_deploy/config.dart';
import 'package:course_deploy/pr_host.dart' as pr;
import 'package:course_deploy/build.dart' as build;
import 'package:course_deploy/github.dart' as github;

/// The parsed configuration for the server.
DeployConfig config;

/// Starts a course_deploy server.
///
/// Configuration is determined by the --config flag.
Future<void> main(List<String> args) async {
  var parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.yaml');

  var result = parser.parse(args);

  var yamlText = await File(result['config'] as String).readAsString();

  config = DeployConfig.fromYaml(yamlText);

  pr.init(config);
  build.init(config);
  github.init(config);

  var server = await HttpServer.bind('0.0.0.0', config.port);

  print('Scheduling periodic builds...');
  var now = DateTime.now();
  Timer(
      DateTime(
              now.year,
              now.month,
              now.day +
                  1 /* next day so that we don't mistakenly schedule an event for earlier today */,
              3,
              0,
              0)
          .difference(now),
      () => scheduleBuilds(Duration(days: 1)));

  await for (HttpRequest request in server) {
    try {
      handle(request);
    } on Exception catch (e) {
      print(e);
    }
  }
}

void scheduleBuilds(Duration period) {
  Timer.periodic(period, (Timer t) {
    try {
      build.queueDeployBuild(null);
    } on Exception catch (e) {
      print(e);
    }
  });
}

void handle(HttpRequest request) {
  var host = request.headers.host;
  if (host == config.buildDomain) {
    build.handle(request);
  } else if (host.endsWith(config.prRootDomain)) {
    pr.handle(request);
  } else {
    request.response.statusCode = 500;
    request.response.writeln("Invalid request to $host");
    request.response.close();
  }
}
