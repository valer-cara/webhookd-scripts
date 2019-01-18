#!/bin/bash

# Form Param: $namespace - the namespace of the deploy we're targeting
# Form Param: $name - the name of the deploy we're targeting
# Form Param: $only - prefix to match tag name against. eg: `beta` `v`

# Post Param: $1 - Docherhub webhook payload: https://docs.docker.com/docker-hub/webhooks/#example-webhook-payload

set -e
set -o pipefail

function k {
  kubectl --namespace "$namespace" $@
}

function die {
  echo $@
  exit 1
}

if [ -z "$name" ] || [ -z "$namespace" ]; then
  die "Must provide 'name' and 'namespace' params"
fi

if [ -z "$1" ] || ! ( echo $1 | jq -r . > /dev/null ); then
  die "Must provide a valid JSON dockerhub webhook payload."
fi

DOCKERHUB_PAYLOAD=$1
REPO=$(echo $DOCKERHUB_PAYLOAD | jq -r .repository.repo_name)
TAG=$(echo $DOCKERHUB_PAYLOAD | jq -r .push_data.tag)
PUSHED_AT=$(echo $DOCKERHUB_PAYLOAD | jq -r .push_data.pushed_at)

if [[ -n "$only" ]]; then
  if ! [[ "$TAG" == "$only"* ]]; then
    echo "Skipping update for tag '$TAG' since it doesn't match given filter 'only=$only*'"
    exit 0
  fi
fi

CONTAINER_NAME=$(k get deploy "$name" -o json | jq -r '.spec.template.spec.containers[] | select(.image | match("'"$REPO"'")) | .name')

PATCH_TEMPLATE=$(cat <<HERE | jq -rc .
  {
    "spec": {
      "template": { "metadata": {
          "annotations": {
            "dockerhub-hook-time":"$PUSHED_AT"
          }
        },
        "spec": {
          "containers": [
            {"name":"$CONTAINER_NAME","image":"$REPO:$TAG"}
          ]
        }
      }
    }
  }
HERE
)

if [ -z "$CONTAINER_NAME" ]; then
  die "Deployment '$namespace/$name' has no containers using image repo '$REPO'. Failed update..."
fi

echo "Updating deployment '$namespace/$name' (container '$CONTAINER_NAME')..."
k patch deployment/"$name" -p $PATCH_TEMPLATE


