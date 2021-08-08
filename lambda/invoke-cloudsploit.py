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

import boto3
from botocore.exceptions import ClientError
import json
import os
import datetime as dt

from antiope.aws_account import *
from common import *

import logging
logger = logging.getLogger()
logger.setLevel(getattr(logging, os.getenv('LOG_LEVEL', default='INFO')))
logging.getLogger('botocore').setLevel(logging.WARNING)
logging.getLogger('boto3').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)


def handler(event, context):
    logger.debug("Received event: " + json.dumps(event, sort_keys=True))
    message = json.loads(event['Records'][0]['Sns']['Message'])
    logger.info("Received message: " + json.dumps(message, sort_keys=True))

    try:
        target_account = AWSAccount(message['account_id'])

        #
        # Get assume role credentials & write them to a file for CloudSploit
        # TODO - eventually we need to do configurable settings here too I think
        #
        creds = target_account.get_creds(session_name="CloudSploit")
        config_file = {
            "credentials": {
                "aws": {
                    "access_key": creds['AccessKeyId'],
                    "secret_access_key": creds['SecretAccessKey'],
                    "session_token": creds['SessionToken'],
                }
            }
        }
        with open(f"/tmp/{target_account.account_id}-config.json", 'w') as outfile:
            json.dump(config_file, outfile)

        command = f"node cloudsploit/index.js --json /tmp/{target_account.account_id}-results.json --collection /tmp/{target_account.account_id}-collection.json --console none --config /tmp/{target_account.account_id}-config.json"

        results = os.system(command)
        if results != 0:
            logger.warning(f"CloudSploit binary failed to execute with exit code 0")

        # Get today's date
        today = dt.date.today()

        # Save json to S3
        s3_client = boto3.client('s3')
        try:

            # Store the scan results back into the antiope bucket
            with open(f"/tmp/{target_account.account_id}-results.json", 'rb') as bucket_data:
                response = s3_client.put_object(
                    ACL='bucket-owner-full-control',
                    Body=bucket_data,
                    Bucket=os.environ['INVENTORY_BUCKET'],
                    ContentType='application/json',
                    Key=f"CloudSploit/latest-results/{target_account.account_id}.json",
                )

            #
            # Keep a daily historical record of the results and collections
            # Place that into the STANDARD_IA for cost savings
            #
            with open(f"/tmp/{target_account.account_id}-results.json", 'rb') as bucket_data:
                response = s3_client.put_object(
                    ACL='bucket-owner-full-control',
                    Body=bucket_data,
                    Bucket=os.environ['INVENTORY_BUCKET'],
                    ContentType='application/json',
                    Key=f"CloudSploit/results/{target_account.account_id}/{today}-results.json",
                    StorageClass='STANDARD_IA'
                )

            with open(f"/tmp/{target_account.account_id}-collection.json", 'rb') as bucket_data:
                response = s3_client.put_object(
                    ACL='bucket-owner-full-control',
                    Body=bucket_data,
                    Bucket=os.environ['INVENTORY_BUCKET'],
                    ContentType='application/json',
                    Key=f"CloudSploit/collection/{target_account.account_id}/{today}-collection.json",
                    StorageClass='STANDARD_IA'
                )

        except ClientError as e:
            logger.error("ClientError saving report: {}".format(e))
            raise

    except AntiopeAssumeRoleError as e:
        logger.error("Unable to assume role into account {}({})".format(target_account.account_name, target_account.account_id))
        return()
    except ClientError as e:
        if e.response['Error']['Code'] == 'UnauthorizedOperation':
            logger.error("Antiope doesn't have proper permissions to this account")
            return(event)
        logger.critical("AWS Error getting info for {}: {}".format(message['account_id'], e))
        capture_error(message, context, e, "ClientError for {}: {}".format(message['account_id'], e))
        raise
    except Exception as e:
        logger.critical("{}\nMessage: {}\nContext: {}".format(e, message, vars(context)))
        capture_error(message, context, e, "General Exception for {}: {}".format(message['account_id'], e))
        raise

