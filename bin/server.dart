import 'dart:io';

import 'package:args/args.dart';

import 'package:course_deploy/config.dart';
import 'package:course_deploy/pr_host.dart' as pr;
import 'package:course_deploy/build.dart' as build;
import 'package:course_deploy/github.dart' as github;

DeployConfig config;

main(List<String> args) async {
  var parser = new ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.yaml');

  var result = parser.parse(args);

  var yamlText = await new File(result['config']).readAsString();

  config = new DeployConfig(yamlText);

  pr.init(config);
  build.init(config);
  github.init(config);

  var server = await HttpServer.bind('0.0.0.0', config.port);

  await for (HttpRequest request in server) {
    try {
      handle(request);
    } on Exception catch (e) {
      print(e);
    }
  }
}

handle(HttpRequest request) {
  String host = request.headers.host;
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
