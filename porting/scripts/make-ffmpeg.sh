#!/bin/bash

OUTPUT=$(cd $OUTPUT && pwd);
BUILD_DIR=$(mktemp -d -t ffmpeg);
cd $BUILD_DIR;

curl -O -L https://github.com/arthenica/ffmpeg-kit/releases/download/v6.0/ffmpeg-kit-full-6.0-ios-xcframework.zip;
unzip ffmpeg-kit-*.zip;

[[ -d $OUTPUT/xcframeworks ]] || mkdir -pv $OUTPUT/xcframeworks;
cp -av *.xcframework $OUTPUT/xcframeworks;

[[ -d "$BUILD_DIR" ]] && rm -rf $BUILD_DIR;
