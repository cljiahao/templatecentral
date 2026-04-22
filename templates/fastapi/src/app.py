import textwrap
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.routes import router
from core.config import common_settings, api_settings
from error_handler import configure_exceptions


def configure_cors(app: FastAPI) -> None:
    """Configures Cross-Origin Resource Sharing (CORS) middleware for the FastAPI application.

    Args:
        app: The FastAPI application instance.
    """
    origins = api_settings.ALLOWED_CORS

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "Authorization"],
    )


def start_application() -> FastAPI:
    """Initialize and configures the FastAPI application.

    Returns:
        The initialized and configured FastAPI application instance.
    """
    app = FastAPI(
        title=common_settings.PROJECT_NAME,
        version=common_settings.PROJECT_VERSION,
        description=textwrap.dedent(common_settings.PROJECT_DESCRIPTION),
        root_path=f"/{api_settings.FASTAPI_ROOT}" if api_settings.FASTAPI_ROOT else "",
        swagger_ui_parameters={
            "defaultModelsExpandDepth": -1,  # Hide models section by default
            "docExpansion": "none",  # Collapse all sections by default
        },
    )

    configure_cors(app)
    configure_exceptions(app)
    app.include_router(router)

    return app


# Initialize the FastAPI application
app = start_application()
