from api.schemas.request.example import ExampleRequest
from api.schemas.response.example import ExampleResponse


def run_example(request: ExampleRequest) -> ExampleResponse:
    """Orchestrate the example request: parse, process, return."""
    greeting = f"Hello, {request.name}!"
    items = [greeting] * request.repeat_count
    return ExampleResponse(message=greeting, items=items)
