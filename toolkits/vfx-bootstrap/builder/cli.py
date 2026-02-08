"""
Command-line interface for vfx-bootstrap builder.
"""

import argparse
import sys
from pathlib import Path

from .cache import BuildCache
from .container import ContainerBuilder
from .core import VFXBuilder


def cmd_build(args):
    """Handle build command."""
    builder = VFXBuilder(
        recipes_dir=args.recipes,
        output_dir=args.output,
        cache_dir=args.cache_dir,
        log_dir=args.log_dir,
        platform=args.platform,
        channels=args.channel,
    )

    if args.recipe:
        # Build specific recipe
        result = builder.build(
            args.recipe,
            use_cache=not args.no_cache,
            verbose=args.verbose,
        )
        return 0 if result.success else 1
    else:
        # Build all or specified targets
        results = builder.build_all(
            targets=args.targets if args.targets else None,
            use_cache=not args.no_cache,
            verbose=args.verbose,
            continue_on_error=args.continue_on_error,
        )
        failed = sum(1 for r in results if not r.success)
        return 1 if failed > 0 else 0


def cmd_list(args):
    """Handle list command."""
    builder = VFXBuilder(
        recipes_dir=args.recipes,
        output_dir=args.output or Path("."),
        platform=args.platform,
    )

    recipes = builder.list_recipes()
    print(f"Available recipes ({len(recipes)}):")
    for recipe in recipes:
        info = builder.get_recipe_info(recipe)
        deps = ", ".join(info.get("dependencies", [])) or "none"
        print(f"  {recipe}")
        if args.verbose:
            print(f"    dependencies: {deps}")


def cmd_info(args):
    """Handle info command."""
    builder = VFXBuilder(
        recipes_dir=args.recipes,
        output_dir=args.output or Path("."),
        platform=args.platform,
    )

    info = builder.get_recipe_info(args.recipe)
    if "error" in info:
        print(info["error"])
        return 1

    print(f"Recipe: {info['name']}")
    print(f"Path: {info['path']}")
    print(f"Dependencies: {', '.join(info['dependencies']) or 'none'}")
    return 0


def cmd_order(args):
    """Handle order command (show build order)."""
    builder = VFXBuilder(
        recipes_dir=args.recipes,
        output_dir=args.output or Path("."),
        platform=args.platform,
    )

    targets = args.targets if args.targets else None
    order = builder.resolve_build_order(targets)

    print(f"Build order ({len(order)} packages):")
    for i, recipe in enumerate(order, 1):
        print(f"  {i}. {recipe}")


def cmd_cache(args):
    """Handle cache subcommand."""
    if not args.cache_dir:
        print("Error: --cache-dir required for cache commands")
        return 1

    cache = BuildCache(args.cache_dir)

    if args.cache_action == "status":
        status = cache.status()
        print(f"Cache directory: {status['cache_dir']}")
        print(f"Entries: {status['num_entries']}")
        print(f"Total size: {status['total_size_mb']:.2f} MB")

    elif args.cache_action == "list":
        entries = cache.list_entries()
        print(f"Cache entries ({len(entries)}):")
        for entry in entries:
            print(f"  {entry['key']}")
            for pkg in entry.get("packages", []):
                print(f"    - {pkg['filename']}")

    elif args.cache_action == "clear":
        if args.force or input("Clear all cache entries? [y/N] ").lower() == "y":
            count = cache.clear()
            print(f"Cleared {count} cache entries")

    return 0


def cmd_container(args):
    """Handle container subcommand."""
    container = ContainerBuilder()

    if args.container_action == "status":
        status = container.status()
        print(f"Runtime: {status['runtime']}")
        print(f"Available: {status['available']}")
        if status["available"]:
            print(f"Version: {status['version']}")
            print(f"Default image: {status['default_image']}")

    elif args.container_action == "pull":
        image = args.image or container.default_image
        success = container.pull_image(image)
        return 0 if success else 1

    elif args.container_action == "shell":
        image = args.image or container.default_image
        container.run_shell(image)

    return 0


def _default_recipes_dir() -> Path:
    """Resolve the default recipes directory relative to the package location."""
    # builder/cli.py -> builder/ -> vfx-bootstrap/ -> vfx-bootstrap/recipes/
    pkg_dir = Path(__file__).resolve().parent.parent
    recipes = pkg_dir / "recipes"
    if recipes.is_dir():
        return recipes
    # Fallback to CWD/recipes for standalone use
    return Path("recipes")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="VFX Bootstrap Build System",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Global arguments
    parser.add_argument(
        "--recipes",
        "-r",
        type=Path,
        default=_default_recipes_dir(),
        help="Recipes directory (default: auto-detected from package location)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        default=Path.home() / "Development" / "vfx" / "builds",
        help="Output directory for packages (default: ~/Development/vfx/builds)",
    )
    parser.add_argument(
        "--platform", "-p", default="vfx2024", help="VFX Platform target (default: vfx2024)"
    )
    parser.add_argument("--cache-dir", type=Path, help="Build cache directory")
    parser.add_argument("--log-dir", type=Path, help="Log directory")
    parser.add_argument("--channel", "-c", action="append", help="Additional conda channels")
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Build command
    build_parser = subparsers.add_parser("build", help="Build packages")
    build_parser.add_argument("recipe", nargs="?", help="Specific recipe to build")
    build_parser.add_argument("--targets", nargs="*", help="Target recipes to build")
    build_parser.add_argument("--no-cache", action="store_true", help="Disable cache")
    build_parser.add_argument(
        "--continue-on-error", action="store_true", help="Continue after failures"
    )
    build_parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    build_parser.set_defaults(func=cmd_build)

    # List command
    list_parser = subparsers.add_parser("list", help="List recipes")
    list_parser.add_argument("--verbose", "-v", action="store_true", help="Show dependencies")
    list_parser.set_defaults(func=cmd_list)

    # Info command
    info_parser = subparsers.add_parser("info", help="Show recipe info")
    info_parser.add_argument("recipe", help="Recipe name")
    info_parser.set_defaults(func=cmd_info)

    # Order command
    order_parser = subparsers.add_parser("order", help="Show build order")
    order_parser.add_argument("--targets", nargs="*", help="Target recipes")
    order_parser.set_defaults(func=cmd_order)

    # Cache subcommand
    cache_parser = subparsers.add_parser("cache", help="Manage build cache")
    cache_parser.add_argument("cache_action", choices=["status", "list", "clear"])
    cache_parser.add_argument("--force", "-f", action="store_true", help="Force action")
    cache_parser.set_defaults(func=cmd_cache)

    # Container subcommand
    container_parser = subparsers.add_parser("container", help="Container operations")
    container_parser.add_argument("container_action", choices=["status", "pull", "shell"])
    container_parser.add_argument("--image", help="Container image")
    container_parser.set_defaults(func=cmd_container)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
