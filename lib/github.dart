import 'dart:convert' show JSON;
import 'dart:io';

import 'package:course_deploy/config.dart';

import 'package:github/server.dart';

DeployConfig config;
RepositorySlug _repo;

GitHub _github;

init(DeployConfig c) {
  config = c;
  _github =
      new GitHub(auth: new Authentication.withToken(config.githubAccessToken));
  _repo = new RepositorySlug.full(config.githubRepo);
}

updateStatus(String ref, String state, String description, String url) {
  if (state != 'error' &&
      state != 'pending' &&
      state != 'failure' &&
      state != 'success') {
    throw new Exception('Bad github status state $state');
  }
  return _github.repositories.createStatus(
      _repo,
      ref,
      new CreateStatus(state)
        ..description = description
        ..targetUrl = url
        ..context = config.statusContext);
}

makeBuildComment(int number, String deployUrl) async {
  await for (IssueComment comment
      in _github.issues.listCommentsByIssue(_repo, number)) {
    if (comment.user.login == config.botUser) {
      // The bot user has already commented on this PR
      return;
    }
  }
  var body = "I've built your PR for you [here]($deployUrl).\n\n"
      "I'll continue to build as you push new changes. "
      "If something isn't working, you can check the [log]($deployUrl/.log). "
      "These links will continue to work until you close this PR.\n\n"
      "> Let Jen know if you encounter issues with the build bot.";
  await _github.issues.createComment(_repo, number, body);
  print('Made build comment on #$number');
}

editDeletedBuildComment(int number) async {
  await for (IssueComment comment
      in _github.issues.listCommentsByIssue(_repo, number)) {
    if (comment.user.login == config.botUser) {
      await _github.request(
          "PATCH", '/repos/${_repo.fullName}/issues/comments/${comment.id}',
          body: JSON.encode({
            'body': "This PR has been closed and the build has been deleted."
          }));
    }
  }
}

postToSlack(String ref) async {
  if (config.slackHook == null) return;
  GitCommit commit = await _github.git.getCommit(_repo, ref);
  if (commit == null) {
    print('Could not find ref $ref');
    return;
  }
  String url = "https://github.com/${_repo.fullName}/commit/$ref";
  String msg = "*Deploy complete!*\n<$url|`${commit.sha.substring(0, 8)}`> - " +
      commit.message.split('\n').first;
  HttpClientRequest request =
      await new HttpClient().postUrl(Uri.parse(config.slackHook))
        ..headers.contentType = ContentType.JSON
        ..write(JSON.encode({'text': msg}));
  await request.close();
}
