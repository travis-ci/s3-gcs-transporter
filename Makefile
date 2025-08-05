.PHONY: all

COMMAND        = bundle exec ./s3_to_gcs.rb
S3_REGION      = us-east-1
GCS_REGION     = us
GCS_JSON       = creds.json
GCS_BUCKET     = travis-ci-language-archives
ARGS           = --s3-region=$(S3_REGION) \
  --s3-prefix=binaries/ \
  --gcs-region=$(GCS_REGION) \
  --gcs-creds-json=$(GCS_JSON) \
  --gcs-project-id=$(GCS_PROJECT_ID) \
  --gcs-bucket=$(GCS_BUCKET) \
  --log-level=info

ruby:
	@$(COMMAND) $(ARGS) --s3-bucket=travis-rubies --gcs-prefix=ruby/binaries/

python:
	@$(COMMAND) $(ARGS) --s3-bucket=travis-python-archives --gcs-prefix=python/binaries/

erlang:
	@$(COMMAND) $(ARGS) --s3-bucket=travis-otp-releases --gcs-prefix=erlang/binaries/

php:
	@$(COMMAND) $(ARGS) --s3-bucket=travis-php-archives --gcs-prefix=php/binaries/

perl:
	@$(COMMAND) $(ARGS) --s3-bucket=travis-perl-archives --gcs-prefix=perl/binaries/

all: ruby python erlang php perl
