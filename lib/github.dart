import 'dart:convert' show json;
import 'dart:io';

import 'package:course_deploy/config.dart';

import 'package:github/github.dart';

DeployConfig config;
RepositorySlug _repo;

GitHub _github;

void init(DeployConfig c) {
  config = c;
  _github = GitHub(auth: Authentication.withToken(config.githubAccessToken));
  _repo = RepositorySlug.full(config.githubRepo);
}

Future<RepositoryStatus> updateStatus(
    String ref, String state, String description, String url) {
  if (state != 'error' &&
      state != 'pending' &&
      state != 'failure' &&
      state != 'success') {
    throw Exception('Bad github status state $state');
  }
  return _github.repositories.createStatus(
      _repo,
      ref,
      CreateStatus(state)
        ..description = description
        ..targetUrl = url
        ..context = config.statusContext);
}

Future<void> makeBuildComment(
    int number, String deployUrl, String unreleasedUrl) async {
  await for (IssueComment comment
      in _github.issues.listCommentsByIssue(_repo, number)) {
    if (comment.user.login == config.botUser) {
      // The bot user has already commented on this PR
      return;
    }
  }
  var body =
      "[Build Complete!]($deployUrl) ([View Log]($deployUrl/.log)).\nFor a build including unreleased targets, [click here]($unreleasedUrl).";
  await _github.issues.createComment(_repo, number, body);
  print('Made build comment on #$number');
}

Future<void> editDeletedBuildComment(int number) async {
  await for (IssueComment comment
      in _github.issues.listCommentsByIssue(_repo, number)) {
    if (comment.user.login == config.botUser) {
      await _github.request(
          "PATCH", '/repos/${_repo.fullName}/issues/comments/${comment.id}',
          body: json.encode({
            'body': "This PR has been closed and the build has been deleted."
          }));
    }
  }
}

Future<void> postToSlack(String ref) async {
  if (config.slackHook == null) return;
  var commit = await _github.git.getCommit(_repo, ref);
  if (commit == null) {
    print('Could not find ref $ref');
    return;
  }
  var url = "https://github.com/${_repo.fullName}/commit/$ref";
  var msg = "*Deploy complete!*\n<$url|`${commit.sha.substring(0, 8)}`> - " +
      commit.message.split('\n').first;
  var request = await HttpClient().postUrl(Uri.parse(config.slackHook))
    ..headers.contentType = ContentType.json
    ..write(json.encode({'text': msg}));
  await request.close();
}
