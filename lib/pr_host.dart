import 'dart:io';

import 'package:course_deploy/config.dart';
import 'package:http_server/http_server.dart';

String root;

init(DeployConfig config) {
  root = config.prDirectory;
}

handle(HttpRequest request) async {
  String subdomain = request.headers.host.split('.').first;
  var files = new VirtualDirectory('$root$subdomain');
  files.followLinks = true;
  var dir = new Directory('$root$subdomain${request.uri.path}');
  if (request.uri.path == '/.log') {
    files.serveFile(new File('$root$subdomain.log'), request);
  } else if (await dir.exists()) {
    var path = dir.path;
    if (!path.endsWith('/')) {
      request.response.redirect(Uri.parse(request.uri.path + '/'));
      return;
    }
    files.serveFile(new File('${path}index.html'), request);
  } else {
    files.serveRequest(request);
  }
}
