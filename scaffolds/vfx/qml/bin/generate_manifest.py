import os
import json
import glob
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: generate_manifest.py <output_file> [exe_path]")
        sys.exit(1)
        
    output_file = sys.argv[1]
    exe_path = sys.argv[2] if len(sys.argv) > 2 else os.path.abspath('bazel-bin/${PROJECT_NAME}.exe')
    
    conda = os.environ.get('CONDA_PREFIX', '')
    if not conda or 'gemini-env' in conda:
        conda = os.path.join(os.environ['USERPROFILE'], "miniconda3", "envs", "manifold")
        
    bin_dir = os.path.join(conda, 'Library', 'bin')
    qt_plugins = os.path.join(conda, 'Library', 'lib', 'qt6', 'plugins')
    qt_qml = os.path.join(conda, 'Library', 'lib', 'qt6', 'qml')
    
    # Start with the main executable
    files = [{
        'path': '${PROJECT_NAME}.exe',
        'source': os.path.abspath(exe_path)
    }]
    
    patterns = [
        'usd_*.dll', 
        'Qt6Core.dll', 
        'Qt6Gui.dll', 
        'Qt6Qml.dll', 
        'Qt6Quick.dll', 
        'Qt6Widgets.dll', 
        'tbb*.dll', 
        'Imath*.dll', 
        'OpenEXR*.dll'
    ]
    
    if os.path.exists(bin_dir):
        for pattern in patterns:
            found = glob.glob(os.path.join(bin_dir, pattern))
            for f in found:
                files.append({
                    'path': os.path.basename(f),
                    'source': os.path.abspath(f)
                })
    
    # Bundle platforms (essential for Windows launch)
    platforms_dir = os.path.join(qt_plugins, 'platforms')
    if os.path.exists(platforms_dir):
        found = glob.glob(os.path.join(platforms_dir, '*.dll'))
        for f in found:
            files.append({
                'path': f'platforms/{os.path.basename(f)}',
                'source': os.path.abspath(f)
            })
            
    # Bundle specific QML modules we use
    qml_modules = ['QtQuick', 'QtQuick.Controls', 'QtQuick.Layouts', 'QtQuick.Window']
    for module in qml_modules:
        module_path = module.replace('.', '/')
        src_module_dir = os.path.join(qt_qml, module_path)
        if os.path.exists(src_module_dir):
            for root, dirs, filenames in os.walk(src_module_dir):
                for filename in filenames:
                    if filename.endswith(('.dll', '.qml', 'qmldir')):
                        abs_src = os.path.join(root, filename)
                        rel_path = os.path.relpath(abs_src, qt_qml)
                        files.append({
                            'path': f'qml/{rel_path}',
                            'source': os.path.abspath(abs_src)
                        })
    
    data = {
        'product': {
            'name': '${PROJECT_NAME}',
            'version': '1.0.0',
            'description': 'VFX Platform Application',
            'manufacturer': 'Development Environment',
            'root_path': os.path.abspath('bazel-bin')
        },
        'files': files
    }
    
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Manifest generated: {output_file} ({len(files)} files)")

if __name__ == '__main__':
    main()
