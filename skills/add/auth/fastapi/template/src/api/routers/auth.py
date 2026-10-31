from fastapi import APIRouter

from api.schemas.request.auth import LoginRequest, RegisterRequest
from api.schemas.response.auth import TokenResponse, UserResponse
from api.services.auth_service import login_user, register_user

router = APIRouter(prefix="/auth")


# Plain `def`: argon2 hashing is ~100 ms of CPU, and FastAPI runs sync handlers in its
# threadpool instead of blocking the event loop.
@router.post("/register", response_model=UserResponse)
def register(body: RegisterRequest) -> UserResponse:
    """Register a new user account."""
    user = register_user(email=body.email, password=body.password, name=body.name)
    return UserResponse(id=user["id"], email=user["email"], name=user["name"])


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest) -> TokenResponse:
    """Authenticate and receive a JWT token."""
    token = login_user(email=body.email, password=body.password)
    return TokenResponse(access_token=token)
