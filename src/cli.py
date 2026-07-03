"""CLI interface for ScreenshotMacro."""

from __future__ import annotations

import sys
from datetime import datetime

import typer
from loguru import logger
from rich import print as rich_print
from rich.console import Console
from rich.table import Table

from src.config import ActionConfig, ConfigManager, get_config
from src.find_duplicate_images import display_duplicate_groups
from src.find_duplicate_images import find_duplicate_images as find_dupes
from src.utils import clean_screenshots as do_clean_screenshots
from src.utils import list_screenshots as do_list_screenshots

app = typer.Typer(
    name="screenshot-macro",
    help="Screenshot automation tool for macOS with GUI interface",
    add_completion=False,
    no_args_is_help=True,
    context_settings={"help_option_names": ["-h", "--help"]},
)

console = Console()


def _configure_logging(verbose: bool = False) -> None:
    """Configure loguru logging."""
    logger.remove()
    level = "DEBUG" if verbose else "INFO"
    logger.add(
        sys.stderr,
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <level>{message}</level>",
        level=level,
        colorize=True,
    )


@app.callback()
def main_callback(
    verbose: bool = typer.Option(False, "-v", "--verbose", help="Enable verbose output"),
) -> None:
    """Screenshot automation tool for macOS."""
    _configure_logging(verbose)


@app.command()
def run() -> None:
    """Run screenshot macro mode with PyQt6 GUI."""
    try:
        from src.gui_pyqt import run_gui

        run_gui()
    except ImportError as exc:
        rich_print("[red]PyQt6 is not installed. Run 'uv add pyqt6' to install.[/red]")
        raise typer.Exit(1) from exc
    except Exception as e:
        logger.error(f"GUI execution error: {e}")
        rich_print(f"[red]GUI error: {e}[/red]")
        raise typer.Exit(1) from e


@app.command(name="self", deprecated=True)
def self_mode() -> None:
    """[DEPRECATED] Use 'screenshot-macro run' instead."""
    rich_print("[red]Self mode is deprecated. Use 'screenshot-macro run' for GUI mode.[/red]")
    raise typer.Exit(1)


@app.command()
def clean(
    force: bool = typer.Option(False, "-f", "--force", help="Skip confirmation prompt"),
) -> None:
    """Clean all screenshots from the screenshots directory."""
    if not force:
        typer.confirm("Are you sure you want to delete all screenshots?", abort=True)

    config = get_config()
    deleted = do_clean_screenshots(config.screenshot)

    if deleted > 0:
        rich_print(f"[green]Cleaned {deleted} screenshot(s)[/green]")
    else:
        rich_print("[yellow]No screenshots to clean[/yellow]")


@app.command()
def macro(
    reps: int = typer.Option(None, "-n", "--reps", help="Repetitions (default: from config)"),
    key: str = typer.Option(
        None, "-k", "--key", help="Key to press each step (default: from config)"
    ),
    wait: float = typer.Option(
        None, "-w", "--wait", help="Initial wait seconds (default: from config)"
    ),
    delay_min: float = typer.Option(
        None, "--delay-min", help="Min delay between captures (default: from config)"
    ),
    delay_max: float = typer.Option(
        None, "--delay-max", help="Max delay between captures (default: from config)"
    ),
) -> None:
    """Run the screenshot macro without the GUI (headless / automation).

    Uses the capture area saved in config.json; override timing/action via flags.
    """
    from PyQt6.QtCore import QCoreApplication

    from src.macro_pyqt import MacroWorker

    config = get_config()
    area = config.gui.area
    x1, y1 = area.top_left
    x2, y2 = area.bottom_right
    x, y = min(x1, x2), min(y1, y2)
    width, height = abs(x2 - x1), abs(y2 - y1)
    if width <= 0 or height <= 0:
        rich_print(
            "[red]Configured capture area has invalid dimensions. Run the GUI to set it.[/red]"
        )
        raise typer.Exit(1)

    macro_cfg = config.macro
    repetitions = reps if reps is not None else macro_cfg.repetitions
    initial_wait = wait if wait is not None else macro_cfg.initial_wait
    d_min = delay_min if delay_min is not None else macro_cfg.delay.min
    d_max = delay_max if delay_max is not None else macro_cfg.delay.max
    action = ActionConfig(type="key", key=key) if key else macro_cfg.action

    if QCoreApplication.instance() is None:
        QCoreApplication([])

    worker = MacroWorker(
        repetitions,
        d_min,
        d_max,
        x,
        y,
        width,
        height,
        action_config=action,
        initial_wait=initial_wait,
    )
    worker.countdown.connect(lambda r: rich_print(f"[dim]Starting in {r}s...[/dim]"))
    worker.progress.connect(lambda c, t: logger.info(f"Captured {c}/{t}"))
    worker.error.connect(lambda msg: logger.error(msg))

    rich_print(
        f"[cyan]Running macro: {repetitions} reps, area {width}x{height} at ({x},{y}), "
        f"action={action.type}[/cyan]"
    )
    try:
        worker.run()  # synchronous: runs the loop on the current thread
        rich_print("[green]Macro completed[/green]")
    except KeyboardInterrupt:
        worker.stop()
        rich_print("\n[yellow]Macro interrupted[/yellow]")
        raise typer.Exit(130) from None


