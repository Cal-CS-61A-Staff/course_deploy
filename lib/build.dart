import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:github/hooks.dart';

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

  QueuedBuild(this.branch, this.output, this.ref,
      [this.url, this.pr, this.output2, this.url2]);

  int get hashCode => branch.hashCode;
  bool operator ==(dynamic other) =>
      other is QueuedBuild && branch == other.branch;
}

final queue = StreamController<QueuedBuild>();
final hookHandler = HookMiddleware();

var active = <QueuedBuild>{};
var target2 = 'unreleased';

DeployConfig config;

void init(DeployConfig c) {
  config = c;
  hookHandler.onEvent.listen(handleHook);
  Future(() async {
    await for (var build in queue.stream) {
      try {
        var activeBuild = active.lookup(build);
        if (identical(build, activeBuild)) {
          active.remove(build);
          await run(build);
        } else {
          print(
              'Skipping build for ${build.branch} ${build.ref}. Newer build queued');
        }
      } catch (e, s) {
        print(
            "Build for ${build.branch} ${build.ref} crashed builder (that shouldn't happen!)");
        print("Exception: $e");
        print("Stack trace: $s");
      }
    }
  });
}

Future<void> run(QueuedBuild build) async {
  var commands = [
    [
      config.buildScript,
      build.url == null ? 'deploy' : 'pull',
      build.branch,
      build.output,
      '${config.prDirectory}tmp',
      config.buildLocation,
      target2 ?? "",
      build.output2 ?? ""
    ]
  ];
  IOSink log;
  if (build.url != null) {
    var file = File('${build.output}.log');
    await file.create(recursive: true);
    log = file.openWrite();
  }
  var logUrl = build.url == null ? null : build.url + '/.log';
  if (build.ref != null) {
    github.updateStatus(build.ref, 'pending', 'Build in progress', logUrl);
  }
  for (var command in commands) {
    if (await repoShell(command, log) != 0) {
      print('Build failed!');
      log?.close();
      if (build.ref != null) {
        github.updateStatus(build.ref, 'failure', 'Failed to build', logUrl);
      }
      return;
    }
  }
  print('Build successful!');
  log?.close();
  if (build.ref != null) {
    github.updateStatus(build.ref, 'success', 'Build successful!', build.url);
  }
  if (build.pr != null) {
    github.makeBuildComment(build.pr, build.url, build.url2);
  } else {
    if (build.ref != null) {
      github.postToSlack(build.ref);
    }
    notifyLiveSiteBuilt();
  }
}

/// Notifies code.cs61a.org that the website has been built.
///
/// TODO(jathak): Generalize this (and probably Slack too) based on the config
void notifyLiveSiteBuilt() {
  var subdomain = "code";
  try {
    var code_domain = config.buildDomain.replaceFirstMapped(
        RegExp(r"^((?:(?:\w+:)?//)?)([\w\-]+)((?:\.[\w\-]+)*)"), (m) {
      return m.group(1) + subdomain + m.group(3);
    });
    var client = HttpClient();
    client
        .postUrl(Uri.parse("https://${code_domain}/api/_async_refresh"))
        .then((HttpClientRequest request) {
      return request.close();
    }); // fire and forget
  } catch (e, _) {
    print("Failed to notify '${subdomain}' about successful build: $e");
  }
}

/// Deletes [branch] from the cloned repo and any builds based on it.
Future<void> deleteBranch(String branch) async {
  var hash = branchHash(branch);
  await repoShell(
      ['rm', '-r', '${config.prDirectory}${hash}_${target2}'], null);
  await repoShell(['rm', '-r', '${config.prDirectory}${hash}'], null);
  await repoShell(['rm', '${config.prDirectory}${hash}.log'], null);
  var code = await repoShell(['git', 'branch', '-D', branch], null);
  if (code != 0) print("Couldn't delete branch $branch");
}

/// Queues [build] to be built.
void queueBuild(QueuedBuild build) {
  while (active.contains(build)) {
    print(
        'Deactivating existing queued build for branch ${build.branch} ${build.ref}');
    active.remove(build);
  }
  active.add(build);
  queue.add(build);
}

/// Queues a deploy of the main branch.
void queueDeployBuild(String ref) {
  queueBuild(QueuedBuild(config.deployBranch, config.deployDirectory, ref, null,
      null, config.deploySolutionsDirectory, null));
}

/// Runs a shell command from within the repo.
Future<int> repoShell(List<String> cmdArgs, IOSink log) async {
  var catchError = false;
  var cmd = cmdArgs.join(" ");
  stderr.writeln("\$ $cmd");
  if (cmdArgs.length >= 2 &&
      cmdArgs[cmdArgs.length - 2] == '||' &&
      cmdArgs[cmdArgs.length - 1] == 'true') {
    catchError = true;
    cmdArgs = cmdArgs.sublist(0, cmdArgs.length - 2);
  }
  log?.writeln('\$ $cmd');
  var process = await Process.start(cmdArgs.first, cmdArgs.sublist(1),
      workingDirectory: config.repoDirectory, runInShell: false);
  process.stdout
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) {
    stdout.writeln(line);
    log?.writeln(line);
  });
  process.stderr
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) {
    stderr.writeln(line);
    log?.writeln(line);
  });
  var code = await process.exitCode;
  return catchError ? 0 : code;
}

/// Handls an HTTP request to the builder.
void handle(HttpRequest request) => hookHandler.handleHookRequest(request);

/// Handles a webhook from GitHub.
void handleHook(HookEvent hook) {
  var now = DateTime.now();
  if (hook is UnknownHookEvent &&
      hook.event == 'push' &&
      hook.data['ref'] == 'refs/heads/${config.deployBranch}' &&
      hook.data['repository']['full_name'] == config.githubRepo) {
    print('[$now] Queuing deploy...');
    queueDeployBuild(hook.data['after'] as String);
  }
  if (hook is PullRequestEvent &&
      hook.repository.fullName == config.githubRepo) {
    var branch = hook.pullRequest.head.ref;
    switch (hook.action) {
      case 'opened':
      case 'synchronize':
        print('[$now] Queuing build for PR: $branch');
        var hash = branchHash(branch);
        queueBuild(QueuedBuild(
            branch,
            '${config.prDirectory}$hash',
            hook.pullRequest.head.sha,
            'http://$hash.${config.prRootDomain}',
            hook.number,
            '${config.prDirectory}${hash}_$target2',
            'http://${hash}_$target2.${config.prRootDomain}'));
        return;
      case 'closed':
        print('[$now] PR closed. Deleting $branch...');
        deleteBranch(branch);
        github.editDeletedBuildComment(hook.number);
        return;
      default:
        return;
    }
  }
}

String branchHash(String branch) {
  return sha1.convert(utf8.encode(branch)).toString().substring(0, 12);
}
