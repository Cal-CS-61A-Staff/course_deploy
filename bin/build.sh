#!/bin/bash

set -euo pipefail

call_make() {
	make "$@" BUILDPASS=1      # NO, please do NOT attempt to simplify these lines via a loop, 'if', '&&', '||', etc.
	make "$@" BUILDPASS=2      # Turns out Bash "helpefully" ignores set -e in many compound statements and keeps going, making the script claim success.
	make "$@" BUILDPASS=3 -j1  # Proof: try executing the following: (set -ex; false && false; echo "you probably do not expect this output")
}

postmake() {
	local buildloc="$1" output="$2" prtmp="$3"
	rm -r -f -- "${prtmp}"
	if [ -d "${output}" ]; then  # Don't move if it doesn't exist for some reason
		mv -T -- "${output}" "${prtmp}" || true  # Can still fail due to a race condition, but ultimately this doesn't matter; what matters is that the output is updated
	fi
	mv -T -- "${buildloc}" "${output}"
}

main() {
	test "$#" -eq 6 || { 1>&2 echo "Invalid number of arguments passed." && return 1; }

	local make_args=(--no-print-directory -C src)
	local target1="all"
	local buildtype="$1" branch="$2" output="$3" prtmp="$4" buildloc="$5" target2="$6" output2="$7"

	# Make sure pdflatex is accessible
	local TEXLIVE_PATH="/usr/local/texlive/2017"
	export PATH="${TEXLIVE_PATH}/bin/x86_64-linux:${PATH}"
	#export INFOPATH="${TEXLIVE_PATH}/texmf-dist/doc/info:${INFOPATH}"
	#export MANPATH="${TEXLIVE_PATH}/texmf-dist/doc/man:${MANPATH}"

	set -x

	git fetch    -q --prune origin "${branch}"
	git clean    -q -d -f -x
	git checkout -q    -f --detach origin/"${branch}"
	git clean    -q -d -f -x

	call_make "${make_args[@]}" BUILDTYPE="${buildtype}" "${target1}"
	postmake "${buildloc}" "${output}" "${prtmp}"

	if [ "${buildtype}" = "pull" ]; then
		cp -a -T -- "${output}" "${buildloc}"  # Copy back the output to continue building other targets

		# Check if target2 is out-of-date (but do NOT fail if it's absent) by checking if the exit code is exactly 1 (and not 2, which might mean the target is absent)
		if make -q -j1 "${make_args[@]}" BUILDTYPE="${buildtype}" "${target2}" 1>/dev/null 2>/dev/null; then
			:  # Nothing to do -- but we need DO this block like this, because the test below will fail if we attempt to use && above (because Bash is stupid)
		elif [ 1 -eq "$?" ]; then
			call_make "${make_args[@]}" BUILDTYPE="${buildtype}" "${target2}" "${target1}"
			postmake "${buildloc}" "${output2}" "${prtmp}"
		fi
	fi
}

main "$@"
