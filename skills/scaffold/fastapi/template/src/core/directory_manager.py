from collections.abc import Sequence
from pathlib import Path
from shutil import rmtree


class DirectoryManager:
    """Handles directory structure and ensures required folders exist."""

    def __init__(self) -> None:
        """Initialize directory paths and ensure required folders exist."""
        self.base_dir = Path(__file__).resolve().parent.parent

        self.log_dir = self.base_dir / "log"

        self._initialize_base_folders()

    def _initialize_base_folders(self) -> None:
        """Initialize base required directory paths."""
        folders = [self.log_dir]
        for folder in folders:
            self.create_directory(folder)

    def create_directory(self, folder_path: Path, to_remove: bool = False) -> None:
        """Creates the directory, removing it first when to_remove is set."""
        if to_remove and folder_path.exists():
            try:
                rmtree(folder_path)
            except Exception as e:
                raise OSError(
                    f"Failed to remove existing directory: {folder_path}"
                ) from e

        try:
            folder_path.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            raise OSError(f"Failed to create directory: {folder_path}") from e

    def create_subdirectories(
        self, directory: Path, folder_list: Sequence[object], to_remove: bool = False
    ) -> None:
        """Creates each named subdirectory under directory."""
        for folder in folder_list:
            if not isinstance(folder, str):
                raise TypeError(
                    f"List of folders provided consist non str type: {folder}"
                )
            folder_path = directory / folder
            self.create_directory(folder_path, to_remove)


directory_manager = DirectoryManager()
