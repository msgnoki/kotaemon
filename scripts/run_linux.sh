#!/bin/bash

# Function to ensure no whitespace in the current path
check_path_for_spaces() {
    if [[ $PWD =~ \  ]]; then
        echo "The current workdir has whitespace which can lead to unintended behaviour. Please modify your path and retry."
        exit 1
    fi
}

# Function to initialize global constants
initialize_constants() {
    install_dir="$(pwd)/install_dir"
    conda_root="${install_dir}/conda"
    env_dir="${install_dir}/env"
    python_version="3.10"

    pdf_js_version="4.0.379"
    pdf_js_dist_name="pdfjs-${pdf_js_version}-dist"
    pdf_js_dist_url="https://github.com/mozilla/pdf.js/releases/download/v${pdf_js_version}/${pdf_js_dist_name}.zip"
    target_pdf_js_dir="$(pwd)/libs/ktem/ktem/assets/prebuilt/${pdf_js_dist_name}"
}

# Function to display highlighted messages
print_highlight() {
    echo ""
    echo "******************************************************"
    echo "$1"
    echo "******************************************************"
    echo ""
}

# Function to install Miniconda
install_miniconda() {
    local sys_arch=$(uname -m)
    case "$sys_arch" in
        x86_64* | amd64*) sys_arch="x86_64" ;;
        arm64* | aarch64*) sys_arch="aarch64" ;;
        *) echo "Unknown architecture: $sys_arch. This script supports only x86_64 or arm64."; exit 1 ;;
    esac

    if ! "${conda_root}/bin/conda" --version &>/dev/null; then
        local miniconda_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${sys_arch}.sh"
        echo "Downloading Miniconda from $miniconda_url"
        mkdir -p "$install_dir"
        curl -L "$miniconda_url" -o "$install_dir/miniconda_installer.sh"
        chmod +x "$install_dir/miniconda_installer.sh"
        echo "Installing Miniconda to $conda_root"
        bash "$install_dir/miniconda_installer.sh" -b -p "$conda_root"
        rm -f "$install_dir/miniconda_installer.sh"
    fi

    echo "Miniconda is installed at $conda_root"
    "$conda_root/bin/conda" --version || { echo "Conda not found. Exiting."; exit 1; }
}

# Function to create a Conda environment
create_conda_env() {
    if [ ! -d "$env_dir" ]; then
        echo "Creating Conda environment with Python $python_version"
        "${conda_root}/bin/conda" create -y -k --prefix "$env_dir" python="$python_version" || {
            echo "Failed to create Conda environment. Deleting $env_dir and exiting."
            rm -rf "$env_dir"
            exit 1
        }
    else
        echo "Conda environment already exists at $env_dir"
    fi
}

# Function to activate the Conda environment
activate_conda_env() {
    source "$conda_root/etc/profile.d/conda.sh"
    conda activate "$env_dir" || {
        echo "Failed to activate Conda environment. Please delete $env_dir and rerun the installer."
        exit 1
    }
    echo "Activated Conda environment at $CONDA_PREFIX"
}

# Function to deactivate the Conda environment
deactivate_conda_env() {
    if [ "$CONDA_PREFIX" == "$env_dir" ]; then
        conda deactivate
        echo "Deactivated Conda environment at $env_dir"
    fi
}

# Function to install dependencies
install_dependencies() {
    local retries=3
    local requirement_file="$(pwd)/requirements.txt"

    if [ -f "$requirement_file" ]; then
        echo "Installing dependencies from $requirement_file"
        for attempt in $(seq 1 $retries); do
            python -m pip install -r "$requirement_file" && break || {
                echo "Installation failed. Retrying ($attempt/$retries)..."
            }
        done
    else
        echo "Installing dependencies manually"
        for attempt in $(seq 1 $retries); do
            python -m pip install -e ./libs/kotaemon \
                && python -m pip install -e ./libs/ktem \
                && python -m pip install --no-deps -e . \
                && break || {
                echo "Installation failed. Retrying ($attempt/$retries)..."
            }
        done
    fi

    if ! pip list | grep -q "kotaemon"; then
        echo "Failed to install dependencies. Exiting."
        deactivate_conda_env
        exit 1
    fi

    conda clean --all -y
    python -m pip cache purge
}

# Function to install Ollama
install_ollama() {
    if command -v ollama &>/dev/null; then
        echo "Ollama is already installed."
    else
        echo "Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh || {
            echo "Failed to install Ollama. Check your connection and try again."
            exit 1
        }
        echo "Ollama installation complete."
    fi
}

# Function to download and unzip files
download_and_unzip() {
    local url="$1"
    local dest_dir="$2"
    local retries=3
    local zip_file="$dest_dir/download.zip"

    if [ -d "$dest_dir" ]; then
        echo "Directory $dest_dir already exists. Skipping download."
        return
    fi

    mkdir -p "$dest_dir"

    echo "Downloading $url to $zip_file"
    for attempt in $(seq 1 $retries); do
        curl -L -o "$zip_file" "$url" && break || {
            echo "Download failed. Retrying ($attempt/$retries)..."
        }
    done

    if [ ! -s "$zip_file" ]; then
        echo "Download failed after $retries attempts. Exiting."
        exit 1
    fi

    echo "Unzipping $zip_file to $dest_dir"
    unzip -o "$zip_file" -d "$dest_dir" || { echo "Failed to unzip. Exiting."; exit 1; }
    rm -f "$zip_file"
}

# Function to set up a local model
setup_local_model() {
    echo "Setting up local model..."
    python "$(pwd)/scripts/serve_local.py"
}

# Function to launch the web UI
launch_ui() {
    local pdfjs_prebuilt_dir="$1"
    echo "Launching Kotaemon web UI..."
    PDFJS_PREBUILT_DIR="$pdfjs_prebuilt_dir" python "$(pwd)/app.py" || {
        echo "Failed to launch the web UI. Exiting."
        exit 1
    }
}

# Main script execution
check_path_for_spaces
initialize_constants

print_highlight "Installing Miniconda"
install_miniconda

print_highlight "Creating Conda environment"
create_conda_env
activate_conda_env

print_highlight "Installing Ollama"
install_ollama

print_highlight "Installing dependencies"
install_dependencies

print_highlight "Downloading and setting up PDF.js"
download_and_unzip "$pdf_js_dist_url" "$target_pdf_js_dir"

print_highlight "Setting up local model"
setup_local_model

print_highlight "Launching web UI"
launch_ui "$target_pdf_js_dir"

deactivate_conda_env
read -p "Press enter to exit"
