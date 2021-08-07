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

# Static, not sure if needed??
PYTHON=python3
PIP=pip3

FILES =	*.py

# Add add files installed by requirements.txt to this next line
DEPENDENCIES=antiope

package: test clean deps zipfile

#
# Lambda function management
#

clean:
	rm -rf __pycache__ *.zip *.dist-info *.egg-info $(DEPENDENCIES)

# Create the package Zip. Assumes all tests were done, only for testing/dev
zipfile:  $(FILES) templates
ifndef LAMBDA_PACKAGE
	$(error LAMBDA_PACKAGE is not set)
endif
	cp -a ../../antiope-aws-module/antiope .
	zip -r ../$(LAMBDA_PACKAGE) $^ $(DEPENDENCIES) -x *.zip

test: $(FILES)
	for f in *.py ; do python3 -m py_compile $$f; if [ $$? -ne 0 ] ; then echo "$$f FAILS" ; exit 1; fi done

deps:
	$(PIP) install -r requirements.txt -t . --upgrade
	$(PIP) install ../../antiope-aws-module -t . --upgrade --no-deps

pep8: $(FILES)
	pycodestyle $^
