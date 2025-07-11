#!/usr/bin/make
#
# Copyright 2018 CSP Config Management Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

######################################################################

##### CONFIG #####

REPO := kpt.dev/configsync

# Some of our recipes use bash syntax, so explicitly set the shell to bash.
SHELL := /bin/bash

# List of dirs containing go code owned by Nomos
NOMOS_CODE_DIRS := pkg cmd e2e
NOMOS_GO_PKG := $(foreach dir,$(NOMOS_CODE_DIRS),./$(dir)/...)

# Directory containing all build artifacts.  We need abspath here since
# mounting a directory as a docker volume requires an abspath.  This should
# eventually be pushed down into where docker commands are run rather than
# requiring all our paths to be absolute.
OUTPUT_DIR := $(abspath .output)

# Self-contained GOPATH dir.
GO_DIR := $(OUTPUT_DIR)/go

# Base image used for all golang containers
# Uses trusted google-built golang image
GOLANG_IMAGE_VERSION := 1.24.3
GOLANG_IMAGE := google-go.pkg.dev/golang:$(GOLANG_IMAGE_VERSION)
# Base image used for debian containers
# When updating you can use this command:
# gcloud container images list-tags gcr.io/gke-release/debian-base --filter="tags:bookworm*"
DEBIAN_BASE_IMAGE := gcr.io/gke-release/debian-base:bookworm-v1.0.4-gke.17
# Base image used for gcloud install, primarily for test images.
# We use -slim for a smaller base image where we can choose which components to install.
# https://cloud.google.com/sdk/docs/downloads-docker#docker_image_options
GCLOUD_IMAGE_VERSION := 513.0.0
GCLOUD_IMAGE := gcr.io/google.com/cloudsdktool/google-cloud-cli:$(GCLOUD_IMAGE_VERSION)-slim
# Base image used for docker cli install, primarily used for test images.
DOCKER_CLI_IMAGE_VERSION := 20.10.14
DOCKER_CLI_IMAGE := gcr.io/cloud-builders/docker:$(DOCKER_CLI_IMAGE_VERSION)

# Directory containing installed go binaries.
BIN_DIR := $(GO_DIR)/bin

# Vendored. Use "go get <module>" to update.
GO_LICENSES := $(BIN_DIR)/go-licenses

ADDLICENSE := $(BIN_DIR)/addlicense

CONTROLLER_GEN := $(BIN_DIR)/controller-gen

KIND := $(BIN_DIR)/kind

# crane cli version used for publishing OCI images
# used by tests or local make targets
CRANE := $(BIN_DIR)/crane

GO_JUNIT_REPORT := $(BIN_DIR)/go-junit-report

# End vendored tools

# golangci-lint is GPL, so it must not be vendored.
GOLANGCI_LINT_VERSION := v1.63.4
GOLANGCI_LINT := $(BIN_DIR)/golangci-lint

KUSTOMIZE_VERSION := v5.4.2-gke.0
KUSTOMIZE := $(BIN_DIR)/kustomize
KUSTOMIZE_STAGING_DIR := $(OUTPUT_DIR)/third_party/kustomize

HELM_VERSION := v3.15.3-gke.6
HELM := $(BIN_DIR)/helm
HELM_STAGING_DIR := $(OUTPUT_DIR)/third_party/helm

COSIGN_VERSION := v2.4.1
COSIGN := $(BIN_DIR)/cosign

GIT_SYNC_VERSION := v4.4.2-gke.1__linux_amd64
GIT_SYNC_IMAGE_NAME := gcr.io/config-management-release/git-sync:$(GIT_SYNC_VERSION)

OTELCONTRIBCOL_VERSION := v0.118.0-gke.10
OTELCONTRIBCOL_IMAGE_NAME := gcr.io/config-management-release/otelcontribcol:$(OTELCONTRIBCOL_VERSION)

# Directory used for staging Docker contexts.
STAGING_DIR ?= $(OUTPUT_DIR)/staging

