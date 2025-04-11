# Download and process winget source index
$tempPath = [System.IO.Path]::GetTempPath()
$msixPath = Join-Path $tempPath "source.msix"
$extractPath = Join-Path $tempPath "winget_source"
$dbPath = Join-Path $extractPath "Public/index.db"

# Download the MSIX file with retry mechanism
$retryCount = 0
$maxRetries = 5
$downloadSuccess = $false

while ($retryCount -lt $maxRetries -and -not $downloadSuccess) {
    try {
        Write-Host "Downloading source.msix..."
        $response = Invoke-WebRequest -Uri "https://cdn.winget.microsoft.com/cache/source.msix" -OutFile $msixPath -PassThru
        Write-Host "Downloaded source.msix with status code $($response.StatusCode)"
        if ($response.StatusCode -eq 200 -and (Test-Path $msixPath)) {
            # Verify if the file is a valid ZIP
            try {
                Write-Host "Verifying downloaded file..."
                [io.compression.zipfile]::OpenRead($msixPath).Dispose()
                Write-Host "Downloaded file is a valid ZIP"
                $downloadSuccess = $true
            } catch {
                Remove-Item $msixPath -Force
                throw "Downloaded file is not a valid ZIP"
            }
        } else {
            throw "HTTP request failed with status code $($response.StatusCode)"
        }
    } catch {
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            throw "Failed to download MSIX file after $maxRetries attempts"
        }
        Start-Sleep -Seconds 30
    }
}

# Create extraction directory if it doesn't exist
if (Test-Path $extractPath) {
    Remove-Item $extractPath -Recurse -Force
}
New-Item -ItemType Directory -Path $extractPath | Out-Null

# Extract MSIX as ZIP
try {
    Expand-Archive -Path $msixPath -DestinationPath $extractPath -Force
} catch {
    Write-Host "Failed to extract MSIX file: $_"
    exit 1
}

# Install PSSQLite module if not present
if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
    Install-Module -Name PSSQLite -Force -Scope CurrentUser
}

# Import SQLite module
Import-Module PSSQLite

# Query to get manifest data with latest version for each ID
$query = @"
WITH RankedVersions AS (
    SELECT 
        i.id as Id,
        v.version as Version,
        ROW_NUMBER() OVER (PARTITION BY i.id ORDER BY v.version DESC) as rn
    FROM manifest m
    JOIN ids i ON m.id = i.rowid
    JOIN versions v ON m.version = v.rowid
)
SELECT Id, Version
FROM RankedVersions
WHERE rn = 1
ORDER BY Id
"@

# Execute query and process results
$results = Invoke-SqliteQuery -DataSource $dbPath -Query $query

Write-Host "Found $($results.Count) manifests"

# Create or clean output directory
$outputDir = "manifests"
if (Test-Path $outputDir) {
    Remove-Item $outputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir | Out-Null

# Process each manifest
foreach ($manifest in $results) {
    # Create JSON content
    $jsonContent = [ordered]@{
        id = $manifest.Id
        version = $manifest.Version
    } | ConvertTo-Json
    
    # Get first character of ID in lowercase for subdirectory
    $subDir = $manifest.Id.Substring(0, 1).ToLower()
    $subDirPath = Join-Path $outputDir $subDir
    
    # Create subdirectory if it doesn't exist
    if (-not (Test-Path $subDirPath)) {
        New-Item -ItemType Directory -Path $subDirPath | Out-Null
    }
    
    # Create file path based on manifest ID in the subdirectory
    $filePath = Join-Path $subDirPath "$($manifest.Id).json"
    $jsonContent | Out-File -FilePath $filePath -Encoding UTF8 -Force
}

# Cleanup
Remove-Item $msixPath -Force
Remove-Item $extractPath -Recurse -Force
