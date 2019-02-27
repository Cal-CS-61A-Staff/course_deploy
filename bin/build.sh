#!/bin/bash
set -eux

# Make sure pdflatex is accessible
export PATH=/usr/local/texlive/2017/bin/x86_64-linux:$PATH
#export INFOPATH=$INFOPATH:/usr/local/texlive/2017/texmf-dist/doc/info
#export MANPATH=$MANPATH:/usr/local/texlive/2017/texmf-dist/doc/man

echo "Building website..."

cd /home/cs61a/course_deploy_files/repo

export VIRTUAL_ENV=$PWD/env
export PATH=$PWD/env/bin:$PATH

# Install requirements
pip install --upgrade pip
pip install -r requirements.txt

# Run checks to determine if build is allowed. Checks will be skipped if
# the file does not exist and will be ignored if this is for a deploy build.
test ! -e scripts/checks.sh || bash scripts/checks.sh || test $1 = "deploy"
test ! -e scripts/checks.py || python3 scripts/checks.py || test $1 = "deploy"

cd src

make clean
make all
make all
