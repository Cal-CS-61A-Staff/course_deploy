#!/bin/bash

set -euxo pipefail

main() {
	test "$#" -eq 5 || { 1>&2 echo "Invalid number of arguments passed." && return 1; }

	git fetch origin "$2"
	git clean -q -d -f -x
	git checkout -f "$2"
	git clean -q -d -f -x

	# Make sure pdflatex is accessible
	export PATH="/usr/local/texlive/2017/bin/x86_64-linux:${PATH}"
	#export INFOPATH="${INFOPATH}:/usr/local/texlive/2017/texmf-dist/doc/info"
	#export MANPATH="${MANPATH}:/usr/local/texlive/2017/texmf-dist/doc/man"

	# Run checks to determine if build is allowed. Checks will be skipped if
	# the file does not exist and will be ignored if this is for a deploy build.
	test ! -e scripts/checks.sh || bash scripts/checks.sh || test "$1" = "deploy"
	test ! -e scripts/checks.py || python3 scripts/checks.py || test "$1" = "deploy"

	local args=(--no-print-directory -C src)
	make "${args[@]}" clean && { make "${args[@]}" all && make "${args[@]}" all && make "${args[@]}" -j1 all; }

	rm -r -f -- "$4"
	mv -T -- "$3" "$4"
	mv -T -- "$5" "$3"
}

main "$@"
