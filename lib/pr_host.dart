import 'dart:io';

import 'package:course_deploy/config.dart';
import 'package:http_server/http_server.dart';

String root;

void init(DeployConfig config) {
  root = config.prDirectory;
}

Future<void> handle(HttpRequest request) async {
  var subdomain = request.headers.host.split('.').first;
  var files = VirtualDirectory('$root$subdomain');
  files.followLinks = true;
  var dir = Directory('$root$subdomain${request.uri.path}');
  if (request.uri.path == '/.log') {
    request.response.headers.contentType =
        ContentType("text", "plain", charset: "utf-8");
    files.serveFile(File('$root$subdomain.log'), request);
  } else if (await dir.exists()) {
    var path = dir.path;
    if (!path.endsWith('/')) {
      request.response.redirect(Uri.parse(request.uri.path + '/'));
      return;
    }
    files.serveFile(File('${path}index.html'), request);
  } else {
    files.serveRequest(request);
  }
}
