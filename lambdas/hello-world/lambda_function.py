import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def lambda_handler(event, context):
    """Entry point invoked by Lambda. `event` is the trigger payload,
    `context` carries runtime info (request ID, remaining time, etc.)."""
    logger.info("Received event: %s", json.dumps(event))

    name = event.get("name", "world")
    greeting = os.environ.get("GREETING", "Hello")
    message = f"{greeting}, {name}! (request_id={context.aws_request_id})"

    return {
        "statusCode": 200,
        "body": json.dumps({"message": message}),
    }
