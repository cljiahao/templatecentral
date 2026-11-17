from collections.abc import Callable
from typing import Annotated

from fastapi import Depends, HTTPException, status

from api.dependencies.auth import get_current_user


def get_current_roles(
    user_id: Annotated[str, Depends(get_current_user)],
) -> frozenset[str]:
    """Roles the current user holds. Grants none until a database lookup replaces it."""
    # Load roles per request, never from the token, so revocation is immediate; user_id forces authentication.
    return frozenset()


def require_roles(*roles: str) -> Callable[..., str]:
    """Dependency that admits a user holding any of `roles` and yields their id."""
    if not roles:
        raise ValueError("require_roles() needs at least one role.")
    required = frozenset(roles)

    def dependency(
        user_id: Annotated[str, Depends(get_current_user)],
        held: Annotated[frozenset[str], Depends(get_current_roles)],
    ) -> str:
        if held.isdisjoint(required):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions.",
            )
        return user_id

    return dependency


def ensure_owner(owner_id: str | None, user_id: str) -> None:
    """404 unless `user_id` owns the record; pass None when the record does not exist."""
    # 404 rather than 403 so callers cannot probe other users' ids.
    if owner_id is None or owner_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found.")