# Directory used for staging the manifest primitives.
NOMOS_MANIFEST_STAGING_DIR := $(STAGING_DIR)/operator
OSS_MANIFEST_STAGING_DIR := $(STAGING_DIR)/oss

# Directory that gets mounted into /tmp for build and test containers.
TEMP_OUTPUT_DIR := $(OUTPUT_DIR)/tmp

# Directory containing Deployment yamls with image paths spliced in
GEN_DEPLOYMENT_DIR := $(OUTPUT_DIR)/deployment

# Directory containing generated test yamls
TEST_GEN_YAML_DIR := $(OUTPUT_DIR)/test/yaml

# Use git tags to set version string.
ifeq ($(origin VERSION), undefined)
VERSION := $(shell git describe --tags --always --dirty --long)
endif

# UID of current user
UID := $(shell id -u)

# GID of current user
GID := $(shell id -g)

# GCP project that owns container registry for local dev build.
ifeq ($(origin GCP_PROJECT), undefined)
GCP_PROJECT := $(shell gcloud config get-value project)
endif

# Use BUILD_ID as a unique identifier for prow jobs, otherwise default to USER
BUILD_ID ?= $(USER)
GCR_PREFIX ?= $(GCP_PROJECT)/$(BUILD_ID)

GCS_PREFIX ?= gs://$(GCP_PROJECT)/config-sync
GCS_BUCKET ?= $(GCS_PREFIX)/$(shell git rev-parse HEAD)

LOCATION ?= us

# Allow arbitrary registry name, but default to GCR with prefix if not provided
REGISTRY ?= gcr.io/$(GCR_PREFIX)

# Registry used for retagging previously built images
OLD_REGISTRY ?= $(REGISTRY)

# Registry which hosts images related to test infrastructure
TEST_INFRA_PROJECT ?= kpt-config-sync-ci-artifacts
TEST_INFRA_REGISTRY ?= $(LOCATION)-docker.pkg.dev/$(TEST_INFRA_PROJECT)/test-infra
INFRA_IMAGE_PREFIX := infrastructure-public-image
# Arbitrary semver to indicate infra versioning. Can be bumped in the future
# if there are notable changes. Bumping this will force all infra images to
# be re-published.
INFRA_VERSION := v2.0.0
INFRA_IMAGE_VERSION := $(INFRA_IMAGE_PREFIX)-$(INFRA_VERSION)-$(shell git rev-parse --short HEAD)

# Docker image used for build and test. This image does not support CGO.
# When upgrading this tag, the image will be rebuilt locally during presubmits.
# After the change is submitted, a postsubmit job will publish the new tag.
# There is no need to manually publish this image.
BUILDENV_IMAGE := $(TEST_INFRA_REGISTRY)/buildenv:$(INFRA_VERSION)-go$(GOLANG_IMAGE_VERSION)-gcloud$(GCLOUD_IMAGE_VERSION)
# The buildenv image is also tagged with a git sha so that it can be traced
# back to commit it was built from.
BUILDENV_SHA_IMAGE := $(TEST_INFRA_REGISTRY)/buildenv:$(INFRA_IMAGE_VERSION)

# Nomos docker images containing all binaries.
RECONCILER_IMAGE := reconciler
RECONCILER_MANAGER_IMAGE := reconciler-manager
ADMISSION_WEBHOOK_IMAGE := admission-webhook
HYDRATION_CONTROLLER_IMAGE := hydration-controller
HYDRATION_CONTROLLER_WITH_SHELL_IMAGE := $(HYDRATION_CONTROLLER_IMAGE)-with-shell
OCI_SYNC_IMAGE := oci-sync
HELM_SYNC_IMAGE := helm-sync
NOMOS_IMAGE := nomos
ASKPASS_IMAGE := gcenode-askpass-sidecar
RESOURCE_GROUP_IMAGE := resource-group-controller
# List of Config Sync images. Used to generate image-related variables/targets.
IMAGES := \
	$(RECONCILER_IMAGE) \
	$(RECONCILER_MANAGER_IMAGE) \
	$(ADMISSION_WEBHOOK_IMAGE) \
	$(HYDRATION_CONTROLLER_IMAGE) \
	$(HYDRATION_CONTROLLER_WITH_SHELL_IMAGE) \
	$(OCI_SYNC_IMAGE) \
	$(HELM_SYNC_IMAGE) \
	$(NOMOS_IMAGE) \
	$(ASKPASS_IMAGE) \
	$(RESOURCE_GROUP_IMAGE)

