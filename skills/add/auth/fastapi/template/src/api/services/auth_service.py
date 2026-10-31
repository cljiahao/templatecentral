from fastapi import HTTPException, status

from core.security import hash_password


def register_user(email: str, password: str, name: str) -> dict:
    """Register a new user. Persist to database after running `templatecentral:add` (database)."""
    hashed = hash_password(password)
    user_id = "generated-id"
    return {"id": user_id, "email": email, "name": name, "hashed_password": hashed}


def login_user(email: str, password: str) -> str:
    """Authenticate user and return JWT. Implement DB lookup after running `templatecentral:add` (database)."""
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Database integration required. Run `templatecentral:add` (database) to complete auth.",
    )
