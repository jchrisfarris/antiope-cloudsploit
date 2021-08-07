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
$(error DEPLOY_PREFIX is not set)
endif

ifndef version
$(error version is not set)
endif

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

package: test deps
	@aws cloudformation package --template-file $(CLOUDSPLOIT_TEMPLATE) --s3-bucket $(BUCKET) --s3-prefix $(DEPLOY_PREFIX)/transform --output-template-file cloudformation/$(CLOUDSPLOIT_OUTPUT_TEMPLATE)  --metadata build_ver=$(version)
	@aws s3 cp cloudformation/$(CLOUDSPLOIT_OUTPUT_TEMPLATE) s3://$(BUCKET)/$(DEPLOY_PREFIX)/

deploy: package
ifndef CLOUDSPLOIT_MANIFEST
	$(error CLOUDSPLOIT_MANIFEST is not set)
endif
	cft-deploy -m ../Manifests/$(CLOUDSPLOIT_MANIFEST) --template-url $(CLOUDSPLOIT_TEMPLATE_URL) pTemplateURL=$(CLOUDSPLOIT_TEMPLATE_URL) pBucketName=$(BUCKET) --force

promote:
ifndef template
	$(error template is not set)
endif
ifndef CLOUDSPLOIT_MANIFEST
	$(error CLOUDSPLOIT_MANIFEST is not set)
endif
	cft-deploy -m ../Manifests/$(CLOUDSPLOIT_MANIFEST) --template-url $(template) pTemplateURL=$(template) pBucketName=$(BUCKET) --force