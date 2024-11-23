#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

CONDA_ROOT="$HOME/miniconda3"
CONDA_ENV_DIR="$HOME/.conda/envs"
LOCAL_PKG_DIR="$HOME/Development/packages"
CONDA_CONFIG="$HOME/.condarc"

setup_conda() {
    if [ ! -d "$CONDA_ROOT" ]; then
        log "INFO" "Installing Miniconda..."
        local miniconda_installer="Miniconda3-latest-Linux-x86_64.sh"
        wget https://repo.anaconda.com/miniconda/$miniconda_installer -O /tmp/$miniconda_installer
        bash /tmp/$miniconda_installer -b -p "$CONDA_ROOT"
        rm /tmp/$miniconda_installer
        
        # Initialize conda for shell interaction
        "$CONDA_ROOT/bin/conda" init bash
        "$CONDA_ROOT/bin/conda" init zsh
    else
        log "INFO" "Miniconda already installed, updating..."
        source "$CONDA_ROOT/etc/profile.d/conda.sh"
        conda update -n base -c defaults conda -y
    fi
    
    # Setup conda configuration
    setup_conda_config
    
    # Create development environments
    setup_dev_environments
    
    # Setup local package structure
    setup_local_packages
}

setup_conda_config() {
    log "INFO" "Configuring Conda..."
    
    # Create .condarc with corrected settings
    cat > "$CONDA_CONFIG" << EOF
# Conda Configuration
channels:
  - conda-forge
  - defaults

# Channel priority
channel_priority: strict

# Environment locations
envs_dirs:
  - $CONDA_ENV_DIR

# Local package repository
custom_channels:
  local: file://$LOCAL_PKG_DIR

# Solver settings (using single key)
solver: libmamba

# Performance optimization
auto_activate_base: false
always_yes: false
notify_outdated_conda: true

# Development settings
pip_interop_enabled: true
use_pip: true
add_pip_as_python_dependency: true

# Build settings
conda-build:
  root-dir: $LOCAL_PKG_DIR/build
  output_folder: $LOCAL_PKG_DIR/dist
  include_recipe: true
  filename_hashing: true
  verify: true
  debug: false
  error_overlinking: true
  
# Advanced settings
remote_connect_timeout_secs: 9.15
remote_max_retries: 3
remote_read_timeout_secs: 60.0
EOF
    
    log "INFO" "Conda configuration created at $CONDA_CONFIG"
}


setup_dev_environments() {
    log "INFO" "Setting up development environments..."
    source "$CONDA_ROOT/etc/profile.d/conda.sh"
    
    # Create C++ development environment
    conda create -n cpp -y \
        compilers \
        cmake \
        make \
        ninja \
        gdb \
        boost-cpp \
        eigen \
        fmt \
        spdlog \
        nlohmann_json \
        catch2 \
        benchmark \
        doxygen \
        ccache
    
    # Create Python development environment
    conda create -n python -y \
        python=3.11 \
        pip \
        ipython \
        jupyter \
        numpy \
        pandas \
        scipy \
        matplotlib \
        seaborn \
        scikit-learn \
        pytest \
        black \
        flake8 \
        mypy \
        sphinx \
        conda-build \
        conda-verify
    
    # Create ML development environment
    conda create -n ml -y \
        python=3.11 \
        pip \
        tensorflow \
        pytorch \
        torchvision \
        cudatoolkit \
        cupy \
        numpy \
        pandas \
        scikit-learn \
        matplotlib \
        seaborn \
        jupyter \
        tensorboard
    
    log "INFO" "Development environments created successfully"
}

