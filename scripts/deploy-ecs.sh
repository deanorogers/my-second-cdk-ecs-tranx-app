#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/deploy-ecs.sh [--env-file <path>] [--help]

Options:
  --env-file <path>  Load environment variables from a file before deployment.
  --help             Show this help message and exit.

The environment file should contain KEY=VALUE lines.
Optional build variable: DOCKER_PLATFORM (default: linux/amd64).
Optional: SSM_LAST_IMAGE_PARAM (default: /my-second-cdk-ecs-tranx-service/image-tag), an SSM parameter updated with the image tag only
after the ECS deployment completes (including bake time).
Optional: DEPLOY_TIMEOUT_SECONDS (default: 1800) to wait for the deployment.

If --env-file is not provided, the script will auto-load the first file found:
  1. .env.deploy.local
  2. .env.deploy
EOF
}

parse_args() {
  DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-file)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for --env-file" >&2
          usage
          exit 1
        fi
        DEPLOY_ENV_FILE="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

discover_default_env_file() {
  local script_dir project_root candidate
  script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  project_root="$(cd -- "$script_dir/.." && pwd)"

  for candidate in "$project_root/.env.deploy.local" "$project_root/.env.deploy"; do
    if [[ -f "$candidate" ]]; then
      DEPLOY_ENV_FILE="$candidate"
      return
    fi
  done
}

