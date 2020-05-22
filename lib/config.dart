import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

class DeployConfig {
  /// The port to host the server on. (YAML: server -> port)
  final int port;

  /// The directory to store PR builds. (YAML: pull_requests -> directory)
  final String prDirectory;

  /// The domain to serve PR builds at. (YAML: pull_requests -> root_domain)
  ///
  /// If this is `example.com`, PR builds will be served at `<pr>.example.com`.
  final String prRootDomain;

  /// The domain to listen to build requests from. (YAML: build -> domain)
  final String buildDomain;

  /// The location of the cloned repo on disk. (YAML: repo -> local_directory)
  final String repoDirectory;

  /// The GitHub repo to build. (YAML: repo -> github)
  ///
  /// This should be of the format: `organization/repo-name`.
  final String githubRepo;

  /// The primary branch of the repo that should be deployed when committed to.
  ///
  /// (YAML: deploy -> branch)
  final String deployBranch;

  /// The location to store the built main website. (YAML: deploy -> directory).
  final String deployDirectory;

  /// The location to store the built solutions website.
  ///
  /// (YAML: deploy -> solutions_directory)
  final String deploySolutionsDirectory;

  /// The location of the script that should be run to build the website.
  ///
  /// TODO(jathak): Describe the arguments for the script
  /// (YAML: build -> script)
  final String buildScript;

  /// The location of the built website after running [buildScript].
  ///
  /// (YAML: build -> location)
  final String buildLocation;

  /// The secret used to verify that webhooks actually came from GitHub.
  ///
  /// (YAML: repo -> webhook_secret)
  final String webhookSecret;

  /// A GitHub bot user that should comment on PRs. (YAML: repo -> bot_user)
  final String botUser;

  /// An access token for [botUser]. (YAML: repo -> access_token)
  ///
  /// This token needs the following permissions:
  /// TODO(jathak): Add permissions
  final String githubAccessToken;

  /// The label for the status context applied to PRs by the builder.
  ///
  /// (YAML: repo -> status_context)
  final String statusContext;

  /// A URL to post status updates to Slack. (YAML: deploy -> slack_hook)
  final String slackHook;

  /// Builds a DeployConfig from a YAML document.
  factory DeployConfig.fromYaml(String text) {
    var yaml = loadYaml(text);
    String end(String path) => path.endsWith('/') ? path : '$path/';
    return DeployConfig._(
        port: yaml['server']['port'] as int,
        prDirectory: end(yaml['pull_requests']['directory'] as String),
        prRootDomain: yaml['pull_requests']['root_domain'] as String,
        buildDomain: yaml['build']['domain'] as String,
        repoDirectory: end(yaml['repo']['local_directory'] as String),
        githubRepo: yaml['repo']['github'] as String,
        deployBranch: yaml['deploy']['branch'] as String,
        deployDirectory: yaml['deploy']['directory'] as String,
        deploySolutionsDirectory:
            yaml['deploy']['solutions_directory'] as String,
        buildScript: yaml['build']['script'] as String,
        buildLocation: yaml['build']['location'] as String,
        webhookSecret: yaml['repo']['webhook_secret'] as String,
        githubAccessToken: yaml['repo']['access_token'] as String,
        statusContext: yaml['repo']['status_context'] as String,
        botUser: yaml['repo']['bot_user'] as String,
        slackHook: yaml['deploy']['slack_hook'] as String);
  }

  DeployConfig._(
      {@required this.port,
      @required this.prDirectory,
      @required this.prRootDomain,
      @required this.buildDomain,
      @required this.repoDirectory,
      @required this.githubRepo,
      @required this.deployBranch,
      @required this.deployDirectory,
      @required this.deploySolutionsDirectory,
      @required this.buildScript,
      @required this.buildLocation,
      @required this.webhookSecret,
      @required this.githubAccessToken,
      @required this.statusContext,
      @required this.botUser,
      @required this.slackHook});
}
