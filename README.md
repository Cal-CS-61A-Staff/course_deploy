# course_deploy

(WIP, most of this isn't true yet)

A simple build server designed to deploy a course website. Combined with some
Caddy configs, it's designed to build and host the following:

- Each PR will be built and hosted at a subdomain based on the hashed branch.
The status will be reported back to GitHub. Once the PR is closed, the built
files for it will be deleted.

- The website will be built whenever code is pushed to master (or a
different specified branch)

- A staging domain will be maintained that symlinks assignment directories so
that they contain a build for either the latest open PR associated with that
assignment or master if there is none.

For performance reasons, the Dart server is only used for the build queue and
the PR subdomains. The deployed and staged sites are hosted by Caddy.
