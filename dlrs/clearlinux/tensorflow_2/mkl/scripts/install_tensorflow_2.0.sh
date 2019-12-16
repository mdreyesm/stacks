#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
set -e
set -u
set -o pipefail

export CFLAGS="-mfma -msse -msse2 -msse3 -mssse3 -mcx16 -msahf -mmovbe -msse4.2 -msse4.1 -mlzcnt -mavx -mavx2 -mtune=skylake-avx512 -m64 "
export CXXFLAGS="-mfma -msse -msse2 -msse3 -mssse3 -mcx16 -msahf -mmovbe -msse4.2 -msse4.1 -mlzcnt -mavx -mavx2 -mtune=skylake-avx512 -m64 "
export OPTM=3
export TF_BRANCH=r2.0
export TF_TAG=v2.0.0
export USE_BAZEL_VERSION=0.26.1
export PYTHON_BIN_PATH=/usr/bin/python
export PROJECT=tensorflow
export USE_DEFAULT_PYTHON_LIB_PATH=1
export TF_NEED_JEMALLOC=1
export TF_NEED_KAFKA=0
export TF_NEED_OPENCL_SYCL=0
export TF_NEED_GCP=0
export TF_NEED_HDFS=0
export TF_NEED_S3=0
export TF_ENABLE_XLA=1
export TF_NEED_GDR=0
export TF_NEED_VERBS=0
export TF_NEED_OPENCL=0
export TF_NEED_MPI=0
export TF_NEED_TENSORRT=0
export TF_SET_ANDROID_WORKSPACE=0
export TF_DOWNLOAD_CLANG=0
export TF_NEED_CUDA=0
export HTTP_PROXY=$(echo "$http_proxy" | sed -e 's/\/$//')
export HTTPS_PROXY=$(echo "$https_proxy" | sed -e 's/\/$//')

run() {
  echo "=============================================================="
  printf "$(date) -- %s"
  printf "%s\n" "$@"
  echo "=============================================================="
}

python_pkgs(){
# install dependencies for tensorflow build
  pip install pip six wheel numpy setuptools mock "future>=0.17.1"
  pip install keras_applications==1.0.6 --no-deps
  pip install keras_preprocessing==1.0.5 --no-deps
}

get_project() {
  git clone https://github.com/${PROJECT}/${PROJECT}.git 
  cd tensorflow && git checkout ${TF_TAG}
}

apply_patch() {
	# apply patches/fixes to TF
	# patch to upgrade curl
	PATCHES=( 33064 )
	GIT_URL="https://patch-diff.githubusercontent.com/raw/tensorflow/tensorflow/pull/"
	# git default config
	git config --global user.email "example@example.com"
	git config --global user.name "example@example.com"
	for ptch in "${PATCHES[@]}"; do
			wget $GIT_URL$ptch.patch && git am $ptch.patch
	done
  # fix for: https://github.com/tensorflow/tensorflow/issues/32026
  echo "Adding fix for: https://github.com/tensorflow/tensorflow/issues/32026"
  sed -i 's/RUY_DONOTUSEDIRECTLY_AVX512 1/RUY_DONOTUSEDIRECTLY_AVX512 0/g' /tensorflow/tensorflow/lite/experimental/ruy/platform.h
  
  # fix for https://github.com/clearlinux/distribution/issues/1151
  wget https://raw.githubusercontent.com/clearlinux-pkgs/tensorflow/master/0001-Add-grpc-fix-for-gettid.patch 
  git am 0001-Add-grpc-fix-for-gettid.patch
 
}

build () {
  # configure and build tensorflow avx2 and avx512 versions
  # build avx2 TF
  mkdir -p /tmp/tf/avx2
  export ARCH=skylake
  export TUNE=skylake
  export TF_BUILD_MAVX=MAVX2
  export CC_OPT_FLAGS="-march=${ARCH} -mtune=${TUNE}"
  export CFLAGS="$CFLAGS -march=${ARCH}"
  export CXXFLAGS="$CXXFLAGS -march=${ARCH}"
  
  ./configure
  bazel --output_base=/tmp/bazel build  \
  --repository_cache=/tmp/cache  \
  --config=opt --config=mkl --config=v2 \
  --copt=-O${OPTM} --copt=-mtune=${TUNE} \
  --copt=-march=${ARCH} --copt=-Wa,-mfence-as-lock-add=yes \
   //tensorflow/tools/pip_package:build_pip_package

  # generate pip package
  bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tf/

  # build avx512 TF
  mkdir -p /tmp/tf/avx512
  export ARCH=skylake-avx512
  export TUNE=cascadelake
  export TF_BUILD_MAVX=MAVX512
  export CC_OPT_FLAGS="-march=${ARCH} -mtune=${TUNE}"
  export CFLAGS="$CFLAGS -march=${ARCH}"
  export CXXFLAGS="$CXXFLAGS -march=${ARCH}"

  bazel clean && ./configure
  bazel --output_base=/tmp/bazel build  \
  --repository_cache=/tmp/cache  \
  --config=opt --config=mkl --config=v2 \
  --copt=-O${OPTM} --copt=-mtune=${TUNE} \
  --copt=-march=${ARCH} --copt=-Wa,-mfence-as-lock-add=yes \
   //tensorflow/tools/pip_package:build_pip_package

  # generate pip package
  bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tf/avx512
}

begin="$(date +%s)"
run "get ${PROJECT}" && get_project 
run "apply patches for CVEs" && apply_patch
run "install python deps" && python_pkgs
run "config, build ${PROJECT}" && build
finish="$(date +%s)"
runtime=$(((finish-begin)/60))
run "Done in :  $runtime minute(s)"