setup_local_packages() {
    log "INFO" "Setting up local package development structure..."
    
    # Create directory structure for local packages
    mkdir -p "$LOCAL_PKG_DIR"/{src,dist,build,docs}
    mkdir -p "$LOCAL_PKG_DIR/templates/cpp"
    mkdir -p "$LOCAL_PKG_DIR/templates/python"
    
    # Create C++ package template
    cat > "$LOCAL_PKG_DIR/templates/cpp/meta.yaml" << 'EOF'
package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  path: .

build:
  number: 0
  script_env:
    - CC
    - CXX

requirements:
  build:
    - {{ compiler('cxx') }}
    - cmake
    - make
    - ninja
  host:
    - boost-cpp
    - eigen
  run:
    - boost-cpp
    - eigen

test:
  commands:
    - test -f $PREFIX/lib/lib{{ name }}.so  # [linux]
    - test -f $PREFIX/include/{{ name }}/{{ name }}.hpp  # [unix]

about:
  home: https://github.com/username/{{ name }}
  license: MIT
  summary: Package description
EOF
    
    # Create Python package template
    cat > "$LOCAL_PKG_DIR/templates/python/meta.yaml" << 'EOF'
package:
  name: {{ name|lower }}
  version: {{ version }}

source:
  path: .

build:
  number: 0
  script: {{ PYTHON }} -m pip install . -vv
  noarch: python

requirements:
  host:
    - python
    - pip
    - setuptools
    - wheel
  run:
    - python
    - numpy
    - pandas

test:
  imports:
    - {{ name }}
  requires:
    - pytest
  commands:
    - pytest tests

about:
  home: https://github.com/username/{{ name }}
  license: MIT
  summary: Package description
EOF
    
    # Create package creation helper script
    cat > "$LOCAL_PKG_DIR/create_package.sh" << 'EOF'
#!/bin/bash

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <type> <name> [version]"
    echo "type: cpp or python"
    echo "name: package name"
    echo "version: package version (default: 0.1.0)"
    exit 1
fi

TYPE=$1
NAME=$2
VERSION=${3:-0.1.0}
PACKAGE_DIR="$LOCAL_PKG_DIR/src/$NAME"

case $TYPE in
    "cpp")
        mkdir -p "$PACKAGE_DIR"/{include,src,tests,cmake}
        cp "$LOCAL_PKG_DIR/templates/cpp/meta.yaml" "$PACKAGE_DIR/meta.yaml"
        # Add CMakeLists.txt and other C++ specific files
        ;;
    "python")
        mkdir -p "$PACKAGE_DIR"/{src,tests,docs}
        cp "$LOCAL_PKG_DIR/templates/python/meta.yaml" "$PACKAGE_DIR/meta.yaml"
        # Add setup.py and other Python specific files
        ;;
    *)
        echo "Invalid package type. Use 'cpp' or 'python'"
        exit 1
        ;;
esac

# Update template variables
sed -i "s/{{ name }}/$NAME/g" "$PACKAGE_DIR/meta.yaml"
sed -i "s/{{ version }}/$VERSION/g" "$PACKAGE_DIR/meta.yaml"

echo "Package structure created at $PACKAGE_DIR"
EOF
    
    chmod +x "$LOCAL_PKG_DIR/create_package.sh"
    
    log "INFO" "Local package development structure created successfully"
}

# Function to build a local package
build_local_package() {
    local package_dir=$1
    local package_type=$2
    
    if [ ! -d "$package_dir" ]; then
        log "ERROR" "Package directory does not exist: $package_dir"
        return 1
    fi
    
    source "$CONDA_ROOT/etc/profile.d/conda.sh"
    
    case $package_type in
        "cpp")
            conda activate cpp
            cd "$package_dir"
            conda build .
            ;;
        "python")
            conda activate python
            cd "$package_dir"
            conda build .
            ;;
        *)
            log "ERROR" "Invalid package type. Use 'cpp' or 'python'"
            return 1
            ;;
    esac
    
    log "INFO" "Package built successfully"
}

# Function to install a local package
install_local_package() {
    local package_name=$1
    local package_version=$2
    local environment=$3
    
    source "$CONDA_ROOT/etc/profile.d/conda.sh"
    conda activate "$environment"
    
    conda install --use-local "$package_name=$package_version"
    
    log "INFO" "Package $package_name=$package_version installed in environment $environment"
}

# Function to update conda environments
update_environments() {
    source "$CONDA_ROOT/etc/profile.d/conda.sh"
    
    log "INFO" "Updating conda environments..."
    
    # Update base environment
    conda update -n base -c defaults conda -y
    
    # Update each environment
    for env in cpp python ml; do
        if conda env list | grep -q "^$env "; then
            log "INFO" "Updating $env environment..."
            conda activate $env
            conda update --all -y
            conda deactivate
        fi
    done
    
    log "INFO" "All environments updated successfully"
}