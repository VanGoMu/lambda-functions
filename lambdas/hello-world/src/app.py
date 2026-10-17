"""hello-world: greets whoever is named in the event.

Invocation payload: {"name": "AWS"}. The response follows the API Gateway proxy shape, so the
same code works behind a Function URL or an HTTP API if one is added later.
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

MAX_NAME_LENGTH = 64


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    """Entry point. `event` is the payload, `context` the runtime information."""
    name = event.get("name", "world") if isinstance(event, dict) else None
    if not isinstance(name, str) or not name.strip() or len(name) > MAX_NAME_LENGTH:
        logger.warning("rejected event without a valid name")
        return _response(
            400, {"error": f"'name' must be a non-empty string of at most {MAX_NAME_LENGTH} chars"}
        )

    greeting = os.environ.get("GREETING", "Hello")
    logger.debug("greeting %s", name)
    return _response(
        200,
        {
            "message": f"{greeting}, {name.strip()}!",
            "requestId": context.aws_request_id,
            # Which published version answered: the alias decides, not the caller.
            "version": context.function_version,
        },
    )
