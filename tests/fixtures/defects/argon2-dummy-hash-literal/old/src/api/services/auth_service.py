from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from api.repositories.user_repository import create_user, get_user_by_email, get_user_by_id
from core.security import create_access_token, hash_password, verify_password

# Verified on the miss path so an unknown email costs the same as a wrong
# password — without it, response timing leaks which accounts exist.
DUMMY_HASH = "$argon2id$v=19$m=65536,t=3,p=1$c29tZXNhbHRzb21lc2E$Rdo0OMHkQXBTOTBqNCn0mPvBGiLxvGBIbxKZ0nJ0Aqo"


def register_user(db: Session, email: str, password: str, name: str) -> dict:
    if get_user_by_email(db, email):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered.",
        )
    user = create_user(
        db=db,
        email=email,
        hashed_password=hash_password(password),
        name=name,
    )
    return {"id": str(user.id), "email": user.email, "name": user.name}


def login_user(db: Session, email: str, password: str) -> str:
    user = get_user_by_email(db, email)
    password_ok = verify_password(password, user.hashed_password if user else DUMMY_HASH)
    if user is None or not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials.",
        )
