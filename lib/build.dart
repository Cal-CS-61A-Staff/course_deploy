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
  String output2;
  String url2;

  QueuedBuild(this.branch, this.output, this.ref, [this.url, this.pr, this.output2, this.url2]);

  int get hashCode => branch.hashCode;
  operator ==(other) => other is QueuedBuild && branch == other.branch;
}

StreamController<QueuedBuild> queue;

var active = new Set<QueuedBuild>();
var target2 = 'unreleased';

DeployConfig config;

init(DeployConfig c) {
  config = c;
  queue = new StreamController<QueuedBuild>();
  new Future(() async {
    await for (QueuedBuild build in queue.stream) {
      try {
        var activeBuild = active.lookup(build);
        if (identical(build, activeBuild)) {
          active.remove(build);
          await run(build);
        } else {
          print('Skipping build for ${build.branch} ${build.ref}. Newer build queued'); 
        }
      } catch (e) {
        print("Build for ${build.branch} ${build.ref} crashed builder (that shouldn't happen!)"); 
      }
    }
  });
}

run(QueuedBuild build) async {
  var commands = [
    [config.buildScript, build.url == null ? 'deploy' : 'pull', build.branch, build.output, '${config.prDirectory}tmp', config.buildLocation, target2, build.output2]
  ];
  IOSink log;
  if (build.url != null) {
    var file = new File('${build.output}.log');
    await file.create(recursive: true);
    log = file.openWrite();
  }
  String logUrl = build.url == null ? null : build.url + '/.log';
  if (build.ref != null) {
    github.updateStatus(build.ref, 'pending', 'Build in progress', logUrl);
  }
  for (var command in commands) {
    if (await repoShell(command, log) != 0) {
      print('Build failed!');
      log?.close();
      if (build.ref) {
        github.updateStatus(build.ref, 'failure', 'Failed to build', logUrl);
      }
      return;
    }
  }
  print('Build successful!');
  log?.close();
  if (build.ref) {
    github.updateStatus(build.ref, 'success', 'Build successful!', build.url);
  }
  if (build.pr != null) {
    github.makeBuildComment(build.pr, build.url, build.url2);
  } else {
    if (build.ref) {
      github.postToSlack(build.ref);
    }
  }
}

deleteBranch(String branch) async {
  var hash = branchHash(branch);
  await repoShell(['rm', '-r', '${config.prDirectory}${hash}_${target2}'], null);
  await repoShell(['rm', '-r', '${config.prDirectory}${hash}'], null);
  await repoShell(['rm', '${config.prDirectory}${hash}.log'], null);
  int code = await repoShell(['git', 'branch', '-D', branch], null);
  if (code != 0) print("Couldn't deleting branch $branch");
}

queueBuild(QueuedBuild build) {
  while(active.contains(build)) {
    print('Deactivating existing queued build for branch ${build.branch} ${build.ref}');
    active.remove(build);
  }
  active.add(build);
  queue.add(build);
}

queueDeployBuild(String ref) {
    queueBuild(new QueuedBuild(
        config.deployBranch, config.deployDirectory, ref));
}

queueDefaultDeployBuild() {
    queueDeployBuild(null);
}

repoShell(List<String> cmdArgs, IOSink log) async {
  bool catchError = false;
  var cmd = cmdArgs.join(" ");
  stderr.writeln("\$ $cmd");
  if (cmdArgs.length >= 2 && cmdArgs[cmdArgs.length - 2] == '||' && cmdArgs[cmdArgs.length - 1] == 'true') {
    catchError = true;
    cmdArgs = cmdArgs.sublist(0, cmdArgs.length - 2);
  }
  log?.writeln('\$ $cmd');
  var process = await Process.start(cmdArgs.first, cmdArgs.sublist(1),
      workingDirectory: config.repoDirectory, runInShell: false);
  process.stdout
      .transform(UTF8.decoder)
      .transform(new LineSplitter())
      .listen((line) {
    stdout.writeln(line);
    log?.writeln(line);
  });
  process.stderr
      .transform(UTF8.decoder)
      .transform(new LineSplitter())
      .listen((line) {
    stderr.writeln(line);
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
    queueDeployBuild(data['after']);
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
    String branch = data['pull_request']['head']['ref'];
    print('Queuing build for PR: $branch');
    String hash = branchHash(branch);
    queueBuild(new QueuedBuild(
        branch,
        '${config.prDirectory}${hash}',
        data['pull_request']['head']['sha'],
        'http://${hash}.${config.prRootDomain}',
        data['number'],
        '${config.prDirectory}${hash}_${target2}',
        'http://${hash}_${target2}.${config.prRootDomain}'));
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
