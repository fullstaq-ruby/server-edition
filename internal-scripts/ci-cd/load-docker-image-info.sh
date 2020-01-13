#!/bin/bash
set -e
echo "::set-output name=image-name::$(cat image_name.txt)"
echo "::set-output name=image-tag::$(cat image_tag.txt)"