# nomos binary for local run.
NOMOS_LOCAL := $(BIN_DIR)/linux_amd64/nomos

# Allows an interactive docker build or test session to be interrupted
# by Ctrl-C.  This must be turned off in case of non-interactive runs,
# like in CI/CD.
DOCKER_INTERACTIVE := --interactive
HAVE_TTY := $(shell [ -t 0 ] && echo 1 || echo 0)
ifeq ($(HAVE_TTY), 1)
	DOCKER_INTERACTIVE += --tty
endif

# Suppresses docker output on build.
#
# To turn off, for example:
#   make DOCKER_BUILD_QUIET="" deploy
DOCKER_BUILD_QUIET ?= --quiet

# Suppresses gcloud output.
GCLOUD_QUIET := --quiet

# Developer focused docker image tag.
ifeq ($(origin IMAGE_TAG), undefined)
IMAGE_TAG := $(shell git describe --tags --always --dirty --long)
endif
# Tag used for retagging previously built images
OLD_IMAGE_TAG ?= $(IMAGE_TAG)

# define a function for dynamically evaluating image tags
# e.g. $(call gen_image_tag,reconciler) => $(REGISTRY)/reconciler:$(IMAGE_TAG)
gen_image_tag = $(REGISTRY)/$(1):$(IMAGE_TAG)

DOCKER_RUN_ARGS = \
	$(DOCKER_INTERACTIVE)                                              \
	-u $(UID):$(GID)                                                   \
	-v $(GO_DIR):/go                                                   \
	-v $$(pwd):/go/src/$(REPO)                                         \
	-v $(GO_DIR)/std/linux_amd64_static:/usr/local/go/pkg/linux_amd64_static    \
	-v $(GO_DIR)/std/linux_arm64_static:/usr/local/go/pkg/linux_arm64_static    \
	-v $(GO_DIR)/std/darwin_amd64_static:/usr/local/go/pkg/darwin_amd64_static   \
	-v $(GO_DIR)/std/darwin_arm64_static:/usr/local/go/pkg/darwin_arm64_static   \
	-v $(GO_DIR)/std/windows_amd64_static:/usr/local/go/pkg/windows_amd64_static   \
	-v $(TEMP_OUTPUT_DIR):/tmp                                         \
	-v $${HOME}/.config:/.config                                       \
	-v $${HOME}/.gsutil:/.gsutil                                       \
	-w /go/src/$(REPO)                                                 \
	--rm                                                               \
	$(BUILDENV_IMAGE)                                                  \

# Common build-arg defaults to define in one place
DOCKER_BUILD_ARGS = \
	--build-arg VERSION=$(VERSION) \
	--build-arg GOLANG_IMAGE=$(GOLANG_IMAGE) \
	--build-arg DEBIAN_BASE_IMAGE=$(DEBIAN_BASE_IMAGE) \
	--build-arg GCLOUD_IMAGE=$(GCLOUD_IMAGE) \
	--build-arg DOCKER_CLI_IMAGE=$(DOCKER_CLI_IMAGE)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Add binary directories to PATH (prioritize .output/go/bin -> $GOPATH/bin -> $PATH)
PATH := $(BIN_DIR):$(GOBIN):$(PATH)

##### SETUP #####

.DEFAULT_GOAL := all

