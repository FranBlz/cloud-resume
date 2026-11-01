import importlib
import json
import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

BACKEND_DIR = Path(__file__).resolve().parents[1]
EVENTS_DIR = BACKEND_DIR / "events"
TABLE_NAME = "test-crc-stats"

sys.path.insert(0, str(BACKEND_DIR))


@pytest.fixture
def aws_env(monkeypatch):
    """Fake credentials so nothing can ever reach the real account."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("DYNAMODB_TABLE_NAME", TABLE_NAME)
    monkeypatch.delenv("AWS_PROFILE", raising=False)


@pytest.fixture
def table(aws_env):
    """An empty moto table with the same key schema as franb-crc-stats."""
    with mock_aws():
        dynamodb = boto3.resource("dynamodb")
        yield dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )


@pytest.fixture
def counter(table):
    """Import visitor_counter fresh, after the env var and the mock exist.

    The module builds its boto3 table at import time, so importing it at the
    top of a test file would read the real environment instead of the mock.
    """
    sys.modules.pop("visitor_counter", None)
    yield importlib.import_module("visitor_counter")
    sys.modules.pop("visitor_counter", None)


@pytest.fixture
def load_event():
    def _load(name):
        return json.loads((EVENTS_DIR / f"{name}.json").read_text())

    return _load
