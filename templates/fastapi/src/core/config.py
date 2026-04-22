from pydantic import Field, field_validator
from pydantic_settings import BaseSettings


class CommonSettings(BaseSettings):
    """Common settings for the application."""

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
    ENVIRONMENT: str = Field(default="dev")


class APISettings(BaseSettings):
    """API-specific settings."""

    FASTAPI_ROOT: str = Field(default="")
    API_PORT: int = Field(default=8000)
    CORS_ORIGINS: str = Field(default="http://localhost:3000")
    ALLOWED_CORS: list[str] = []

    def model_post_init(self, _) -> None:
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
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @field_validator("FASTAPI_ROOT", mode="before")
    def remove_trailing_slash(cls, value: str) -> str:
        """Remove any trailing slashes from FASTAPI_ROOT."""
        return value.rstrip("/")


common_settings = CommonSettings()
api_settings = APISettings()
