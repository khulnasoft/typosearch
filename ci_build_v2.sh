#!/bin/bash
# TYPOSEARCH_VERSION=nightly TYPOSEARCH_TARGET=typosearch-server|typosearch-test bash ci_build_v2.sh

set -ex
PROJECT_DIR=`dirname $0 | while read a; do cd $a && pwd && break; done`
BUILD_DIR=bazel-bin

if [ -z "$TYPOSEARCH_VERSION" ]; then
  TYPOSEARCH_VERSION="nightly"
fi

ARCH_NAME="amd64"

if [[ "$@" == *"--graviton2"* ]] || [[ "$@" == *"--arm"* ]]; then
  ARCH_NAME="arm64"
fi

if [[ "$@" == *"--with-cuda"* ]]; then
  CUDA_FLAGS="--define use_cuda=on --action_env=CUDA_HOME=/usr/local/cuda --action_env=CUDNN_HOME=/usr/local/cuda"
fi

# First build protobuf
bazel build @com_google_protobuf//:protobuf_headers
bazel build @com_google_protobuf//:protobuf_lite
bazel build @com_google_protobuf//:protobuf
bazel build @com_google_protobuf//:protoc

# Build whisper
if [[ "$@" == *"--with-cuda"* ]]; then
  bazel build @whisper.cpp//:whisper_cuda_shared $CUDA_FLAGS --experimental_cc_shared_library
  /bin/cp -f $PROJECT_DIR/$BUILD_DIR/external/whisper.cpp/libwhisper_cuda_shared.so $PROJECT_DIR/$BUILD_DIR/
fi

# Finally build Typosearch
bazel build --verbose_failures --jobs=6 $CUDA_FLAGS \
  --define=TYPOSEARCH_VERSION=\"$TYPOSEARCH_VERSION\" //:$TYPOSEARCH_TARGET


if [[ "$@" == *"--build-deploy-image"* ]]; then
    echo "Creating deployment image for Typosearch $TYPOSEARCH_VERSION server ..."
    docker build --platform linux/${ARCH_NAME} --file $PROJECT_DIR/docker/deployment.Dockerfile \
          --tag typosearch/typosearch:$TYPOSEARCH_VERSION $PROJECT_DIR/$BUILD_DIR
fi

if [[ "$@" == *"--package-binary"* ]]; then
    OS_FAMILY=linux
    RELEASE_NAME=typosearch-server-$TYPOSEARCH_VERSION-$OS_FAMILY-$ARCH_NAME
    printf `md5sum $PROJECT_DIR/$BUILD_DIR/typosearch-server | cut -b-32` > $PROJECT_DIR/$BUILD_DIR/typosearch-server.md5.txt
    tar -cvzf $PROJECT_DIR/$BUILD_DIR/$RELEASE_NAME.tar.gz -C $PROJECT_DIR/$BUILD_DIR typosearch-server typosearch-server.md5.txt
    echo "Built binary successfully: $PROJECT_DIR/$BUILD_DIR/$RELEASE_NAME.tar.gz"

    GPU_DEPS_NAME=typosearch-gpu-deps-$TYPOSEARCH_VERSION-$OS_FAMILY-$ARCH_NAME
    tar -cvzf $PROJECT_DIR/$BUILD_DIR/$GPU_DEPS_NAME.tar.gz -C $PROJECT_DIR/$BUILD_DIR libonnxruntime_providers_cuda.so libonnxruntime_providers_shared.so libwhisper_cuda_shared.so
    echo "Built binary successfully: $PROJECT_DIR/$BUILD_DIR/$GPU_DEPS_NAME.tar.gz"
fi
