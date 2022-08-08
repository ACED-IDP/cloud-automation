#
# Helper script for 'gen3 workon' - see ../README.md and ../gen3setup.sh
#

source "$GEN3_HOME/gen3/lib/utils.sh"
gen3_load "gen3/lib/aws"
gen3_load "gen3/lib/gcp"
gen3_load "gen3/lib/onprem"
gen3_load "gen3/lib/terraform"

# lib -------------------

#
# Sync the given file with S3.
# Note that 'workon' only every copies from S3 to local,
# and only if a local copy does not already exist.
# See 'gen3 refresh' to pull down latest files from s3.
# We copy the local up to S3 at 'apply' time.
#
refreshFromBackend() {
  local fileName
  local filePath
  fileName=$1
  if [[ -z $fileName ]]; then
    return 1
  fi
  filePath="${GEN3_WORKDIR}/$fileName"
  if [[ -f $filePath ]]; then
    gen3_log_info "Ignoring S3 refresh for file that already exists: $fileName"
    return 1
  fi
  if [[ "$GEN3_FLAVOR" != "AWS" ]]; then
    #echo -e "$(red_color "refreshFromBackend not yet supported for $GEN3_FLAVOR")"
    return 1
  fi
  s3Path="s3://${GEN3_S3_BUCKET}/${GEN3_WORKSPACE}/${fileName}"
  gen3_aws_run aws s3 cp "$s3Path" "$filePath" > /dev/null 2>&1
  if [[ ! -f "$filePath" ]]; then
    gen3_log_info "No data at $s3Path"
    return 1
  fi
  return 0
}

# main -----------------------

#
# Create any missing files
#
mkdir -p -m 0700 "$GEN3_WORKDIR/backups"
chmod 0700 "$GEN3_WORKDIR"

if [[ ! -f "$GEN3_WORKDIR/root.tf" ]]; then
  # Note: do not use `` in heredoc!
  gen3_log_info "Creating $GEN3_WORKDIR/root.tf"
  if [[ "$GEN3_FLAVOR" == "AWS" ]]; then
    cat - > "$GEN3_WORKDIR/root.tf" <<EOM
#
# THIS IS AN AUTOGENERATED FILE (by gen3)
# root.tf is required for *terraform output*, *terraform taint*, etc
# @see https://github.com/hashicorp/terraform/issues/15761
#
terraform {
    backend "s3" {
        encrypt = "true"
    }
}
EOM
  else
    cat - > "$GEN3_WORKDIR/root.tf" <<EOM
#
# THIS IS AN AUTOGENERATED FILE (by gen3)
# root.tf is required for *terraform output*, *terraform taint*, etc
# @see https://github.com/hashicorp/terraform/issues/15761
#
EOM
  fi
fi

for fileName in config.tfvars backend.tfvars README.md; do
  filePath="${GEN3_WORKDIR}/$fileName"
  if [[ ! -f "$filePath" ]]; then
    refreshFromBackend "$fileName"
    if [[ ! -f "$filePath" ]]; then
      gen3_log_info "Variables not configured at $filePath"
      gen3_log_info "Setting up initial contents - customize before running terraform"
      # Run the function that corresponds to the profile flavor (AWS, GCP, ...) and $fileName
      "gen3_${GEN3_FLAVOR}.$fileName" > "$filePath"
    fi
  fi
done

cd "$GEN3_WORKDIR"
bucketCheckFlag=".tmp_bucketcheckflag2"
if [[ ! -f "$bucketCheckFlag" && "$GEN3_FLAVOR" == "AWS" ]]; then
  gen3_log_info "initializing terraform"
  gen3_log_info "checking if $GEN3_S3_BUCKET bucket exists"
  if ! gen3_aws_run aws s3 ls "s3://$GEN3_S3_BUCKET" > /dev/null 2>&1; then
    gen3_log_info "Creating $GEN3_S3_BUCKET bucket"
    gen3_log_info "NOTE: please verify that aws profile region matches backend.tfvars region:"
    gen3_log_info "  aws profile region: $(aws configure get $GEN3_PROFILE.region)"
    gen3_log_info "  terraform backend region: $(cat *backend.tfvars | grep region)"

    S3_POLICY=$(cat - <<EOM
  {
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }
EOM
)
    gen3_aws_run aws s3api create-bucket --acl private --bucket "$GEN3_S3_BUCKET"
    sleep 5 # Avoid race conditions
    if gen3_aws_run aws s3api put-bucket-encryption --bucket "$GEN3_S3_BUCKET" --server-side-encryption-configuration "$S3_POLICY"; then
      touch "$bucketCheckFlag"
    fi
  else
    touch "$bucketCheckFlag"
  fi
fi

# setup git
(
    cd "${GEN3_WORKDIR}/"
    if [[ ! -d ".git" ]]; then
      git init .
      cat > .gitignore <<EOM
.*
*.log
*.bak
*~

!.gitignore
EOM
      git add .
      git commit -n -m 'initial'
    fi
)

if [[ "$GEN3_WORKSPACE" =~ __custom$ ]]; then
  ( # pin terraform version
    cd "${GEN3_WORKDIR}/"
    if [[ ! -f "manifest.json" ]]; then
      cat - > manifest.json <<EOM
{
  "terraform": {
    "module_version" : "0.12"
  }
}
EOM
    fi
  )
fi

cd "${GEN3_WORKDIR}/"
if [[ ! -z $USE_TF_1 ]]; then
  gen3_log_info "Running: terraform -chdir="$GEN3_TFSCRIPT_FOLDER/" init --backend-config ./backend.tfvars in $(pwd)"
  gen3_terraform -chdir="$GEN3_TFSCRIPT_FOLDER/" init --backend-config="${GEN3_WORKDIR}/backend.tfvars"
else
  gen3_log_info "Running: terraform init --backend-config ./backend.tfvars $GEN3_TFSCRIPT_FOLDER/ in $(pwd)"
  gen3_terraform init --backend-config="${GEN3_WORKDIR}/backend.tfvars" "$GEN3_TFSCRIPT_FOLDER"
fi