import json
import os
from datetime import datetime, timezone

import boto3

ec2 = boto3.client("ec2")
s3 = boto3.client("s3")
sns = boto3.client("sns")


def handler(event, context):
    filters = [
        {"Name": "tag:Environment", "Values": [os.environ["TARGET_TAG_VALUE"]]},
        {"Name": "instance-state-name", "Values": ["running"]},
    ]

    ids = []
    for page in ec2.get_paginator("describe_instances").paginate(Filters=filters):
        for reservation in page["Reservations"]:
            ids += [i["InstanceId"] for i in reservation["Instances"]]

    if ids:
        ec2.stop_instances(InstanceIds=ids)
        sns.publish(
            TopicArn=os.environ["TOPIC_ARN"],
            Subject="EC2 Cost Saver: instances stopped",
            Message=f"Stopped {len(ids)} instance(s): {', '.join(ids)}",
        )

    status = {
        "last_run": datetime.now(timezone.utc).isoformat(),
        "stopped_count": len(ids),
        "stopped_instances": ids,
    }
    s3.put_object(
        Bucket=os.environ["BUCKET_NAME"],
        Key="status.json",
        Body=json.dumps(status),
        ContentType="application/json",
    )
    return status