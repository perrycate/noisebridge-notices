#!/usr/bin/env sh
docker run --name image-maker --mount type=bind,source="$(pwd)"/target,target=/app --rm image-maker
