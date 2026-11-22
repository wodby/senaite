# Base image inputs shared by local builds and CI.
# The digest identifies the complete multi-platform image index.
BASE_IMAGE_REPOSITORY := ubuntu
BASE_IMAGE_TAG := 22.04
BASE_IMAGE_DIGEST := sha256:f64b2ffc2f10ab8f8505aa56b2664bd846cbb9df87c7e2532e30f7667021c0e6

BASE_IMAGE = $(BASE_IMAGE_REPOSITORY):$(BASE_IMAGE_TAG)@$(BASE_IMAGE_DIGEST)