.PHONY: $(OUTPUT_DIR)
$(OUTPUT_DIR):
	@echo "+++ Creating the local build output directory: $(OUTPUT_DIR)"
	@mkdir -p \
		$(STAGING_DIR) \
		$(TEMP_OUTPUT_DIR) \
		$(TEST_GEN_YAML_DIR) \
		$(NOMOS_MANIFEST_STAGING_DIR) \
		$(OSS_MANIFEST_STAGING_DIR) \
		$(GEN_DEPLOYMENT_DIR)

# These directories get mounted by DOCKER_RUN_ARGS, so we have to create them
# before invoking docker.
.PHONY: buildenv-dirs
buildenv-dirs:
	@mkdir -p \
		$(BIN_DIR) \
		$(GO_DIR)/src/$(REPO) \
			$(GO_DIR)/std/linux_amd64_static \
			$(GO_DIR)/std/linux_arm64_static \
			$(GO_DIR)/std/darwin_amd64_static \
			$(GO_DIR)/std/darwin_arm64_static \
			$(GO_DIR)/std/windows_amd64_static \
		$(TEMP_OUTPUT_DIR)

##### TARGETS #####

include Makefile.build
-include Makefile.docs
include Makefile.e2e
-include Makefile.prow
include Makefile.gen
include Makefile.oss
include Makefile.oss.prow
include Makefile.reconcilermanager
-include Makefile.release

.PHONY: all
# Run tests, cleanup dependencies, and generate CRDs in the buildenv container
all: buildenv-dirs
	@docker run $(DOCKER_RUN_ARGS) \
		make all-local

.PHONY: all-local
# Run tests, cleanup dependencies, and generate CRDs locally
all-local: test deps clientgen configsync-crds

# Cleans all artifacts.
.PHONY: clean
clean:
	@echo "+++ Cleaning $(OUTPUT_DIR)"
	@rm -rf $(OUTPUT_DIR)

.PHONY: build-status
build-status:
	@./scripts/build-status.sh

.PHONY: test-unit
test-unit: buildenv-dirs "$(KUSTOMIZE)"
	@./scripts/test-unit.sh $(NOMOS_GO_PKG)

# small unit test to verify the behavior of an example kustomization for manual install
.PHONY: test-kustomization
test-kustomization:
	$(MAKE) build-manifests \
		STAGING_DIR=$(OUTPUT_DIR)/testing \
		REGISTRY=gcr.io/cs-test \
		IMAGE_TAG=placeholder \
		GIT_SYNC_VERSION=placeholder \
		OTELCONTRIBCOL_VERSION=placeholder
	@./scripts/test-kustomization.sh

# helper make target for generating the expected output
.PHONY: update-expected-kustomization
update-expected-kustomization:
	$(MAKE) build-manifests \
		STAGING_DIR=$(OUTPUT_DIR)/testing \
		REGISTRY=gcr.io/cs-test \
		IMAGE_TAG=placeholder \
		GIT_SYNC_VERSION=placeholder \
		OTELCONTRIBCOL_VERSION=placeholder
	UPDATE_EXPECTED_OUTPUT="true" ./scripts/test-kustomization.sh

# Runs unit tests and linter.
.PHONY: test
test: test-unit test-kustomization lint test-post-sync

# The presubmits have made side-effects in the past, which makes their
# validation suspect (as the repository they are validating is different
# than what is checked in).  Run `test` but verify that repository is clean.
.PHONY: __test-presubmit
__test-presubmit: all-local
	@./scripts/fail-if-dirty-repo.sh

# This is the entrypoint used by the ProwJob - runs using docker-in-docker.
.PHONY: test-presubmit
test-presubmit: pull-buildenv
	@docker run $(DOCKER_RUN_ARGS) make __test-presubmit

# Runs all tests.
# This only runs on local dev environment not CI environment.
.PHONY: test-all-local
test-all-local: test test-e2e

