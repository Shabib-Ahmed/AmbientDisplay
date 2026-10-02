#!/bin/bash
# Builds and runs the weather harness on the Mac. Optional args: latitude longitude.
set -euo pipefail
cd "$(dirname "$0")/.."
W=AmbientDisplay/Weather
clang -fobjc-arc -framework Foundation -I"$W" \
  Scripts/weather_test.m "$W/AmbientWeatherTags.m" "$W/AmbientWeatherConditions.m" "$W/AmbientWeatherService.m" \
  -o /tmp/weather_test
/tmp/weather_test "$@"
