from typing import Any, Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class CommonSettings(BaseSettings):
    """Common settings for the application."""

    # Read src/.env directly rather than relying on main.py's load_dotenv(): the Docker
    # entrypoints run `uvicorn app:app --app-dir src`, which never executes main.py.
    model_config = SettingsConfigDict(env_file="src/.env", extra="ignore")

    PROJECT_NAME: str = Field(default="My Project")
    PROJECT_VERSION: str = Field(default="v1.0.0")
    PROJECT_DESCRIPTION: str = Field(
        default="""
        A FastAPI application built with
        [FastAPI](https://fastapi.tiangolo.com/)

        - [Source Code](https://www.github.com)
        - [Issues](https://www.github.com/issues)
        """
    )
    # Closed set (parity with NestJS's z.enum): an unknown value such as "production" must
    # fail at boot, not slip past main.py's prod/uat check and run with auto-reload on.
    ENVIRONMENT: Literal["dev", "uat", "prod"] = Field(default="dev")
    # Injected by appCentral at runtime: the only origin allowed to frame this app.
    # Validated in core/security_headers.py; unset or invalid denies all framing.
    APPCENTRAL_PORTAL_ORIGIN: str = Field(default="")


class APISettings(BaseSettings):
    """API-specific settings."""

    model_config = SettingsConfigDict(env_file="src/.env", extra="ignore")

    FASTAPI_ROOT: str = Field(default="")
    API_PORT: int = Field(default=8000)
    CORS_ORIGINS: str = Field(default="http://localhost:3000")
    ALLOWED_CORS: list[str] = []
    TRUST_PROXY: str = Field(default="")

    def model_post_init(self, __context: Any) -> None:
        """Compute allowed CORS origins after initialization."""
        self.ALLOWED_CORS = self._compute_allowed_cors()

    def _compute_allowed_cors(self) -> list[str]:
        if common_settings.ENVIRONMENT == "dev":
            return [
                "http://localhost:3000",
                "http://localhost:3001",
                "http://localhost:5173",
                "http://127.0.0.1:3000",
                "http://127.0.0.1:5173",
            ]
        return [
            origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()
        ]

    @field_validator("FASTAPI_ROOT", mode="before")
    @classmethod
    def remove_trailing_slash(cls, value: str) -> str:
        """Remove any trailing slashes from FASTAPI_ROOT."""
        return value.rstrip("/")


common_settings = CommonSettings()
# Fields without a default (e.g. added by templatecentral:add) are filled from the
# environment at runtime; pyright only sees the constructor signature and flags them.
api_settings = APISettings()  # pyright: ignore[reportCallIssue]
