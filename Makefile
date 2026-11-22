-include env_make

# A SENAITE release, such as 2.6.0. Its first two parts name the release line
# the image is published for (2.6). versions.cfg pins the release's packages.
SENAITE_VER ?= 2.6.0
SENAITE_VER_MINOR := $(basename $(SENAITE_VER))

TAG ?= $(SENAITE_VER_MINOR)

REPO = wodby/senaite
NAME = senaite-$(SENAITE_VER_MINOR)

IMAGETOOLS_TAG ?= $(TAG)

ifneq ($(ARCH),)
	override TAG := $(TAG)-$(ARCH)
endif

.PHONY: build test push shell run clean buildx-imagetools-create

# Resolve the same pinned base image for every local and CI build target.
include base-images.mk

default: build

build:
	docker build --build-arg BASE_IMAGE="$(BASE_IMAGE)" --build-arg SENAITE_VER="$(SENAITE_VER)" -t $(REPO):$(TAG) ./

test:
	cd ./tests && IMAGE=$(REPO):$(TAG) NAME=$(NAME) SENAITE_VER=$(SENAITE_VER) ./run.sh

push:
	docker push $(REPO):$(TAG)

# CI combines the exact architecture images this workflow run pushed; see
# wodby/images arch-image-pins. Per-architecture tags are shared by every run,
# so an overlapping run may already have replaced one of them.
arch-image = $(if $(ARCH_IMAGE_PINS),$(or $(shell cat '$(ARCH_IMAGE_PINS)/$(subst :,_,$(subst /,_,$(1)))' 2>/dev/null),$(error No digest of $(1) was pushed by this workflow run)),$(1))

buildx-imagetools-create:
	docker buildx imagetools create -t $(REPO):$(IMAGETOOLS_TAG) \
				$(call arch-image,$(REPO):$(TAG)-amd64) \
				$(call arch-image,$(REPO):$(TAG)-arm64)

shell:
	docker run --rm --name $(NAME) -i -t $(PORTS) $(VOLUMES) $(ENV) $(REPO):$(TAG) /bin/bash

run:
	docker run --rm --name $(NAME) $(PORTS) $(VOLUMES) $(ENV) $(REPO):$(TAG) $(CMD)

clean:
	-docker rm -f $(NAME)

# Print the image make builds and pushes; CI pushes exactly this reference.
.PHONY: image-ref
image-ref:
	@printf '%s\n' '$(REPO):$(TAG)'
