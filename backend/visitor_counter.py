import os
import json
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["DYNAMODB_TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        if event["routeKey"] == "POST /visits":
            return increment_visitor_count()
        elif event["routeKey"] == "GET /visits":
            return get_visitor_count()
        else:
            return {
                "statusCode": 405,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps("Method Not Allowed")
            }
    except ClientError as error:
        print(f"DynamoDB error: {error.response['Error']['Code']}")
        return {
            "statusCode": 503,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Service temporarily unavailable"})
        }

def increment_visitor_count():
    response = table.update_item(
        Key={"id": "visitors"},
        UpdateExpression="ADD visitorCount :val",
        ExpressionAttributeValues={":val": 1},
        ReturnValues="UPDATED_NEW"
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"count": int(response["Attributes"]["visitorCount"])})
    }

def get_visitor_count():
    response = table.get_item(
        Key={"id": "visitors"}
    )

    item = response.get("Item")
    count = int(item["visitorCount"]) if item else 0

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"count": count})
    }