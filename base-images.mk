# Base image inputs shared by local builds and CI.
# The digest identifies the complete multi-platform image index.
BASE_IMAGE_REPOSITORY := ubuntu
BASE_IMAGE_TAG := 22.04
BASE_IMAGE_DIGEST := sha256:b000e69a50ff940390233025e7a337fb8469b509e2334fa4d018ac30f3e18cdb

BASE_IMAGE = $(BASE_IMAGE_REPOSITORY):$(BASE_IMAGE_TAG)@$(BASE_IMAGE_DIGEST)
