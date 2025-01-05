#!/bin/bash

OUTPUT=$(cd $OUTPUT && pwd);
BUILD_DIR=$(mktemp -d -t ffmpeg);
cd "$BUILD_DIR" || exit;

curl -O -L https://github.com/arthenica/ffmpeg-kit/releases/download/v6.0/ffmpeg-kit-full-6.0-ios-xcframework.zip;
unzip ffmpeg-kit-*.zip;

[[ -d $OUTPUT/xcframeworks ]] || mkdir -pv "$OUTPUT/xcframeworks";
cp -av *.xcframework "$OUTPUT/xcframeworks";

find "$OUTPUT/xcframeworks" -name "lib*.xcframework" | while read xcframework; do
  framework_name=$(basename "$(echo "$xcframework" | cut -d. -f1)");
  echo "- Copy framework headers: $framework_name";
  mkdir -pv "$OUTPUT/libs/include/$framework_name" || echo '';
  cp -v "$xcframework"/*/*.framework/Headers/*.h libs/include/"$framework_name";
done

[[ -d "$BUILD_DIR" ]] && rm -rf "$BUILD_DIR";
