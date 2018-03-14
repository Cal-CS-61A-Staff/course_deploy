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
      "> This bot is in beta. Let Jen know if you encounter issues with it.";
  await _github.issues.createComment(_repo, number, body);
  print('Made build comment on #$number');
}
