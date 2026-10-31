from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from core.config import api_settings

ALGORITHM = "HS256"

# argon2id, t=3 / m=64 MiB / p=1 — above OWASP's minimums. Set explicitly because
# argon2-cffi's defaults (RFC 9106 low-memory profile) use p=4.
_ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=1)
# A named tuple, not `except A, B:` — that unparenthesized form (PEP 758) is a
# SyntaxError before 3.14, and the Beanie path pins projects to 3.13.
_VERIFY_ERRORS = (VerificationError, InvalidHashError)


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return _ph.verify(hashed_password, plain_password)
    except _VERIFY_ERRORS:
        return False


def create_access_token(subject: str, expires_delta: timedelta | None = None) -> str:
    """Create a JWT access token."""
    now = datetime.now(UTC)
    expire = now + (
        expires_delta or timedelta(minutes=api_settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    return jwt.encode(
        {"sub": subject, "iat": now, "exp": expire},
        api_settings.SECRET_KEY,
        algorithm=ALGORITHM,
    )


def decode_access_token(token: str) -> str | None:
    """Decode and validate a JWT token. Returns the subject or None."""
    try:
        # Pinned algorithm list blocks alg-confusion / "none"; require rejects tokens missing exp/sub.
        payload = jwt.decode(
            token,
            api_settings.SECRET_KEY,
            algorithms=[ALGORITHM],
            options={"require": ["exp", "sub"]},
        )
        return payload.get("sub")
    except jwt.PyJWTError:
        return None
