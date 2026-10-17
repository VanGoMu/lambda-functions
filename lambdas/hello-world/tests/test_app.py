import json
from types import SimpleNamespace

import app
import pytest

CONTEXT = SimpleNamespace(aws_request_id="req-1", function_version="3")


def body(response):
    return json.loads(response["body"])


def test_greets_the_given_name():
    response = app.handler({"name": "AWS"}, CONTEXT)

    assert response["statusCode"] == 200
    assert body(response) == {"message": "Hello, AWS!", "requestId": "req-1", "version": "3"}


def test_defaults_to_world():
    assert body(app.handler({}, CONTEXT))["message"] == "Hello, world!"


def test_greeting_comes_from_the_environment(monkeypatch):
    monkeypatch.setenv("GREETING", "Hola")
    assert body(app.handler({"name": " Ana "}, CONTEXT))["message"] == "Hola, Ana!"


@pytest.mark.parametrize("event", [{"name": ""}, {"name": 42}, {"name": "x" * 65}, ["name"]])
def test_rejects_invalid_names(event):
    response = app.handler(event, CONTEXT)

    assert response["statusCode"] == 400
    assert "error" in body(response)
