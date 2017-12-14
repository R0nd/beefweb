#!/bin/bash

set -e

source "$(dirname $0)/config.sh"

usage="Usage: $(basename $0) options
Options:
  --debug     build in debug mode
  --release   build in release mode
  --server    build server
  --webui     build webui
  --pkg       build binary package
  --all       build server, webui and binary package
  --tests     also build corresponding tests
  --verbose   generate more debug messages
  --werror    treat warnings as errors

Build mode option (--debug or --release) is required.
At least one build target (--server, --ui, --pkg or --all) is required.
"

verbose=
config=
has_targets=

enable_server=
enable_webui=
enable_pkg=
enable_werror=

for arg in "$@"; do
    case "$arg" in
        --server)
            has_targets=1
            enable_server=1
            ;;

        --webui)
            has_targets=1
            enable_webui=1
            ;;

        --pkg)
            has_targets=1
            enable_pkg=1
            ;;

        --all)
            has_targets=1
            enable_server=1
            enable_webui=1
            enable_pkg=1
            ;;

        --debug)
            config=debug
            ;;

        --release)
            config=release
            ;;

        --tests)
            enable_tests=1
            ;;

        --verbose)
            verbose=1
            ;;

        --werror)
            enable_werror=1
            ;;

        --help)
            echo "$usage"
            exit 0
            ;;

        *)
            echo "invalid command line option: $arg"
            exit 1
    esac
done

if [ -z "$config" ] || [ -z "$has_targets" ]; then
    echo "$usage"
    exit 1
fi

cd "$(dirname $0)/.."

pkg_build_dir=$(pwd)/build/$config
pkg_tmp_dir=$pkg_build_dir/tmp

server_src_dir=$(pwd)/server
server_build_dir=$(pwd)/server/build/$config
server_plugin_file=$server_build_dir/src/plugin_deadbeef/$plugin_file

webui_src_dir=$(pwd)/webui
webui_build_dir=$(pwd)/webui/build/$config

function detect_server_arch()
{
    test -e $server_plugin_file
    server_plugin_info=$(file $server_plugin_file)

    if echo $server_plugin_info | grep 'Intel 80386' > /dev/null; then
        server_arch=x86
    elif echo $server_plugin_info | grep 'x86-64' > /dev/null; then
        server_arch=x86_64
    else
        server_arch=unknown
    fi
}

function show_server_build_logs()
{
    for log_file in deps/root/src/*-stamp/*.log; do
        echo "$log_file:"
        cat $log_file
        echo
    done
}

function build_server()
{
    echo
    echo 'Building server...'
    echo

    if [ "$config" == "release" ]; then
        server_build_type=Release
    else
        server_build_type=Debug
    fi

    if [ -n "$enable_tests" ]; then
        server_enable_tests=ON
    else
        server_enable_tests=OFF
    fi

    if [ -n "$enable_werror" ]; then
        server_enable_werror=ON
    else
        server_enable_werror=OFF
    fi

    rm -rf $server_build_dir
    mkdir -p $server_build_dir
    cd $server_build_dir

    cmake \
        -DCMAKE_BUILD_TYPE=$server_build_type \
        -DENABLE_TESTS=$server_enable_tests \
        -DENABLE_WERROR=$server_enable_werror \
        $server_src_dir

    if ! cmake --build . ; then
        if [ -n "$verbose" ]; then
            show_server_build_logs
        fi

        exit 1
    fi
}

function build_webui()
{
    echo
    echo 'Building webui...'
    echo

    webui_flags=""

    if [ "$config" == "release" ]; then
        webui_flags="$webui_flags --env.release"
    fi

    if [ -n "$enable_tests" ]; then
        webui_flags="$webui_flags --env.tests"
    fi

    cd $webui_src_dir

    yarn install
    yarn run build $webui_flags
}

function build_pkg()
{
    echo
    echo 'Building package...'
    echo

    detect_server_arch

    git_rev=$(git rev-parse --short HEAD)

    rm -rf $pkg_build_dir
    mkdir -p $pkg_tmp_dir/$webui_root

    cd $pkg_tmp_dir
    cp -v -t . $server_plugin_file
    cp -v -t $webui_root $webui_build_dir/*.*

    tar czf $pkg_build_dir/$pkg_name-$pkg_version-$git_rev-$server_arch.tar.gz *

    rm -rf $pkg_tmp_dir
}

if [ -n "$enable_webui" ]; then
    build_webui
fi

if [ -n "$enable_server" ]; then
    build_server
fi

if [ -n "$enable_pkg" ]; then
    build_pkg
fi
