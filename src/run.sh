#!/usr/bin/env sh
docker run --mount type=bind,source="$(pwd)"/target,target=/app --rm image-maker
