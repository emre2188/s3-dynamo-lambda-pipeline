import boto3
import csv
import json
import os

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    print("Event:", json.dumps(event))

    # Get S3 object
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]

    obj = s3.get_object(Bucket=bucket, Key=key)
    data = obj["Body"].read().decode("utf-8")

    # Auto-detect CSV or JSON
    if key.endswith(".json"):
        items = json.loads(data)
    elif key.endswith(".csv"):
        items = parse_csv(data)
    else:
        raise ValueError("Unsupported file type: " + key)

    # Insert items into DynamoDB
    for item in items:
        # Ensure partition key exists
        if "LocationAbbr" not in item:
            raise ValueError("Missing required field: LocationAbbr")

        table.put_item(Item=item)

    return {"statusCode": 200, "body": "Success"}

def parse_csv(data):
    lines = data.splitlines()
    reader = csv.DictReader(lines)
    items = []

    for row in reader:
        items.append({k: v for k, v in row.items()})
    return items
