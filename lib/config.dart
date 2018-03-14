import 'package:yaml/yaml.dart';

class DeployConfig {
  var _yaml;
  DeployConfig(String yamlText) {
    _yaml = loadYaml(yamlText);
  }

  int get port => _yaml['server']['port'];

  String get prDirectory => _end(_yaml['pull_requests']['directory']);

  String get prRootDomain => _yaml['pull_requests']['root_domain'];

  String get buildDomain => _yaml['build']['domain'];

  String get repoDirectory => _end(_yaml['repo']['local_directory']);

  String get githubRepo => _yaml['repo']['github'];

  String get deployBranch => _yaml['deploy']['branch'];

  String get deployDirectory => _yaml['deploy']['directory'];

  String get buildScript => _yaml['build']['script'];

  String get buildLocation => _end(_yaml['build']['location']);

  String get webhookSecret => _yaml['repo']['webhook_secret'];

  String get githubAccessToken => _yaml['repo']['access_token'];

  String get statusContext => _yaml['repo']['status_context'];

  String get botUser => _yaml['repo']['bot_user'];

  String _end(String path) => path.endsWith('/') ? path : '$path/';
}