load_env_file() {
  local env_file="$1"

  if [[ -z "$env_file" ]]; then
    return
  fi

  if [[ ! -f "$env_file" ]]; then
    echo "Environment file not found: $env_file" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

next_tag() {
  local repo="$1"
  local hash="$2"
  local tags max next

  tags="$(aws ecr describe-images \
    --region "$AWS_REGION" \
    --repository-name "$repo" \
    --query 'imageDetails[].imageTags[]' \
    --output text 2>/dev/null || true)"

  max="$(printf '%s\n' "$tags" \
    | tr '\t' '\n' \
    | grep -E '^[0-9]{6}-[a-f0-9]{12}$' \
    | cut -d- -f1 \
    | sed 's/^0*//' \
    | awk 'BEGIN{m=0} {if ($1>m) m=$1} END{print m}')"

  if [[ -z "$max" ]]; then
    max=0
  fi

  next=$((max + 1))
  printf '%06d-%s\n' "$next" "$hash"
}

main() {
  parse_args "$@"
  if [[ -z "$DEPLOY_ENV_FILE" ]]; then
    discover_default_env_file
  fi
  load_env_file "$DEPLOY_ENV_FILE"
  SSM_LAST_IMAGE_PARAM="${SSM_LAST_IMAGE_PARAM:-/my-second-cdk-ecs-service/transactions/image-tag}"

  require_cmd aws
  require_cmd docker
  require_cmd jq
  if ! docker buildx version >/dev/null 2>&1; then
    echo "Missing required docker subcommand: buildx" >&2
    exit 1
  fi

  require_env AWS_REGION
  require_env AWS_ACCOUNT_ID
  require_env ECR_REPOSITORY
  require_env ECS_CLUSTER
  require_env ECS_SERVICE
  require_env TASK_DEFINITION_FAMILY

  local dockerfile context_dir container_name docker_platform
  dockerfile="${DOCKERFILE_PATH:-Dockerfile}"
  context_dir="${CONTEXT_DIR:-.}"
  container_name="${CONTAINER_NAME:-}"
  docker_platform="${DOCKER_PLATFORM:-linux/amd64}"

  local ecr_registry image_repo_uri local_image image_id image_hash image_tag remote_image
  ecr_registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  image_repo_uri="${ecr_registry}/${ECR_REPOSITORY}"
  local_image="${ECR_REPOSITORY}:build"

  echo "Validating AWS identity...$AWS_REGION"
  aws configure set output json --profile default
  aws sts get-caller-identity --region "$AWS_REGION" >/dev/null

  echo "Logging into ECR ${ecr_registry}..."
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ecr_registry" >/dev/null

  echo "Building image from ${dockerfile} (context: ${context_dir}, platform: ${docker_platform})..."
  docker buildx build \
    --platform "$docker_platform" \
    --load \
    -f "$dockerfile" \
    -t "$local_image" \
    "$context_dir" >/dev/null

  image_id="$(docker image inspect "$local_image" --format '{{.Id}}')"
  image_hash="$(printf '%s' "$image_id" | sed 's/^sha256://' | cut -c1-12)"

  image_tag="$(next_tag "$ECR_REPOSITORY" "$image_hash")"
  remote_image="${image_repo_uri}:${image_tag}"
#   remote_image="${image_repo_uri}:bootstrap"

  echo "Tagging and pushing ${remote_image}..."
  docker tag "$local_image" "$remote_image"
  docker push "$remote_image" >/dev/null
  # exit the function here with success
#  echo "All Done!"
#  exit 0

  local current_td_arn td_json updated_td_json register_out new_td_arn
  # Passing only the family resolves to the latest ACTIVE revision.
  current_td_arn="$(aws ecs describe-task-definition \
    --region "$AWS_REGION" \
    --task-definition "$TASK_DEFINITION_FAMILY" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)"

  if [[ "$current_td_arn" == "None" || -z "$current_td_arn" ]]; then
    echo "Could not resolve latest task definition for family ${TASK_DEFINITION_FAMILY}" >&2
    exit 1
  fi

  echo "Preparing new task definition from ${current_td_arn}..."
  td_json="$(aws ecs describe-task-definition \
    --region "$AWS_REGION" \
    --task-definition "$current_td_arn" \
    --query 'taskDefinition' \
    --output json)"

  if [[ -z "$container_name" ]]; then
    container_name="$(printf '%s' "$td_json" | jq -r '.containerDefinitions[0].name')"
  fi

  if [[ "$(printf '%s' "$td_json" | jq -r '.family')" != "$TASK_DEFINITION_FAMILY" ]]; then
    echo "Resolved task definition family does not match TASK_DEFINITION_FAMILY=${TASK_DEFINITION_FAMILY}" >&2
    exit 1
  fi

  if [[ "$(printf '%s' "$td_json" | jq -r --arg cname "$container_name" '[.containerDefinitions[] | select(.name == $cname)] | length')" -eq 0 ]]; then
    echo "Container '${container_name}' was not found in task definition ${current_td_arn}" >&2
    exit 1
  fi

  updated_td_json="$(printf '%s' "$td_json" | jq \
    --arg image "$remote_image" \
    --arg cname "$container_name" '
      .containerDefinitions |= map(if .name == $cname then .image = $image else . end)
      | del(
          .taskDefinitionArn,
          .revision,
          .status,
          .requiresAttributes,
          .compatibilities,
          .registeredAt,
          .registeredBy,
          .deregisteredAt
        )
    ')"

  register_out="$(aws ecs register-task-definition \
    --region "$AWS_REGION" \
    --cli-input-json "$updated_td_json")"

  new_td_arn="$(printf '%s' "$register_out" | jq -r '.taskDefinition.taskDefinitionArn')"
  if [[ -z "$new_td_arn" || "$new_td_arn" == "null" ]]; then
    echo "Failed to register new task definition" >&2
    exit 1
  fi

  echo "Updating ECS service ${ECS_SERVICE} to ${new_td_arn}..."
  aws ecs update-service \
    --region "$AWS_REGION" \
    --cluster "$ECS_CLUSTER" \
    --service "$ECS_SERVICE" \
    --task-definition "$new_td_arn" \
    --force-new-deployment >/dev/null

  echo "Waiting for deployment of ${new_td_arn} to complete..."
  local deadline dep state
  deadline=$((SECONDS + ${DEPLOY_TIMEOUT_SECONDS:-1800}))
  while :; do
    dep="$(aws ecs describe-services \
      --region "$AWS_REGION" \
      --cluster "$ECS_CLUSTER" \
      --services "$ECS_SERVICE" \
      --query "services[0].deployments[?taskDefinition=='${new_td_arn}'] | [0]" \
      --output json)"
    state="$(printf '%s' "$dep" | jq -r '.rolloutState // "MISSING"')"
    case "$state" in
      COMPLETED) break ;;
      FAILED|MISSING)
        echo "Deployment failed (${state}); not updating SSM." >&2
        exit 1
        ;;
    esac
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for deployment to complete; not updating SSM." >&2
      exit 1
    fi
    sleep 15
  done

  if [[ -n "${SSM_LAST_IMAGE_PARAM:-}" ]]; then
    echo "Updating SSM parameter ${SSM_LAST_IMAGE_PARAM}..."
    aws ssm put-parameter \
      --region "$AWS_REGION" \
      --name "$SSM_LAST_IMAGE_PARAM" \
      --type String \
      --overwrite \
      --value "$image_tag" >/dev/null
  fi

  echo "Deployment completed successfully."
  echo "Image: ${remote_image}"
  echo "Task definition: ${new_td_arn}"
}

main "$@"


