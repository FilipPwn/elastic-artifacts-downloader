#!/bin/bash

# Base URL for Elastic downloads
base_url="https://artifacts.elastic.co/downloads"

# Log file
log_file="/var/log/elastic-artifacts-downloader.log"

# Function to log messages with a timestamp
log_with_timestamp() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    message="$1"
    log_entry="{\"ts\":\"$timestamp\",\"message\":\"$message\"}"
    echo "$log_entry" | tee -a $log_file
}

# Function to fetch the latest version
get_latest_version() {
    curl -s 'https://www.elastic.co/guide/en/elasticsearch/reference/current/es-release-notes.html' | \
    grep -oP 'release-notes-\K[\d\.]+' | \
    head -n 1 | \
    sed 's/.$//'
}

# Check version argument
if [ $# -eq 1 ]; then
    version=$1
    log_with_timestamp "Using provided version: $version"
else
    version=$(get_latest_version)
    log_with_timestamp "Latest version is: $version"
fi

# Declare products and their types
declare -A products=(
    ["apm-server"]="apm-server"
    ["auditbeat"]="beats/auditbeat"
    ["elastic-agent"]="beats/elastic-agent"
    ["filebeat"]="beats/filebeat"
    ["heartbeat"]="beats/heartbeat"
    ["metricbeat"]="beats/metricbeat"
    ["osquerybeat"]="beats/osquerybeat"
    ["packetbeat"]="beats/packetbeat"
    ["cloudbeat"]="cloudbeat"
    ["endpoint-security"]="endpoint-dev"
    ["fleet-server"]="fleet-server"
    ["winlogbeat"]="beats/winlogbeat"
    ["pf-host-agent"]="prodfiler"
    ["pf-elastic-collector"]="prodfiler"
    ["pf-elastic-symbolizer"]="prodfiler"
)

local_repo_path="/var/www/repo/elastic-artifacts/"
linux_arch="linux-x86_64"
windows_arch="windows-x86_64"
package_types=("tar.gz" "zip")

# Function to download and organize files for a specific version
download_and_organize_files() {
    local product=$1
    local product_type=$2
    local version=$3
    local arch=$4
    local package_type=$5
    local url="${base_url}/${product_type}/${product}-${version}-${arch}.${package_type}"
    local local_dir="${local_repo_path}/${product_type}"
    local file_path="${local_dir}/${product}-${version}-${arch}.${package_type}"

    mkdir -p "${local_dir}"
    if [ ! -s "$file_path" ]; then
        log_with_timestamp "Downloading ${product} version ${version} for ${arch} from $url"
        curl -o "$file_path" "$url"
        curl -o "${file_path}.sha512" "${url}.sha512"
        curl -o "${file_path}.asc" "${url}.asc"

        # Check if the downloaded file is not empty
        if [ ! -s "$file_path" ]; then
            log_with_timestamp "Downloaded file $file_path is empty, download failed. Removing files."
            rm -f "$file_path" "${file_path}.sha512" "${file_path}.asc"
            return 1
        fi

        local sha512sum_local
        sha512sum_local=$(sha512sum "$file_path" | awk '{ print $1 }')
        local sha512sum_expected
        sha512sum_expected=$(cat "${file_path}.sha512" | awk '{ print $1 }')

        if [ "$sha512sum_local" == "$sha512sum_expected" ]; then
            log_with_timestamp "SHA512 checksum verification passed for ${file_path}"
        else
            log_with_timestamp "SHA512 checksum verification failed for ${file_path} - Expected: $sha512sum_expected - Got: $sha512sum_local. Removing files."
            rm -f "$file_path" "${file_path}.sha512" "${file_path}.asc"
            return 1
        fi
    else
        log_with_timestamp "File $file_path already exists, skipping download."
    fi
}

# Function to process versions for a product
process_product_versions() {
    local product=$1
    local product_type=$2
    local start_major=$3
    local start_minor=$4
    local start_patch=$5
    local major=$start_major
    local minor=$start_minor
    local patch=$start_patch

    while true; do
        version="${major}.${minor}.${patch}"
        log_with_timestamp "Checking version ${version} for ${product}"

        # Try downloading for both architectures
        local linux_downloaded=false
        local windows_downloaded=false
        
        # Try Linux version first
        if curl --head --silent --fail "${base_url}/${product_type}/${product}-${version}-${linux_arch}.tar.gz" > /dev/null; then
            if download_and_organize_files "$product" "$product_type" "$version" "$linux_arch" "tar.gz"; then
                linux_downloaded=true
                log_with_timestamp "Successfully downloaded Linux version for ${product} ${version}"
            else
                log_with_timestamp "Failed to download Linux version for ${product} ${version}"
            fi
        else
            log_with_timestamp "Linux version not available for ${product} ${version}"
        fi
        
        # Try Windows version
        if curl --head --silent --fail "${base_url}/${product_type}/${product}-${version}-${windows_arch}.zip" > /dev/null; then
            if download_and_organize_files "$product" "$product_type" "$version" "$windows_arch" "zip"; then
                windows_downloaded=true
                log_with_timestamp "Successfully downloaded Windows version for ${product} ${version}"
            else
                log_with_timestamp "Failed to download Windows version for ${product} ${version}"
            fi
        else
            log_with_timestamp "Windows version not available for ${product} ${version}"
        fi
        
        # Log summary for this version
        if [ "$linux_downloaded" = true ] || [ "$windows_downloaded" = true ]; then
            log_with_timestamp "Version ${version} for ${product}: Linux: $([ "$linux_downloaded" = true ] && echo "✓" || echo "✗"), Windows: $([ "$windows_downloaded" = true ] && echo "✓" || echo "✗")"
        fi

        # Check if next version exists
        ((patch++))
        next_version="${major}.${minor}.${patch}"
        
        # Check if next version exists for either Linux or Windows
        version_exists=false
        if curl --head --silent --fail "${base_url}/${product_type}/${product}-${next_version}-${linux_arch}.tar.gz" > /dev/null; then
            version_exists=true
        fi
        if curl --head --silent --fail "${base_url}/${product_type}/${product}-${next_version}-${windows_arch}.zip" > /dev/null; then
            version_exists=true
        fi
        
        if ! $version_exists; then
            ((minor++))
            patch=0
            next_version="${major}.${minor}.${patch}"
            
            # Check if next version exists for either Linux or Windows
            version_exists=false
            if curl --head --silent --fail "${base_url}/${product_type}/${product}-${next_version}-${linux_arch}.tar.gz" > /dev/null; then
                version_exists=true
            fi
            if curl --head --silent --fail "${base_url}/${product_type}/${product}-${next_version}-${windows_arch}.zip" > /dev/null; then
                version_exists=true
            fi
            
            if ! $version_exists; then
                if [ "$major" -eq "$start_major" ]; then
                    # If we're in the first major version, move to the next major
                    major=$((major + 1))
                    minor=0
                    patch=0
                    next_version="${major}.${minor}.${patch}"
                    
                    # Check if next version exists for either Linux or Windows
                    version_exists=false
                    if curl --head --silent --fail "${base_url}/${product_type}/${product}-${next_version}-${linux_arch}.tar.gz" > /dev/null; then
                        version_exists=true
                    fi
                    if curl --head --silent --fail "${base_url}/${product_type}/${product}-${next_version}-${windows_arch}.zip" > /dev/null; then
                        version_exists=true
                    fi
                    
                    if ! $version_exists; then
                        log_with_timestamp "No more versions found for ${product}, moving to next product."
                        break
                    fi
                else
                    log_with_timestamp "No more versions found for ${product}, moving to next product."
                    break
                fi
            fi
        fi
    done
}

# Process all products for both version ranges
for product in "${!products[@]}"; do
    log_with_timestamp "Processing product: ${product}"
    # Process 8.15.0+ versions
    process_product_versions "$product" "${products[$product]}" 8 15 0
    # Process 9.0.0+ versions
    process_product_versions "$product" "${products[$product]}" 9 0 0
done

log_with_timestamp "Download endpoint artifacts"

download_artifacts() {
    local version=$1
    local artifact_url="https://artifacts.security.elastic.co/downloads/endpoint/manifest/artifacts-${version}.zip"
    local local_artifact_path="/var/www/repo/elastic-artifacts/downloads/endpoint/manifest/artifacts-${version}.zip"

    # Check if URL exists
    if curl --head --silent --fail "$artifact_url" > /dev/null; then
        log_with_timestamp "Downloading endpoint artifacts for version ${version}..."
        wget -O "$local_artifact_path" "$artifact_url"
        log_with_timestamp "Processing downloaded artifacts manifest for version ${version}..."
        zcat -q "$local_artifact_path" | jq -r '.artifacts | to_entries[] | .value.relative_url' | while read -r relative_url; do
            full_url="https://artifacts.security.elastic.co${relative_url}"
            save_path="/var/www/repo/elastic-artifacts/.${relative_url}"
            #log_with_timestamp "Downloading $full_url to $save_path"
            mkdir -p "$(dirname "$save_path")"
            curl --create-dirs -o "$save_path" "$full_url"
        done
    else
        return 1  # Return 1 to signal version does not exist
    fi
}

# Function to process a major version
process_major_version() {
    local major=$1
    local minor=0
    local patch=0

    while true; do
        version="${major}.${minor}.${patch}"
        if ! download_artifacts "$version"; then
            log_with_timestamp "Version ${version} not found, moving to next minor version."
            ((minor++))
            patch=0  # Reset patch number
            # Try the first patch of the next minor version to check if it should stop
            next_version="${major}.${minor}.${patch}"
            if ! curl --head --silent --fail "https://artifacts.security.elastic.co/downloads/endpoint/manifest/artifacts-${next_version}.zip" > /dev/null; then
                log_with_timestamp "Version ${next_version} not found. Moving to next major version."
                break
            fi
        else
            ((patch++))  # Increment patch number if download was successful
        fi
    done
}

# Process both major versions
for major in 8 9; do
    log_with_timestamp "Processing major version ${major}.x.x"
    process_major_version $major
done

log_with_timestamp "All available artifacts from version 8.0.0 and 9.0.0 onwards were checked and downloaded if available."

# Setting correct permissions
chmod -R a+rx /var/www/repo/elastic-artifacts/downloads/endpoint/
log_with_timestamp "Artifacts download and organization completed."