"""
Command-line interface for vfx-bootstrap packager.
"""

import argparse
import sys
from pathlib import Path

from .exporters import ArchiveExporter, CondaExporter, TarballExporter
from .schema import PackageManifest

EXPORTERS = {
    "conda": CondaExporter,
    "tarball": TarballExporter,
    "archive": ArchiveExporter,
}


def cmd_package(args):
    """Handle package command."""
    # Load manifest
    manifest = PackageManifest.load(args.manifest)

    print(f"Packaging: {manifest.name} {manifest.version}")
    print(f"Source: {args.source}")
    print(f"Output: {args.output}")

    formats = args.format if args.format != ["all"] else list(EXPORTERS.keys())

    results = []
    for fmt in formats:
        if fmt not in EXPORTERS:
            print(f"Unknown format: {fmt}")
            continue

        print(f"\nExporting to {fmt}...")
        exporter_class = EXPORTERS[fmt]
        exporter = exporter_class(manifest)

        try:
            output_file = exporter.export(
                source_dir=args.source,
                output_dir=args.output,
                components=args.components,
            )
            print(f"  Created: {output_file}")
            results.append((fmt, output_file, True))
        except Exception as e:
            print(f"  Error: {e}")
            results.append((fmt, None, False))

    # Summary
    print("\n" + "=" * 50)
    print("Packaging Summary")
    print("=" * 50)
    for fmt, path, success in results:
        status = "OK" if success else "FAILED"
        print(f"  {fmt}: {status}")
        if path:
            print(f"    {path}")

    failed = sum(1 for _, _, s in results if not s)
    return 1 if failed > 0 else 0


def cmd_validate(args):
    """Handle validate command."""
    manifest = PackageManifest.load(args.manifest)

    print(f"Validating: {manifest.name} {manifest.version}")
    print(f"Source: {args.source}")

    # Create a dummy exporter just for validation
    from .exporters.base import Exporter

    class DummyExporter(Exporter):
        @property
        def format_name(self):
            return "validate"

        @property
        def file_extension(self):
            return ""

        def export(self, *args, **kwargs):
            pass

    exporter = DummyExporter(manifest)
    missing = exporter.validate_source(Path(args.source), args.components)

    if missing:
        print(f"\nMissing files ({len(missing)}):")
        for f in missing:
            print(f"  - {f}")
        return 1
    else:
        print("\nAll required files present.")
        return 0


def cmd_show(args):
    """Handle show command."""
    manifest = PackageManifest.load(args.manifest)

    print(f"Name: {manifest.name}")
    print(f"Version: {manifest.version}")
    print(f"Description: {manifest.description}")
    print(f"License: {manifest.license}")
    print(f"Homepage: {manifest.homepage}")

    print(f"\nComponents ({len(manifest.components)}):")
    for comp in manifest.components:
        opt = " (optional)" if comp.optional else ""
        print(f"  - {comp.name}{opt}")
        print(f"    Files: {len(comp.files)}")
        print(f"    Dependencies: {', '.join(comp.dependencies) or 'none'}")

    print(f"\nAll dependencies:")
    for dep in manifest.get_all_dependencies():
        print(f"  - {dep}")


def cmd_init(args):
    """Handle init command (create template manifest)."""
    output_file = Path(args.output)

    if output_file.exists() and not args.force:
        print(f"File already exists: {output_file}")
        print("Use --force to overwrite")
        return 1

    manifest = PackageManifest(
        name=args.name or "my-package",
        version=args.version or "1.0.0",
        description="Package description",
        license="Apache-2.0",
        homepage="https://example.com",
    )

    manifest.save(output_file)
    print(f"Created manifest: {output_file}")
    return 0


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="VFX Bootstrap Packager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # Package command
    pkg_parser = subparsers.add_parser("package", help="Create package")
    pkg_parser.add_argument("manifest", type=Path, help="Package manifest file")
    pkg_parser.add_argument("--source", "-s", type=Path, required=True, help="Source directory")
    pkg_parser.add_argument("--output", "-o", type=Path, default=Path("."), help="Output directory")
    pkg_parser.add_argument(
        "--format",
        "-f",
        nargs="+",
        default=["tarball"],
        choices=list(EXPORTERS.keys()) + ["all"],
        help="Output format(s)",
    )
    pkg_parser.add_argument("--components", "-c", nargs="*", help="Components to include")
    pkg_parser.set_defaults(func=cmd_package)

    # Validate command
    val_parser = subparsers.add_parser("validate", help="Validate source against manifest")
    val_parser.add_argument("manifest", type=Path, help="Package manifest file")
    val_parser.add_argument("--source", "-s", type=Path, required=True, help="Source directory")
    val_parser.add_argument("--components", "-c", nargs="*", help="Components to validate")
    val_parser.set_defaults(func=cmd_validate)

    # Show command
    show_parser = subparsers.add_parser("show", help="Show manifest details")
    show_parser.add_argument("manifest", type=Path, help="Package manifest file")
    show_parser.set_defaults(func=cmd_show)

    # Init command
    init_parser = subparsers.add_parser("init", help="Create template manifest")
    init_parser.add_argument(
        "--output", "-o", type=Path, default=Path("package.yaml"), help="Output file"
    )
    init_parser.add_argument("--name", help="Package name")
    init_parser.add_argument("--version", help="Package version")
    init_parser.add_argument("--force", "-f", action="store_true", help="Overwrite existing file")
    init_parser.set_defaults(func=cmd_init)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