@app.command(name="find-duplicates")
def find_duplicates(
    directory: str = typer.Option(
        None,
        "-d",
        "--directory",
        help="Directory to search (default: from config)",
    ),
    threshold: int = typer.Option(
        0,
        "-t",
        "--threshold",
        help="Hash difference threshold (0 for exact match)",
    ),
) -> None:
    """Find duplicate images in the specified directory."""
    if directory is None:
        config = get_config()
        directory = str(config.screenshot.directory)

    duplicates = find_dupes(directory, threshold)
    display_duplicate_groups(duplicates)


@app.command(name="list")
def list_screenshots(
    limit: int = typer.Option(20, "-n", "--limit", help="Maximum screenshots to show"),
) -> None:
    """List all screenshots in the screenshots directory."""
    config = get_config()
    screenshots = do_list_screenshots(config.screenshot)

    if not screenshots:
        rich_print("[yellow]No screenshots found[/yellow]")
        return

    table = Table(title=f"Screenshots ({len(screenshots)} files)")
    table.add_column("Filename", style="cyan")
    table.add_column("Size", justify="right", style="green")
    table.add_column("Modified", style="magenta")

    for screenshot in screenshots[:limit]:
        size = screenshot.stat().st_size
        size_str = f"{size / 1024:.1f} KB" if size < 1024 * 1024 else f"{size / 1024 / 1024:.1f} MB"
        modified = screenshot.stat().st_mtime
        date_str = datetime.fromtimestamp(modified).strftime("%Y-%m-%d %H:%M:%S")
        table.add_row(screenshot.name, size_str, date_str)

    console.print(table)

    if len(screenshots) > limit:
        rich_print(f"\n[dim]... and {len(screenshots) - limit} more files[/dim]")


@app.command()
def stats() -> None:
    """Show statistics about captured screenshots."""
    config = get_config()
    screenshots = do_list_screenshots(config.screenshot)

    if not screenshots:
        rich_print("[yellow]No screenshots found[/yellow]")
        return

    total_count = len(screenshots)
    total_size = sum(f.stat().st_size for f in screenshots)

    mtimes = [f.stat().st_mtime for f in screenshots]
    oldest = min(mtimes)
    newest = max(mtimes)

    oldest_date = datetime.fromtimestamp(oldest).strftime("%Y-%m-%d %H:%M:%S")
    newest_date = datetime.fromtimestamp(newest).strftime("%Y-%m-%d %H:%M:%S")

    rich_print("[bold]Screenshot Statistics[/bold]\n")
    rich_print(f"Total screenshots: [cyan]{total_count}[/cyan]")
    rich_print(f"Total size: [green]{total_size / 1024 / 1024:.1f} MB[/green]")
    rich_print(f"Oldest: [magenta]{oldest_date}[/magenta]")
    rich_print(f"Newest: [magenta]{newest_date}[/magenta]")

    if total_count > 0:
        avg_size = total_size / total_count
        rich_print(f"Average size: [yellow]{avg_size / 1024:.1f} KB[/yellow]")


@app.command()
def config(
    reload: bool = typer.Option(False, "-r", "--reload", help="Force reload config from file"),
) -> None:
    """Show current configuration."""
    manager = ConfigManager()

    if reload:
        manager.reload()
        rich_print("[green]Config reloaded[/green]\n")

    config_data = manager.config

    rich_print("[bold]Current Configuration[/bold]\n")

    # GUI settings
    rich_print("[bold cyan]GUI Settings[/bold cyan]")
    rich_print(f"  Window size: {config_data.gui.window_size}")
    rich_print(f"  Top-left: {config_data.gui.area.top_left}")
    rich_print(f"  Bottom-right: {config_data.gui.area.bottom_right}")

    # Macro settings
    rich_print("\n[bold cyan]Macro Settings[/bold cyan]")
    rich_print(f"  Repetitions: {config_data.macro.repetitions}")
    rich_print(f"  Delay: {config_data.macro.delay.min}-{config_data.macro.delay.max}s")
    rich_print(f"  Initial wait: {config_data.macro.initial_wait}s")

    # Action settings
    action = config_data.macro.action
    rich_print(f"  Action type: {action.type}")
    if action.type == "key":
        rich_print(f"  Key: {action.key}")
    else:
        rich_print(f"  Click position: {action.position or 'current'}")

    # Screenshot settings
    rich_print("\n[bold cyan]Screenshot Settings[/bold cyan]")
    rich_print(f"  Directory: {config_data.screenshot.directory}")
    rich_print(f"  Format: {config_data.screenshot.format}")
    rich_print(f"  Prefix: {config_data.screenshot.prefix}")


def main() -> None:
    """Entry point for the CLI."""
    # PyInstaller 번들에서 인자 없이 실행 시 자동으로 GUI 실행
    if getattr(sys, "frozen", False) and len(sys.argv) == 1:
        sys.argv.append("run")
    app()


if __name__ == "__main__":
    main()
