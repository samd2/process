#!/bin/bash

# Copyright 2020 Rene Rivera, Sam Darwin
# Distributed under the Boost Software License, Version 1.0.
# (See accompanying file LICENSE.txt or copy at http://boost.org/LICENSE_1_0.txt)

set -e
export TRAVIS_BUILD_DIR=$(pwd)
export DRONE_BUILD_DIR=$(pwd)
export TRAVIS_BRANCH=$DRONE_BRANCH
export VCS_COMMIT_ID=$DRONE_COMMIT
export GIT_COMMIT=$DRONE_COMMIT
export REPO_NAME=$DRONE_REPO
export USER=$(whoami)
export CC=${CC:-gcc}
export PATH=~/.local/bin:/usr/local/bin:$PATH
export BRANCH_TO_TEST="$TRAVIS_BRANCH"

if [ "$DRONE_JOB_BUILDTYPE" == "boost" ]; then

echo '==================================> INSTALL'

PROJECT_TO_TEST=`basename $TRAVIS_BUILD_DIR`
echo "Testing $PROJECT_TO_TEST"
if [ $TRAVIS_OS_NAME = "osx" ]; then true brew install gcc5; true brew install valgrind; true brew install llvm; TOOLSET=clang; BOOST_TEST_CATCH_SYSTEM_ERRORS=no; MULTITHREAD=-j8; else TOOLSET=gcc-5; REPORT_CI=--boost-process-report-ci USE_VALGRIND="testing.launcher=valgrind valgrind=on"; fi
BOOST=$HOME/boost-local
git init $BOOST
cd $BOOST
echo Branch to test  $BRANCH_TO_TEST
if [ $BRANCH_TO_TEST = "master" ]; then BOOST_BRANCH=master; else BOOST_BRANCH=develop; fi
git remote add --no-tags -t $BOOST_BRANCH origin https://github.com/boostorg/boost.git
git fetch --depth=1
git checkout $BOOST_BRANCH
git submodule update --init --merge
git remote set-branches --add origin $BOOST_BRANCH
git pull --recurse-submodules || true
git submodule update --init
git checkout $BOOST_BRANCH
git submodule foreach "git reset --quiet --hard; git clean -fxd"
git reset --hard; git clean -fxd
git status
echo "Removing $BOOST/libs/$BOOST_REMOVE"
rm -rf $BOOST/libs/$BOOST_REMOVE
cp -rp $TRAVIS_BUILD_DIR/../$PROJECT_TO_TEST/ $BOOST/libs/$PROJECT_TO_TEST
TRAVIS_BUILD_DIR=$BOOST/libs/$PROJECT_TO_TEST
./bootstrap.sh
./b2 headers
cd $BOOST/libs/$PROJECT_TO_TEST/test
echo BOOST_TEST_CATCH_SYSTEM_ERRORS $BOOST_TEST_CATCH_SYSTEM_ERRORS

echo '==================================> SCRIPT'

../../../b2 $MULTITHREAD with-valgrind address-model=64 architecture=x86 $USE_VALGRIND toolset=$TOOLSET cxxflags="--coverage -DBOOST_TRAVISCI_BUILD -std=$CXX_STANDARD" linkflags="--coverage" -sBOOST_BUILD_PATH=. $REPORT_CI
../../../b2 $MULTITHREAD without-valgrind address-model=64 architecture=x86 toolset=$TOOLSET cxxflags="--coverage -DBOOST_TRAVISCI_BUILD -std=$CXX_STANDARD" linkflags="--coverage" -sBOOST_BUILD_PATH=. $REPORT_CI

echo '==================================> AFTER_SUCCESS'

mkdir -p $TRAVIS_BUILD_DIR/coverals
find ../../../bin.v2/ -name "*.gcda" -exec cp "{}" $TRAVIS_BUILD_DIR/coverals/ \;
find ../../../bin.v2/ -name "*.gcno" -exec cp "{}" $TRAVIS_BUILD_DIR/coverals/ \;
git clone https://github.com/linux-test-project/lcov.git lcov_dir
GCOV_VERSION=""
if [[ "$TOOLSET" == *"-"* ]]; then GCOV_VERSION="--gcov-tool gcov-${TOOLSET#*-}"; fi
LCOV="$BOOST/libs/$PROJECT_TO_TEST/test/lcov_dir/bin/lcov $GCOV_VERSION"
$LCOV --directory $TRAVIS_BUILD_DIR/coverals --base-directory ./ --capture --output-file $TRAVIS_BUILD_DIR/coverals/coverage.info
cd $BOOST
$LCOV --remove $TRAVIS_BUILD_DIR/coverals/coverage.info "*.cpp" "/usr*" "*/$PROJECT_TO_TEST/test/*" $IGNORE_COVERAGE "*/$PROJECT_TO_TEST/tests/*" "*/$PROJECT_TO_TEST/examples/*" "*/$PROJECT_TO_TEST/example/*" -o $TRAVIS_BUILD_DIR/coverals/coverage.info
OTHER_LIBS=`grep "submodule .*" .gitmodules | sed 's/\[submodule\ "\(.*\)"\]/"\*\/boost\/\1\.hpp" "\*\/boost\/\1\/\*"/g'| sed "/\"\*\/boost\/process\/\*\"/d" | sed ':a;N;$!ba;s/\n/ /g'`
echo $OTHER_LIBS
eval "$LCOV --remove $TRAVIS_BUILD_DIR/coverals/coverage.info $OTHER_LIBS -o $TRAVIS_BUILD_DIR/coverals/coverage.info" > /dev/null
cd $TRAVIS_BUILD_DIR
gem install coveralls-lcov
coveralls-lcov coverals/coverage.info


fi
