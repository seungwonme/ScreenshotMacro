import json
from datetime import datetime
from pathlib import Path
from tkinter import Tk

import typer
from rich import print as rich_print
from rich.console import Console
from rich.table import Table

import src.constants as const
from src.find_duplicate_images import display_duplicate_groups
from src.find_duplicate_images import find_duplicate_images as find_dupes
from src.find_duplicate_images import setup_logger
from src.gui_setup import setup_common_gui
from src.macro import ScreenshotMacro
from src.self import ScreenshotSelf
from src.utils import clean_screenshots

app = typer.Typer(
    name="screenshot-macro",
    help="Screenshot automation tool for macOS with GUI interface",
    add_completion=False,
    no_args_is_help=True,
    context_settings={"help_option_names": ["-h", "--help"]},
)

console = Console()


def load_config() -> dict:
    """Load configuration from config.json"""
    config_path = Path("config.json")
    if not config_path.exists():
        typer.echo("Warning: config.json not found, using defaults", err=True)
        return {}

    try:
        with open(config_path, encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        typer.echo(f"Error parsing config.json: {e}", err=True)
        return {}


@app.command()
def run():
    """Run screenshot macro mode with GUI"""

    root = Tk()
    root.geometry(const.GuiConfig.WINDOW_SIZE)
    root.attributes("-topmost", True)

    setup_common_gui(root)

    config = load_config()
    macro = ScreenshotMacro(root)
    macro.config = config  # Pass config to macro instance
    macro.setup()

    root.mainloop()


@app.command()
def self():
    """Run self mode (manual screenshot capture) with GUI"""

    root = Tk()
    root.geometry(const.GuiConfig.WINDOW_SIZE)
    root.attributes("-topmost", True)

    setup_common_gui(root)

    ScreenshotSelf(root).setup()

    root.mainloop()


@app.command()
def clean():
    """Clean all screenshots from the screenshots directory"""
    typer.confirm("Are you sure you want to delete all screenshots?", abort=True)
    clean_screenshots()
    rich_print("[green]✓[/green] All screenshots have been cleaned")


@app.command(name="find-duplicates")
def find_duplicates(
    directory: str = typer.Option("./screenshots", "-d", "--directory", help="Directory to search"),
    threshold: int = typer.Option(0, "-t", "--threshold", help="Hash difference threshold"),
):
    """Find duplicate images in the specified directory"""

    logger = setup_logger()
    duplicates = find_dupes(directory, threshold, logger)
    display_duplicate_groups(duplicates, logger)


@app.command()
def list_screenshots():
    """List all screenshots in the screenshots directory"""
    screenshots_dir = Path("./screenshots")

    if not screenshots_dir.exists():
        rich_print("[yellow]Screenshots directory does not exist[/yellow]")
        return

    screenshots = sorted(
        [f for f in screenshots_dir.iterdir() if f.suffix.lower() in {".png", ".jpg", ".jpeg"}],
        key=lambda x: x.stat().st_mtime,
        reverse=True,
    )

    if not screenshots:
        rich_print("[yellow]No screenshots found[/yellow]")
        return

    table = Table(title=f"Screenshots ({len(screenshots)} files)")
    table.add_column("Filename", style="cyan")
    table.add_column("Size", justify="right", style="green")
    table.add_column("Modified", style="magenta")

    for screenshot in screenshots[:20]:  # Show last 20
        size = screenshot.stat().st_size
        size_str = f"{size / 1024:.1f} KB" if size < 1024 * 1024 else f"{size / 1024 / 1024:.1f} MB"
        modified = screenshot.stat().st_mtime

        date_str = datetime.fromtimestamp(modified).strftime("%Y-%m-%d %H:%M:%S")

        table.add_row(screenshot.name, size_str, date_str)

    console.print(table)

    if len(screenshots) > 20:
        rich_print(f"\n[dim]... and {len(screenshots) - 20} more files[/dim]")


@app.command()
def stats():
    """Show statistics about captured screenshots"""
    screenshots_dir = Path("./screenshots")

    if not screenshots_dir.exists():
        rich_print("[yellow]Screenshots directory does not exist[/yellow]")
        return

    screenshots = [
        f for f in screenshots_dir.iterdir() if f.suffix.lower() in {".png", ".jpg", ".jpeg"}
    ]

    if not screenshots:
        rich_print("[yellow]No screenshots found[/yellow]")
        return

    total_count = len(screenshots)
    total_size = sum(f.stat().st_size for f in screenshots)

    # Get date range
    mtimes = [f.stat().st_mtime for f in screenshots]
    oldest = min(mtimes)
    newest = max(mtimes)

    oldest_date = datetime.fromtimestamp(oldest).strftime("%Y-%m-%d %H:%M:%S")
    newest_date = datetime.fromtimestamp(newest).strftime("%Y-%m-%d %H:%M:%S")

    # Display stats
    rich_print("[bold]Screenshot Statistics[/bold]\n")
    rich_print(f"📊 Total screenshots: [cyan]{total_count}[/cyan]")
    rich_print(f"💾 Total size: [green]{total_size / 1024 / 1024:.1f} MB[/green]")
    rich_print(f"📅 Oldest: [magenta]{oldest_date}[/magenta]")
    rich_print(f"📅 Newest: [magenta]{newest_date}[/magenta]")

    if total_count > 0:
        avg_size = total_size / total_count
        rich_print(f"📏 Average size: [yellow]{avg_size / 1024:.1f} KB[/yellow]")


@app.command()
def config():
    """Show current configuration"""
    config_data = load_config()

    if not config_data:
        rich_print("[yellow]No configuration loaded[/yellow]")
        return

    rich_print("[bold]Current Configuration[/bold]\n")

    # Pretty print the config
    rich_print(json.dumps(config_data, indent=2))

    # Show interpreted action
    action_config = config_data.get("macro", {}).get("action", {})
    action_type = action_config.get("type", "key")

    rich_print(f"\n[bold]Action Type:[/bold] {action_type}")
    if action_type == "key":
        rich_print(f"[bold]Key:[/bold] {action_config.get('key', 'right')}")
    elif action_type == "click":
        position = action_config.get("position", "current mouse position")
        rich_print(f"[bold]Click Position:[/bold] {position}")


def main():
    """Entry point for the CLI"""
    app()


if __name__ == "__main__":
    main()
