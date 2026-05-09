<!-- ref: standards/validation-patterns/fastapi.md
     loaded-by: standards/SKILL.md
     prereq: Stack = fastapi. Do not invoke this file directly — it is loaded at runtime by the templatecentral:standards skill. -->
### FastAPI (Python + Pydantic)

**1. Request Model with Validation**

```python
# src/api/projects/schemas.py
from pydantic import BaseModel, Field, EmailStr
from datetime import datetime

class CreateProjectRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = Field(None, max_length=500)

    model_config = {
        "json_schema_extra": {
            "example": {
                "name": "My Project",
                "description": "A great project",
            }
        }
    }


class ProjectResponse(BaseModel):
    id: str
    name: str
    description: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=12)


class PaginationQuery(BaseModel):
    page: int = Field(default=1, ge=1)
    limit: int = Field(default=10, ge=1, le=100)
    sort: str | None = Field(None, pattern=r'^(asc|desc)_\w+$')
```

**2. API Endpoint with Validation**

```python
# src/api/projects/routes.py
from fastapi import APIRouter, Query, status, UploadFile, File
from pydantic import ValidationError

from core.exceptions import InvalidInputError
from .schemas import CreateProjectRequest, ProjectResponse, PaginationQuery

router = APIRouter(prefix="/projects", tags=["projects"])


@router.post("", status_code=status.HTTP_201_CREATED, response_model=ProjectResponse)
async def create_project(req: CreateProjectRequest) -> ProjectResponse:
    """Create a new project.

    Pydantic automatically validates the request body.
    Returns 422 if validation fails.
    """
    # req is guaranteed to be valid
    # Your logic: project = await db.projects.create(req.model_dump())
    from datetime import datetime
    project = ProjectResponse(
        id="1",
        name=req.name,
        description=req.description,
        created_at=datetime.now(),
    )
    return project


@router.get("", response_model=list[ProjectResponse])
async def list_projects(
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=10, ge=1, le=100),
) -> list[ProjectResponse]:
    """List projects with pagination.

    Query parameters are automatically validated and coerced.
    """
    # page and limit are guaranteed to be valid integers
    offset = (page - 1) * limit
    # Your logic: projects = await db.projects.find(skip=offset, limit=limit)
    return []


@router.post("/upload")
async def upload_project_file(file: UploadFile = File(...)):
    """Upload a project file with validation."""
    # Validate file type
    allowed_types = {"image/jpeg", "image/png", "application/pdf"}
    if file.content_type not in allowed_types:
        raise InvalidInputError(
            f"File type {file.content_type} not allowed. "
            f"Allowed: {', '.join(allowed_types)}"
        )

    # Validate file size (max 10MB)
    max_size = 10 * 1024 * 1024
    contents = await file.read()
    if len(contents) > max_size:
        raise InvalidInputError("File must be under 10MB")

    # Validate filename
    if ".." in file.filename or file.filename.startswith("/"):
        raise InvalidInputError("Invalid filename")

    # Safe to use: file.filename, contents
    # await storage.save(file.filename, contents)

    return {"data": {"message": "File uploaded successfully"}}
```

**3. Form Data Validation**

```python
# src/api/auth/routes.py
from fastapi import APIRouter, Form, status
from .schemas import LoginRequest

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", status_code=status.HTTP_200_OK)
async def login(
    email: str = Form(...),
    password: str = Form(...),
):
    """Login via form data with validation."""
    # Manually validate since FastAPI doesn't auto-validate Form data
    try:
        req = LoginRequest(email=email, password=password)
    except ValidationError as e:
        raise InvalidInputError(f"Validation failed: {e}")

    # Safe to use: req.email, req.password
    # session = await auth.login(req.email, req.password)

    return {"data": {"message": "Login successful"}}
```

**4. External API Response Validation**

```python
# src/integrations/services/github_service.py
from pydantic import BaseModel, field_validator
import httpx
from core.exceptions import InvalidInputError

class GitHubUser(BaseModel):
    id: int | str
    login: str
    email: str | None = None

    @field_validator("login", mode="before")
    @classmethod
    def validate_login(cls, v):
        if not v or not isinstance(v, str):
            raise ValueError("login is required")
        return v


async def fetch_github_user(username: str) -> GitHubUser:
    """Fetch and validate GitHub user data."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"https://api.github.com/users/{username}")

    if response.status_code != 200:
        raise InvalidInputError("GitHub user not found")

    try:
        data = response.json()
        user = GitHubUser(**data)  # Validates automatically
        return user
    except ValidationError as e:
        raise InvalidInputError(f"Invalid GitHub API response: {e}")
```

## Testing / Verification

```bash
# Test endpoint validation
curl -X POST http://localhost:8000/projects \
  -H "Content-Type: application/json" \
  -d '{"name": ""}'  # Should return 422

pytest -v -s
```

## After Writing Code

Dispatch in order:
1. `shared-build-agent` — validate compilation
2. `shared-review-agent` — check code standards