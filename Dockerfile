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

# As the lambda handler is python, we need to start with a python base image
FROM amazon/aws-lambda-python:3.8

# copy in the Lambda code and ensure requirements are installed
COPY lambda ${LAMBDA_TASK_ROOT}
RUN  pip3 install -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

#
# CloudSploit is a large Nodejs package, which is why we've moved to
# lambda containers
#
# Install the nodejs binary, then run npm install
# to install the CloudSploit packages
#

# There has got to be a better way than this. This is how Supplychain hacks occur
RUN curl -sL https://rpm.nodesource.com/setup_16.x | bash -
RUN yum install -y nodejs

# Install cloudsploit in a subdirectory
COPY cloudsploit ${LAMBDA_TASK_ROOT}/cloudsploit
RUN cd ${LAMBDA_TASK_ROOT}/cloudsploit ; npm install

# This is the Lambda Handler
CMD [ "invoke-cloudsploit.handler" ]