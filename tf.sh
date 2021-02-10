#!/usr/env/bin bash

set -e


TF_PARALLELISM=${TF_PARALLELISM:-10}
TF_STATE_BUCKET=${TF_STATE_BUCKET:-}
TF_STATE_PATH=${TF_STATE_PATH:-}
TF_STATE_FILE_NAME=${TF_STATE_FILE_NAME:-main.tfstate}
TF_TERRAFORM_EXECUTABLE=${TF_TERRAFORM_EXECUTABLE:-terraform}
TF_ENVIRONMENT_ID=${TF_ENVIRONMENT_ID:-}

[ -e ./.terraform_executable ] && export TF_TERRAFORM_EXECUTABLE="$(cat .terraform_executable)"

if [ "$#" -eq 0 ] || [ "$*" == "-h" ] || [ "$*" == "-h" ]
then
  echo "This is a Terraform wrapper to dynamically pick different state files for different environment"
  echo "Wrapper will attempt to pick defaults and setup a correct bucket"
  echo "All script argumetns will be passed to Terraform"
  echo ""
  echo "Example:"
  echo "tf plan"
  echo "tf destroy"
  echo ""
  echo "tf will indentify your env based on current AWS account id and region"
  echo ""
  exit 0
fi

if [ -z "${AWS_DEFAULT_REGION}" ]
then
  echo "Define env variable AWS_DEFAULT_REGION (should be your region name, ex us-east-1) and try again"
  exit 1
fi

if [ -z "${TF_ENVIRONMENT_ID}" ]; then
    if [ -z $(which aws) ]; then
        echo "aws cli is required to identify environment id. https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "${AWS_ACCOUNT_ID}" ]; then
        echo "Can't determine aws account id by running 'aws sts get-caller-identity'. Please make sure that you have valid credentials and try again"
        echo "Or provide your own TF_ENVIRONMENT_ID"
        exit 1
    fi
    export TF_ENVIRONMENT_ID="${AWS_ACCOUNT_ID}-${AWS_DEFAULT_REGION}"
    echo "Based on aws config assuming TF_ENVIRONMENT_ID=${TF_ENVIRONMENT_ID}"
else
    echo "Using user provided TF_ENVIRONMENT_ID=${TF_ENVIRONMENT_ID}"
fi

if [ -z "${TF_STATE_BUCKET}" ]; then
    # Use hashed environment id to avoid account id/region disclosure via S3 DNS name
    # in this way it is hard to predict the bucket name and attacker won't be able to
    # setup buckets in advance to capture your state file
    HASHED_ENVIRONMENT_ID=$(echo -n ${TF_ENVIRONMENT_ID} | sha1sum | awk '{print $1}')
    export TF_STATE_BUCKET="terraform-state-${HASHED_ENVIRONMENT_ID}"
fi

if [ -z "${TF_STATE_PATH}" ]; then
    # Check if we are in git repo
    GIT_REPO_TEST=$(git rev-parse --git-dir 2> /dev/null || true)
    if [ -z "${GIT_REPO_TEST}" ]
    then
        echo "tf expects you to run inside git repo since it will be using git repo name as part of the state"
        exit 1
    fi

    # Try to get remote repo name
    # we can't use just local repo name because jenkins pipelines
    # clone repos to directories with abracadabra names which are not the same
    # as actual repo name
    if [ ! -z "$(git config --get remote.origin.url)" ]
    then
        REPO_NAME=$(basename -s .git $(git config --get remote.origin.url))
        echo "Using remote repo name \"${REPO_NAME}\" as a part of Terraform state path"
    else
        # If there are no remote repo then fall back to local repo directory name
        REPO_NAME=$(basename $(git rev-parse --show-toplevel))
        echo "Can not find remote repo name. Using local repo name \"${REPO_NAME}\" as a part of Terraform state path"
    fi
    export TF_STATE_PATH="terraform/${REPO_NAME}/${TF_STATE_FILE_NAME}"
fi

echo "Using remote state s3://${TF_STATE_BUCKET}/${TF_STATE_PATH}"

set -x

${TF_TERRAFORM_EXECUTABLE} init -backend-config "key=${TF_STATE_PATH}" -backend-config "bucket=${TF_STATE_BUCKET}" -backend-config "region=${AWS_DEFAULT_REGION}"

# If we are applying changes, do not ask for interactive approval
[ $1 == "apply" ] && export OPTIONS="-auto-approve"
# figure out which env file to use
[ -e ./${TF_ENVIRONMENT_ID}.tfvars ] && export VAR_FILE="-var-file=./${TF_ENVIRONMENT_ID}.tfvars"

${TF_TERRAFORM_EXECUTABLE} $* ${VAR_FILE} ${OPTIONS}