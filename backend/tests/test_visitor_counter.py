import json

import pytest
from botocore.exceptions import ClientError


def body(response):
    return json.loads(response["body"])


def test_post_on_empty_table_starts_at_one(counter, load_event):
    response = counter.lambda_handler(load_event("post"), None)

    assert response["statusCode"] == 200
    assert body(response) == {"count": 1}


def test_post_increments_on_every_call(counter, load_event):
    counts = [
        body(counter.lambda_handler(load_event("post"), None))["count"]
        for _ in range(3)
    ]

    assert counts == [1, 2, 3]


def test_get_on_empty_table_returns_zero(counter, load_event):
    response = counter.lambda_handler(load_event("get"), None)

    assert response["statusCode"] == 200
    assert body(response) == {"count": 0}


def test_get_does_not_increment(counter, load_event):
    counter.lambda_handler(load_event("post"), None)
    first = counter.lambda_handler(load_event("get"), None)
    second = counter.lambda_handler(load_event("get"), None)

    assert body(first) == body(second) == {"count": 1}


def test_existing_count_is_read_and_incremented(counter, table, load_event):
    table.put_item(Item={"id": "visitors", "visitorCount": 41})

    assert body(counter.lambda_handler(load_event("get"), None)) == {"count": 41}
    assert body(counter.lambda_handler(load_event("post"), None)) == {"count": 42}
    assert table.get_item(Key={"id": "visitors"})["Item"]["visitorCount"] == 42


def test_unknown_route_returns_405(counter, load_event):
    response = counter.lambda_handler(load_event("bad"), None)

    assert response["statusCode"] == 405


@pytest.mark.parametrize("event_name", ["post", "get", "bad"])
def test_every_response_is_json(counter, load_event, event_name):
    response = counter.lambda_handler(load_event(event_name), None)

    assert response["headers"]["Content-Type"] == "application/json"
    json.loads(response["body"])


@pytest.mark.parametrize(
    "event_name, method", [("post", "update_item"), ("get", "get_item")]
)
def test_dynamodb_error_returns_503(
    counter, load_event, monkeypatch, capsys, event_name, method
):
    def fail(**kwargs):
        raise ClientError(
            {
                "Error": {
                    "Code": "ProvisionedThroughputExceededException",
                    "Message": "slow down",
                }
            },
            method,
        )

    monkeypatch.setattr(counter.table, method, fail)

    response = counter.lambda_handler(load_event(event_name), None)

    assert response["statusCode"] == 503
    assert body(response) == {"error": "Service temporarily unavailable"}
    assert "ProvisionedThroughputExceededException" in capsys.readouterr().out


def test_full_http_api_event(counter):
    """The trimmed events in backend/events only carry routeKey; this is the
    shape API Gateway HTTP API (payload 2.0) actually sends."""
    event = {
        "version": "2.0",
        "routeKey": "POST /visits",
        "rawPath": "/visits",
        "rawQueryString": "",
        "headers": {"origin": "https://example.cloudfront.net", "content-length": "0"},
        "requestContext": {
            "apiId": "de7gk4ckdh",
            "domainName": "de7gk4ckdh.execute-api.us-east-1.amazonaws.com",
            "http": {
                "method": "POST",
                "path": "/visits",
                "protocol": "HTTP/1.1",
                "sourceIp": "203.0.113.10",
            },
            "routeKey": "POST /visits",
            "stage": "$default",
        },
        "isBase64Encoded": False,
    }

    response = counter.lambda_handler(event, None)

    assert response["statusCode"] == 200
    assert body(response) == {"count": 1}
