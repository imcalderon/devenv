"""
Post-install fixup for USD plugInfo.json files on Windows.

Called from bld.bat after DLLs have been moved from Library/lib/ to Library/bin/.
Updates LibraryPath entries in all plugInfo.json files to point to bin/ instead
of lib/, so the USD plugin system loads DLLs from the correct location.

Usage: python fix_pluginfo.py <LIBRARY_PREFIX>
"""
import sys
import os
import json
import glob

library_prefix = sys.argv[1]
lib_usd = os.path.join(library_prefix, 'lib', 'usd')
plugin_usd = os.path.join(library_prefix, 'plugin', 'usd')
bin_dir = os.path.join(library_prefix, 'bin')

if not os.path.isdir(lib_usd):
    print(f"WARNING: {lib_usd} not found, skipping plugInfo.json fixup")
    sys.exit(0)

fixed = 0
skipped = 0

for search_dir in [lib_usd, plugin_usd]:
    if not os.path.isdir(search_dir):
        continue
    for path in glob.glob(os.path.join(search_dir, '**', 'plugInfo.json'), recursive=True):
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        if not content.strip():
            continue  # empty file — schema-only plugin, no DLL reference

        try:
            data = json.loads(content)
        except json.JSONDecodeError:
            print(f"WARNING: invalid JSON in {path}, skipping")
            skipped += 1
            continue

        plugins = data.get('Plugins', [])
        if not plugins:
            continue

        resources_dir = os.path.dirname(path)
        changed = False

        for plugin in plugins:
            lib_path = plugin.get('LibraryPath', '')
            if not lib_path or not lib_path.endswith('.dll'):
                continue

            root_rel = plugin.get('Root', '.')
            plugin_root = os.path.normpath(os.path.join(resources_dir, root_rel))
            abs_lib = os.path.normpath(os.path.join(plugin_root, lib_path))
            dll_name = os.path.basename(abs_lib)

            bin_dll = os.path.join(bin_dir, dll_name)
            if not os.path.exists(bin_dll):
                # Check if the DLL is next to the plugInfo.json (plugin-dir layout)
                local_dll = os.path.join(os.path.dirname(path), '..', dll_name)
                local_dll = os.path.normpath(local_dll)
                if os.path.exists(local_dll):
                    continue  # DLL is local to the plugin dir, leave as-is
                print(f"WARNING: {dll_name} not found in bin/ or plugin dir, skipping")
                skipped += 1
                continue

            new_rel = os.path.relpath(bin_dll, plugin_root).replace('\\', '/')
            if new_rel == lib_path:
                continue

            print(f"  {plugin.get('Name', dll_name)}: {lib_path!r} -> {new_rel!r}")
            plugin['LibraryPath'] = new_rel
            changed = True

        if changed:
            with open(path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=4)
            fixed += 1

print(f"plugInfo.json fixup: {fixed} files updated, {skipped} skipped")
