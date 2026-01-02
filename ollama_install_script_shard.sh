#!/bin/bash
set -e  # Exit on error

# Install system dependencies
sudo apt update && \
sudo apt install -y pciutils nano htop nvtop python3 python3-pip curl jq

# Install Python dependencies
pip3 install huggingface_hub requests

# Install Ollama
curl https://ollama.ai/install.sh | sh

# Configure Ollama
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/environment.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=-1"
EOF

systemctl daemon-reload
systemctl restart ollama
sleep 3

# ============================================
# Define ollama_hf_pull function FIRST
# ============================================
ollama_hf_pull() {
    local hf_model="$1"  # Format: unsloth/GLM-4.5-Air-GGUF:Q4_K_M
    local model_alias="$2"  # Optional: custom name for ollama
    
    # Parse repo and quantization
    local repo_id=$(echo "$hf_model" | cut -d':' -f1)
    local quant=$(echo "$hf_model" | cut -d':' -f2)
    
    if [ -z "$quant" ] || [ "$quant" = "$repo_id" ]; then
        quant=""
    fi
    
    # Generate safe model name
    local safe_name=$(echo "${model_alias:-$repo_id}" | sed 's|.*/||' | tr '[:upper:]' '[:lower:]' | sed 's/-gguf//')
    
    echo "========================================"
    echo "Repository: $repo_id"
    echo "Quantization: ${quant:-auto-detect}"
    echo "Model name: $safe_name"
    echo "========================================"
    
    # Python script to detect sharding and handle download
    python3 - "$repo_id" "$quant" "$safe_name" << 'PYSCRIPT'
import sys
import os
import subprocess
from pathlib import Path
from huggingface_hub import list_repo_files, hf_hub_download

def main():
    repo_id = sys.argv[1]
    quant = sys.argv[2] if len(sys.argv) > 2 else ""
    model_name = sys.argv[3] if len(sys.argv) > 3 else repo_id.split('/')[-1].lower().replace('-gguf', '')
    
    download_dir = Path(f"/tmp/hf_{model_name}")
    merged_path = Path(f"/tmp/{model_name}.gguf")
    modelfile_path = Path(f"/tmp/Modelfile_{model_name}")
    
    download_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"\n[1/5] Scanning repository: {repo_id}")
    
    try:
        # List all files in repo
        all_files = list_repo_files(repo_id)
        gguf_files = [f for f in all_files if f.endswith('.gguf')]
        
        if not gguf_files:
            print("Error: No GGUF files found in repository")
            sys.exit(1)
        
        print(f"      Found {len(gguf_files)} total GGUF file(s)")
        
        # Filter by quantization if specified
        if quant:
            filtered = [f for f in gguf_files if quant.lower() in f.lower()]
            if filtered:
                gguf_files = filtered
                print(f"      Filtered to {len(gguf_files)} file(s) matching '{quant}'")
        
        # Sort files for proper shard order
        gguf_files = sorted(gguf_files)
        
        # Detect if sharded
        print(f"\n[2/5] Detecting model structure...")
        
        is_sharded = False
        shard_pattern_detected = False
        
        # Check for shard patterns
        shard_indicators = ['-of-', '.part', '-split-']
        for indicator in shard_indicators:
            if any(indicator in f for f in gguf_files):
                shard_pattern_detected = True
                break
        
        # Count files that look like shards
        if shard_pattern_detected and len(gguf_files) > 1:
            is_sharded = True
            print(f"      ✓ SHARDED MODEL DETECTED ({len(gguf_files)} parts)")
            for f in gguf_files:
                print(f"        - {f}")
        elif len(gguf_files) == 1:
            is_sharded = False
            print(f"      ✓ SINGLE FILE MODEL DETECTED")
            print(f"        - {gguf_files[0]}")
        else:
            # Multiple files but no shard pattern - pick the best one
            is_sharded = False
            if quant:
                best_match = [f for f in gguf_files if quant.upper() in f.upper()]
                if best_match:
                    gguf_files = [best_match[0]]
            else:
                gguf_files = [gguf_files[0]]
            print(f"      ✓ SINGLE FILE MODEL (selected from multiple options)")
            print(f"        - {gguf_files[0]}")
        
        # Handle based on detection
        if is_sharded:
            print(f"\n[3/5] Downloading {len(gguf_files)} shard files...")
            
            downloaded_paths = []
            total_download_size = 0
            
            for i, gguf_file in enumerate(gguf_files):
                print(f"      [{i+1}/{len(gguf_files)}] {gguf_file}")
                
                local_path = hf_hub_download(
                    repo_id=repo_id,
                    filename=gguf_file,
                    local_dir=str(download_dir),
                    local_dir_use_symlinks=False
                )
                
                actual_path = download_dir / gguf_file
                if actual_path.exists():
                    downloaded_paths.append(actual_path)
                else:
                    downloaded_paths.append(Path(local_path))
                
                file_size = downloaded_paths[-1].stat().st_size
                total_download_size += file_size
                print(f"             Downloaded: {file_size / (1024**3):.2f} GB")
            
            downloaded_paths = sorted(downloaded_paths, key=lambda p: str(p))
            
            print(f"\n[4/5] Merging {len(downloaded_paths)} shards...")
            print(f"      Total size: {total_download_size / (1024**3):.2f} GB")
            print(f"      Output: {merged_path}")
            
            with open(merged_path, 'wb') as outfile:
                for i, shard_path in enumerate(downloaded_paths):
                    print(f"      [{i+1}/{len(downloaded_paths)}] Merging {shard_path.name}...")
                    
                    with open(shard_path, 'rb') as infile:
                        while chunk := infile.read(100 * 1024 * 1024):
                            outfile.write(chunk)
            
            print(f"      Cleaning up shard files...")
            for shard_path in downloaded_paths:
                shard_path.unlink()
            
            try:
                for dirpath in sorted(download_dir.rglob('*'), reverse=True):
                    if dirpath.is_dir():
                        dirpath.rmdir()
                download_dir.rmdir()
            except:
                pass
            
            print(f"      ✓ Merge complete!")
            
        else:
            print(f"\n[3/5] Downloading single file...")
            
            gguf_file = gguf_files[0]
            print(f"      {gguf_file}")
            
            local_path = hf_hub_download(
                repo_id=repo_id,
                filename=gguf_file,
                local_dir=str(download_dir),
                local_dir_use_symlinks=False
            )
            
            actual_path = download_dir / gguf_file
            source_path = actual_path if actual_path.exists() else Path(local_path)
            
            print(f"\n[4/5] Moving to final location...")
            
            import shutil
            shutil.move(str(source_path), str(merged_path))
            
            try:
                for dirpath in sorted(download_dir.rglob('*'), reverse=True):
                    if dirpath.is_dir():
                        dirpath.rmdir()
                download_dir.rmdir()
            except:
                pass
            
            print(f"      ✓ Download complete!")
        
        # Verify final file
        if not merged_path.exists():
            print("Error: Final model file not found!")
            sys.exit(1)
        
        final_size = merged_path.stat().st_size
        print(f"\n[5/5] Creating Ollama model...")
        print(f"      Model file: {merged_path}")
        print(f"      Size: {final_size / (1024**3):.2f} GB")
        
        # Create Modelfile
        modelfile_content = f'''FROM {merged_path}

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER num_ctx 4096
'''
        
        with open(modelfile_path, 'w') as f:
            f.write(modelfile_content)
        
        print(f"      Running: ollama create {model_name}")
        result = subprocess.run(
            ['ollama', 'create', model_name, '-f', str(modelfile_path)],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print(f"      Error creating model: {result.stderr}")
            sys.exit(1)
        
        print(f"\n========================================")
        print(f"✓ SUCCESS!")
        print(f"========================================")
        print(f"Model '{model_name}' is ready to use!")
        print(f"")
        print(f"Run with:")
        print(f"  ollama run {model_name}")
        print(f"")
        
        subprocess.run(['ollama', 'list'])
        
        print(f"\n[Optional] GGUF file stored at: {merged_path}")
        print(f"           Size: {final_size / (1024**3):.2f} GB")
        print(f"           Delete with: rm {merged_path}")
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
PYSCRIPT

    local result=$?
    if [ $result -ne 0 ]; then
        echo "Failed to download/create model"
        return 1
    fi
    
    return 0
}

# Export function for use in interactive shell
export -f ollama_hf_pull

# ============================================
# NOW call the function AFTER it's defined
# ============================================
ollama_hf_pull "unsloth/GLM-4.5-Air-GGUF:Q4_K_M" "GLM-4.5-Air-GGUF:Q4_K_M"
ollama_hf_pull "gpt-oss:120b" "gpt-oss:120b"

echo ""
echo "========================================"
echo "Setup complete!"
echo "========================================"
echo ""
echo "Usage:"
echo ""
echo "  ollama_hf_pull 'username/repo-GGUF:QUANTIZATION' [optional-alias]"
echo ""
echo "Examples:"
echo ""
echo "  # Sharded model (auto-detected and merged):"
echo "  ollama_hf_pull 'unsloth/GLM-4.5-Air-GGUF:Q4_K_M'"
echo ""
echo "  # Single file model:"
echo "  ollama_hf_pull 'TheBloke/Llama-2-7B-GGUF:Q4_K_M' 'llama2-7b'"
echo ""
