# Copyright 2021 Chris Farris <chrisf@primeharbor.com>
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

ifndef BUCKET
$(error BUCKET is not set)
endif

ifndef DEPLOY_PREFIX
	DEPLOY_PREFIX=deploy-packages
endif

ifndef version
	export version := $(shell date +%Y%b%d-%H%M)
endif

ifndef CONTAINER_TAG
	export CONTAINER_TAG=$(version)
endif

# We may need this in future places
# See https://stackoverflow.com/questions/2019989/how-to-assign-the-output-of-a-command-to-a-makefile-variable#answer-54776239
GET_ACCOUNT_ID = $(shell aws sts get-caller-identity --query 'Account' --output text)
CALL_GET_ACCOUNT_ID = $(eval ACCOUNT_ID=$(GET_ACCOUNT_ID))

#
# CloudSploit Settings
#
CLOUDSPLOIT_PREFIX=antiope-cloudsploit
CLOUDSPLOIT_TEMPLATE=cloudformation/$(CLOUDSPLOIT_PREFIX)-Template.yaml
CLOUDSPLOIT_OUTPUT_TEMPLATE=$(CLOUDSPLOIT_PREFIX)-Template-Transformed-$(version).yaml
CLOUDSPLOIT_TEMPLATE_URL ?= https://s3.amazonaws.com/$(BUCKET)/$(DEPLOY_PREFIX)/$(CLOUDSPLOIT_OUTPUT_TEMPLATE)

deps:
	cd lambda && $(MAKE) deps

test:
	cd lambda && $(MAKE) test

clean:
	cd lambda && $(MAKE) clean
	rm cloudformation/$(CLOUDSPLOIT_PREFIX)-Template-Transformed-*.yaml

package: test deps
	@aws cloudformation package --template-file $(CLOUDSPLOIT_TEMPLATE) --s3-bucket $(BUCKET) --s3-prefix $(DEPLOY_PREFIX)/transform --output-template-file cloudformation/$(CLOUDSPLOIT_OUTPUT_TEMPLATE)  --metadata build_ver=$(version)
	@aws s3 cp cloudformation/$(CLOUDSPLOIT_OUTPUT_TEMPLATE) s3://$(BUCKET)/$(DEPLOY_PREFIX)/

deploy: package container-build container-push cft-deploy

serverless-deploy: package cft-deploy

cft-deploy:
ifndef CLOUDSPLOIT_MANIFEST
	$(error CLOUDSPLOIT_MANIFEST is not set)
endif
	cft-deploy -m ../Manifests/$(CLOUDSPLOIT_MANIFEST) --template-url $(CLOUDSPLOIT_TEMPLATE_URL) pTemplateURL=$(CLOUDSPLOIT_TEMPLATE_URL) pBucketName=$(BUCKET) pContainerTag=$(CONTAINER_TAG) --force

promote:
ifndef template
	$(error template is not set)
endif
ifndef CLOUDSPLOIT_MANIFEST
	$(error CLOUDSPLOIT_MANIFEST is not set)
endif
	cft-deploy -m ../Manifests/$(CLOUDSPLOIT_MANIFEST) --template-url $(template) pTemplateURL=$(template) pBucketName=$(BUCKET) --force


#
# Container Targets
#
container-build: deps
	docker build -t antiope-cloudsploit:$(version)  .

# Note - to use this target the Env vars ACCOUNT_TABLE, VPC_TABLE, ROLE_NAME and ROLE_NAME must be set in your config.ENV
# Additionally AWS_DEFAULT_REGION, AWS_SECRET_ACCESS_KEY and  AWS_ACCESS_KEY_ID must be in the environment rather than in the credentials file
container-test:
	docker run -p 9000:8080  -e ROLE_SESSION_NAME=Cloudsploit \
		-e INVENTORY_BUCKET=$(BUCKET) -e LOG_LEVEL=DEBUG \
		-e ACCOUNT_TABLE -e VPC_TABLE -e ROLE_NAME -e ERROR_QUEUE \
		-e AWS_DEFAULT_REGION -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID \
		antiope-cloudsploit:$(version)

# To trigger the test container:
# curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d @SAMPLEEVENT.json

container-push:
	$(CALL_GET_ACCOUNT_ID)
	docker tag antiope-cloudsploit:$(version) $(ACCOUNT_ID).dkr.ecr.$(AWS_DEFAULT_REGION).amazonaws.com/antiope-cloudsploit:$(version)
	aws ecr get-login-password | docker login --username AWS --password-stdin $(ACCOUNT_ID).dkr.ecr.$(AWS_DEFAULT_REGION).amazonaws.com
	docker push $(ACCOUNT_ID).dkr.ecr.$(AWS_DEFAULT_REGION).amazonaws.com/antiope-cloudsploit:$(version)