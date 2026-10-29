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
        """Helper method to ensure the destination directory exists, and remove it if necessary.

        Args:
            folder_path: The path to the directory.
            to_remove: If True, remove the directory before creating it.
        """
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
        self, directory: Path, folder_list: list[str], to_remove: bool = False
    ) -> None:
        """Creates multiple subdirectories under a specified base directory.

        Args:
            directory: The parent directory where the subdirectories will be created.
            folder_list: A list of subdirectory names to create and count.

        Raises:
            TypeError: If non str type is found in folder_list
        """
        for folder in folder_list:
            if not isinstance(folder, str):
                raise TypeError(
                    f"List of folders provided consist non str type: {folder}"
                )
            folder_path = directory / folder
            self.create_directory(folder_path, to_remove)


directory_manager = DirectoryManager()
