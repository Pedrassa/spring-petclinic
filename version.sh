#!/usr/bin/env bash
# version.sh — single source of truth for the current release version
export APP_VERSION="3.0.0"
export BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
export GIT_SHA=$(git rev-parse --short HEAD)
export ARTIFACT_NAME="spring-petclinic-${APP_VERSION}-${GIT_SHA}.jar"

