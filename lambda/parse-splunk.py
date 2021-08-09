# Copyright 2020-2021 Chris Farris <chrisf@primeharbor.com>
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

import json
import os
import boto3
from botocore.exceptions import ClientError
import urllib3
from urllib.parse import unquote

import logging
logger = logging.getLogger()
logger.setLevel(getattr(logging, os.getenv('LOG_LEVEL', default='INFO')))
logging.getLogger('botocore').setLevel(logging.WARNING)
logging.getLogger('boto3').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)

def handler(event, _context):
    logger.debug("Received event: " + json.dumps(event, sort_keys=True))

    if hec_data is None:
        logger.critical(f"Unable to fetch secret {os.environ['HEC_DATA']}")
        raise Exception
    logger.debug(f"HEC Endpoint: {hec_data['HECEndpoint']}")
    file_count = 0
    finding_count = 0
    s3 = boto3.client('s3')

    # Multiple layers of nesting to unpack with S3 Events, to SNS to SQS
    for sns_record in event['Records']:
        sns_message = json.loads(sns_record['body'])
        sns_message2 = json.loads(sns_message['Message'])
        logger.debug(f"sns_message2: {sns_message2}")

        for s3_record in sns_message2['Records']:
            file_data_to_push = get_object(s3_record['s3']['bucket']['name'], s3_record['s3']['object']['key'], s3)
            if file_data_to_push is None:
                logger.warning(f"Got no data for s3://{s3_record['s3']['bucket']['name']}/{s3_record['s3']['object']['key']}")
                continue

            for finding in file_data_to_push:
                if finding['status'] == "OK":
                    continue  # Only send issues to splunk

                # logger.debug(json.dumps(finding, indent=2, default=str))
                push_event(finding)
                finding_count += 1

            file_count += 1

    logger.info(f"Wrote {finding_count} findings in {file_count} files to Splunk")
    return()


def push_event(message):

    headers = {'Authorization': 'Splunk '+ hec_data['HECToken']}
    payload = { "host": hec_data['HECEndpoint'], "event": message }
    data=json.dumps(payload, default=str)

    try:
        logger.debug(f"Sending data {data} to {hec_data['HECEndpoint']}")
        r = http.request('POST', hec_data['HECEndpoint'], headers=headers, body=data)
        if r.status != 200:
            logger.critical(f"Error: {r.data}")
            raise(Exception(f"HEC Error: {r.data}"))
        else:
            logger.debug(f"Success: {r.data}")
    except Exception as e:
        logger.critical(f"Error: {e}")
        raise

def get_secret(secret_name):
    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager')

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except ClientError as e:
        logger.critical(f"Client error {e} getting secret")
        raise e

    else:
        # Decrypts secret using the associated KMS CMK.
        # Depending on whether the secret is a string or binary, one of these
        # fields will be populated.
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            return json.loads(secret)
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            return(decoded_binary_secret)
    return None

# Get the secret once per lambda container rather than on each invocation.
hec_data = get_secret(os.environ['HEC_DATA'])
if hec_data is None:
    logger.critical(f"Unable to fetch secret {os.environ['HEC_DATA']}")
    raise Exception
# Reuse the PoolManager across invocations
http = urllib3.PoolManager()

def get_object(bucket, obj_key, s3):
    '''get the object to index from S3 and return the parsed json'''
    try:
        response = s3.get_object(
            Bucket=bucket,
            Key=unquote(obj_key)
        )
        return(json.loads(response['Body'].read()))
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchKey':
            logger.error("Unable to find resource s3://{}/{}".format(bucket, obj_key))
        else:
            logger.error("Error getting resource s3://{}/{}: {}".format(bucket, obj_key, e))
        return(None)

### EOF ###