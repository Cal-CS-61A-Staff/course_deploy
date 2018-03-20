import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:course_deploy/config.dart';
import 'package:course_deploy/github.dart' as github;

class QueuedBuild {
  String branch;
  String output;
  String url;
  int pr;
  String ref;

  QueuedBuild(this.branch, this.output, this.ref, [this.url, this.pr]);

  int get hashCode => branch.hashCode;
  operator ==(other) => other is QueuedBuild && branch == other.branch;
}

StreamController<QueuedBuild> queue;

var active = new Set<QueuedBuild>();

DeployConfig config;

init(DeployConfig c) {
  config = c;
  queue = new StreamController<QueuedBuild>();
  new Future(() async {
    await for (QueuedBuild build in queue.stream) {
      var activeBuild = active.lookup(build);
      if (identical(build, activeBuild)) {
        active.remove(build);
        await run(build);
      }
    }
  });
}

run(QueuedBuild build) async {
  var commands = [
    'git fetch origin ${build.branch}',
    'git checkout ${build.branch}',
    'git reset --hard origin/${build.branch}',
    config.buildScript + ' ' + (build.url == null ? 'deploy' : 'pull'),
    'cp -r ${config.buildLocation} ${config.prDirectory}tmp',
    'mv ${build.output} ${config.prDirectory}tmp2 || true',
    'mv ${config.prDirectory}tmp ${build.output} || true',
    'rm -r ${config.prDirectory}tmp2 || true'
  ];
  IOSink log;
  if (build.url != null) {
    var file = new File('${build.output}.log');
    await file.create(recursive: true);
    log = file.openWrite();
  }
  String logUrl = build.url == null ? null : build.url + '/.log';
  github.updateStatus(build.ref, 'pending', 'Build in progress', logUrl);
  for (var command in commands) {
    if (await repoShell(command, log) != 0) {
      print('Build failed!');
      log.close();
      github.updateStatus(build.ref, 'failure', 'Failed to build', logUrl);
      return;
    }
  }
  print('Build successful!');
  log?.close();
  github.updateStatus(build.ref, 'success', 'Build successful!', build.url);
  if (build.pr != null) {
    github.makeBuildComment(build.pr, build.url);
  }
}

deleteBranch(String branch) async {
  var hash = branchHash(branch);
  await repoShell('rm -r ${config.prDirectory}$hash', null);
  await repoShell('rm ${config.prDirectory}$hash.log', null);
  int code = await repoShell('git branch -D $branch', null);
  if (code != 0) print("Couldn't deleting branch $branch");
}

queueBuild(QueuedBuild build) {
  active.remove(build);
  active.add(build);
  queue.add(build);
}

repoShell(String cmd, IOSink log) async {
  bool catchError = false;
  if (cmd.endsWith(' || true')) {
    catchError = true;
    cmd = cmd.substring(0, cmd.length - 8);
  }
  log?.writeln('\$ $cmd');
  var pieces = cmd.split(' ');
  var process = await Process.start(pieces.first, pieces.sublist(1),
      workingDirectory: config.repoDirectory, runInShell: true);
  process.stdout
      .transform(UTF8.decoder)
      .transform(new LineSplitter())
      .listen((line) {
    log?.writeln(line);
  });
  process.stderr
      .transform(UTF8.decoder)
      .transform(new LineSplitter())
      .listen((line) {
    log?.writeln(line);
  });
  int code = await process.exitCode;
  return catchError ? 0 : code;
}

handle(HttpRequest request) async {
  if (request.method == 'POST' && request.uri.path == '/event') {
    var data = await request.reduce((a, b) => []..addAll(a)..addAll(b));
    var events = request.headers['X-Github-Event'];
    var signatures = request.headers['X-Hub-Signature'];
    if (events.length > 0) {
      try {
        if (!validatePayload(data, signatures.last)) {
          request.response.statusCode = 403;
          request.response.writeln('Invalid payload signature');
          request.response.close();
          return;
        }
        handleEvent(events.last, new String.fromCharCodes(data));
        request.response.writeln('Ok');
        request.response.close();
        return;
      } on Exception catch (e) {
        print(e);
      }
    }
  }
  request.response.statusCode = 404;
  request.response.close();
}

handleEvent(String event, String contents) {
  var data = JSON.decode(contents);
  if (event == 'push' &&
      data['ref'] == 'refs/heads/${config.deployBranch}' &&
      data['repository']['full_name'] == config.githubRepo) {
    print('Queueing deploy...');
    queueBuild(new QueuedBuild(
        config.deployBranch, config.deployDirectory, data['after']));
  } else if (event == 'issue_comment' &&
      data.containsKey('pull_request') &&
      data['action'] == 'created' &&
      data['repository']['full_name'] == config.githubRepo &&
      data['comment']['body'].toLowercase().startsWith('stage')) {
    print('Staging directory...');
    print('Not yet implemented');
  } else if (event == 'pull_request' &&
      (data['action'] == 'opened' || data['action'] == 'synchronize') &&
      data['pull_request']['head']['repo']['full_name'] == config.githubRepo) {
    print('Queuing build for PR...');
    String branch = data['pull_request']['head']['ref'];
    String hash = branchHash(branch);
    queueBuild(new QueuedBuild(
        branch,
        '${config.prDirectory}${hash}',
        data['pull_request']['head']['sha'],
        'http://$hash.${config.prRootDomain}',
        data['number']));
  } else if (event == 'pull_request' &&
      data['action'] == 'closed' &&
      data['pull_request']['head']['repo']['full_name'] == config.githubRepo) {
    String branch = data['pull_request']['head']['ref'];
    print('PR closed. Deleting $branch...');
    deleteBranch(branch);
    github.editDeletedBuildComment(data['number']);
  }
}

bool validatePayload(List<int> data, String signature) {
  var hmac = new Hmac(sha1, UTF8.encode(config.webhookSecret));
  return secureCompare('sha1=' + hmac.convert(data).toString(), signature);
}

String branchHash(String branch) {
  return sha1.convert(UTF8.encode(branch)).toString().substring(0, 12);
}

// from https://stackoverflow.com/questions/27006687/dart-constant-time-string-comparison
bool secureCompare(String a, String b) {
  if (a.codeUnits.length != b.codeUnits.length) return false;

  var r = 0;
  for (int i = 0; i < a.codeUnits.length; i++) {
    r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return r == 0;
}
