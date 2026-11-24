import main
from core.config import api_settings


def test_load_environment_reports_a_missing_env_file(monkeypatch, capsys) -> None:
    monkeypatch.setattr(main, "find_dotenv", lambda _name: "")
    main.load_environment()
    assert "not found" in capsys.readouterr().out


def test_load_environment_loads_the_file_it_finds(monkeypatch) -> None:
    loaded: list[str] = []
    monkeypatch.setattr(main, "find_dotenv", lambda _name: "/project/.env")
    monkeypatch.setattr(
        main, "load_dotenv", lambda dotenv_path: loaded.append(dotenv_path)
    )
    main.load_environment()
    assert loaded == ["/project/.env"]


def test_run_api_serves_the_app_on_the_configured_port(monkeypatch) -> None:
    calls: list[tuple[tuple, dict]] = []
    monkeypatch.setattr(main.uvicorn, "run", lambda *a, **kw: calls.append((a, kw)))
    main.run_api()
    (target,), options = calls[0]
    assert target == "app:app"
    assert (options["host"], options["port"]) == ("127.0.0.1", api_settings.API_PORT)
    assert options["log_config"] is None