# Runs gofmt and goimports.
# Even though goimports runs gofmt, it runs it without the -s (simplify) flag
# and offers no option to turn it on. So we run them in sequence.
.PHONY: fmt-go
fmt-go: pull-buildenv buildenv-dirs
	@docker run $(DOCKER_RUN_ARGS) gofmt -s -w $(NOMOS_CODE_DIRS)
	@docker run $(DOCKER_RUN_ARGS) goimports -w $(NOMOS_CODE_DIRS)

# Runs shfmt.
.PHONY: fmt-sh
fmt-sh:
	@./scripts/fmt-bash.sh

.PHONY: tidy
tidy:
	go mod tidy

.PHONY: vendor
vendor:
	go mod vendor

.PHONY: deps
deps: tidy vendor

.PHONY: lint
lint: lint-go lint-bash lint-yaml lint-license lint-license-headers

.PHONY: lint-go
lint-go: "$(GOLANGCI_LINT)" lint-post-sync
	./scripts/lint-go.sh $(NOMOS_GO_PKG)

.PHONY: lint-bash
lint-bash:
	@./scripts/lint-bash.sh

# List of currently permitted licenses to be included for go modules.
# This may need to be updated as new dependencies are added.
# See https://github.com/google/licenseclassifier/blob/e6a9bb99b5a6f71d5a34336b8245e305f5430f99/license_type.go
ALLOWED_LICENSES := "MIT,ISC,Apache-2.0,BSD-2-Clause,BSD-3-Clause"

.PHONY: lint-license
# Lints licenses for all packages, even ones just for testing.
# Ignore the vendored kpt, because it's a copy from ./internal/third_party,
# which causes go-licenses to error.
# https://github.com/google/go-licenses/issues/310
lint-license: "$(GO_LICENSES)"
	@echo "\"$(GO_LICENSES)\" check --allowed_licenses=$(ALLOWED_LICENSES) \$$(go list all) ./vendor/... --ignore github.com/GoogleContainerTools/kpt"
	@"$(GO_LICENSES)" check --allowed_licenses=$(ALLOWED_LICENSES) $(shell go list all) ./vendor/... --ignore github.com/GoogleContainerTools/kpt

"$(GO_LICENSES)": buildenv-dirs
	GOPATH="$(GO_DIR)" go install github.com/google/go-licenses/v2

.PHONY: install-go-licenses
# install go-licenses (user-friendly target alias)
install-go-licenses: "$(GO_LICENSES)"

.PHONY: clean-go-licenses
clean-go-licenses:
	@rm -rf $(GO_LICENSES)

"$(ADDLICENSE)": buildenv-dirs
	GOPATH="$(GO_DIR)" go install github.com/google/addlicense

.PHONY: install-addlicense
# install addlicense (user-friendly target alias)
install-addlicense: "$(ADDLICENSE)"

.PHONY: clean-addlicense
clean-addlicense:
	@rm -rf $(ADDLICENSE)

"$(GOLANGCI_LINT)": buildenv-dirs
	GOPATH="$(GO_DIR)" go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)

.PHONY: install-golangci-lint
# install golangci-lint (user-friendly target alias)
install-golangci-lint: "$(GOLANGCI_LINT)"

.PHONY: clean-golangci-lint
clean-golangci-lint:
	@rm -rf $(GOLANGCI_LINT)

"$(KUSTOMIZE)": buildenv-dirs
	@KUSTOMIZE_VERSION="$(KUSTOMIZE_VERSION)" \
		INSTALL_DIR="$(BIN_DIR)" \
		TMPDIR="/tmp" \
		OUTPUT_DIR="$(OUTPUT_DIR)" \
		STAGING_DIR="$(KUSTOMIZE_STAGING_DIR)" \
		./scripts/install-kustomize.sh

.PHONY: clean-cosign
clean-cosign:
	@rm -rf $(COSIGN)

.PHONY: install-cosign
install-cosign: "$(COSIGN)"

"$(COSIGN)": buildenv-dirs
	GOPATH="$(GO_DIR)" CGO_ENABLED=0 go install github.com/sigstore/cosign/v2/cmd/cosign@$(COSIGN_VERSION)

