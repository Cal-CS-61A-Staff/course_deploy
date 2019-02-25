# course_deploy

A simple build server designed to deploy a course website. Combined with some
Caddy configs, it's designed to build and host the following:

- Each PR will be built and hosted at a subdomain based on the hashed branch.
The status will be reported back to GitHub. Once the PR is closed, the built
files for it will be deleted.

- The website will be built whenever code is pushed to master (or a
different specified branch)

For performance reasons, the Dart server is only used for the build queue and
the PR subdomains. The deployed site is hosted by Caddy.

If for some reason you need to restart the build server manually, run:

    sudo service course_deploy restart