.PHONY: install-kustomize
# install kustomize (user-friendly target alias)
install-kustomize: "$(KUSTOMIZE)"

.PHONY: clean-kustomize
clean-kustomize:
	@rm -rf $(KUSTOMIZE_STAGING_DIR)
	@rm -rf $(KUSTOMIZE)

"$(HELM)": buildenv-dirs
	@HELM_VERSION="$(HELM_VERSION)" \
		INSTALL_DIR="$(BIN_DIR)" \
		TMPDIR="/tmp" \
		OUTPUT_DIR="$(OUTPUT_DIR)" \
		STAGING_DIR="$(HELM_STAGING_DIR)" \
		./scripts/install-helm.sh

.PHONY: install-helm
# install helm (user-friendly target alias)
install-helm: "$(HELM)"

.PHONY: clean-helm
clean-helm:
	@rm -rf $(HELM_STAGING_DIR)
	@rm -rf $(HELM)

"$(GOBIN)/kind":
	# Build kind with CGO disabled so it can be used in containers without C installed.
	CGO_ENABLED=0 go install sigs.k8s.io/kind

"$(KIND)": "$(GOBIN)/kind" buildenv-dirs
	cp $(GOBIN)/kind $(KIND)

.PHONY: install-kind
# install kind (user-friendly target alias)
install-kind: "$(KIND)"

.PHONY: clean-go-junit-report
clean-go-junit-report:
	@rm -rf $(GO_JUNIT_REPORT)

.PHONY: install-go-junit-report
# install go-junit-report (user-friendly target alias)
install-go-junit-report: "$(GO_JUNIT_REPORT)"

"$(GOBIN)/go-junit-report":
	CGO_ENABLED=0 go install github.com/jstemmer/go-junit-report/v2

"$(GO_JUNIT_REPORT)": "$(GOBIN)/go-junit-report" buildenv-dirs
	cp $(GOBIN)/go-junit-report $(GO_JUNIT_REPORT)

# Set CGO_ENABLED=0 for compatibility with containers missing glibc
"$(GOBIN)/crane":
	CGO_ENABLED=0 go install github.com/google/go-containerregistry/cmd/crane

"$(CRANE)": "$(GOBIN)/crane" buildenv-dirs
	cp $(GOBIN)/crane $(CRANE)

.PHONY: install-crane
# install crane (user-friendly target alias)
install-crane: "$(CRANE)"

.PHONY: clean-crane
clean-crane:
	@rm -rf $(CRANE)

.PHONY: license-headers
license-headers: "$(ADDLICENSE)"
	./scripts/license-headers.sh add

.PHONY: lint-license-headers
lint-license-headers: "$(ADDLICENSE)"
	./scripts/license-headers.sh lint

.PHONY: lint-yaml
lint-yaml:
	@./scripts/lint-yaml.sh

.PHONY: test-loggers
test-loggers:
	./scripts/generate-test-loggers.sh

# Print the value of a variable
print-%:
	@echo $($*)

####################################################################################################
# MANUAL TESTING COMMANDS

# Reapply the resources, including a new image.  Use this to update with your code changes.
.PHONY: manual-test-refresh
manual-test-refresh: config-sync-manifest
	kubectl apply -f ${NOMOS_MANIFEST_STAGING_DIR}/config-sync-manifest.yaml

####################################################################################################

.PHONY: test-post-sync
test-post-sync:
	@echo "+++ Running post-sync tests"
	@cd examples/post-sync && go test -v ./... && cd $(CURDIR)

.PHONY: lint-post-sync
lint-post-sync: "$(GOLANGCI_LINT)"
	@echo "+++ Running golangci-lint on post-sync example"
	@cd examples/post-sync && GOCACHE="$(OUTPUT_DIR)/.cache/go" XDG_CACHE_HOME="$(OUTPUT_DIR)/.cache" $(GOLANGCI_LINT) run --config .golangci.yaml && cd $(CURDIR)
