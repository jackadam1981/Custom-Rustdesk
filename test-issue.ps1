# Test Issue #1 content updates

Write-Host "=== Test Issue 1 content updates ==="

# Step 1: Check Issue 1 current status
Write-Host "Step 1: Check Issue 1 current status"
$issue = gh issue view 1 --json number,title,body,state,createdAt,updatedAt
if ($LASTEXITCODE -eq 0) {
    $issueObj = $issue | ConvertFrom-Json
    Write-Host "PASS Issue 1 status check"
    Write-Host "Title $($issueObj.title)"
    Write-Host "Body length $($issueObj.body.Length) characters"
} else {
    Write-Host "FAIL Issue 1 status check"
    exit 1
}

# Step 2: Test simple text update
Write-Host "Step 2: Test simple text update"
$simpleBody = "# Simple test update`n`nTest time $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`nTest content Simple text update test"
$result = gh issue edit 1 --body $simpleBody 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS Simple text update"
} else {
    Write-Host "FAIL Simple text update"
    Write-Host $result
}

# Step 3: Check simple text update result
Write-Host "Step 3: Check simple text update result"
$issue = gh issue view 1 --json number,title,body,state,updatedAt
if ($LASTEXITCODE -eq 0) {
    $issueObj = $issue | ConvertFrom-Json
    Write-Host "PASS Simple text update check"
    Write-Host "Update time $($issueObj.updatedAt)"
} else {
    Write-Host "FAIL Simple text update check"
}

# Step 4: Test JSON update
Write-Host "Step 4: Test JSON update"
$jsonData = @{
    queue = @()
    issue_locked_by = $null
    queue_locked_by = $null
    build_locked_by = $null
    issue_lock_version = 1
    queue_lock_version = 1
    build_lock_version = 1
    version = 1
} | ConvertTo-Json -Compress

$time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$jsonBody = "# JSON test update`n`nTest time $time`nTest content JSON data update test`n`nTest JSON data`n```json`n$jsonData`n```"

$result = gh issue edit 1 --body $jsonBody 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "PASS JSON update"
} else {
    Write-Host "FAIL JSON update"
    Write-Host $result
}

# Step 5: Check JSON update result
Write-Host "Step 5: Check JSON update result"
$issue = gh issue view 1 --json number,title,body,state,updatedAt
if ($LASTEXITCODE -eq 0) {
    $issueObj = $issue | ConvertFrom-Json
    Write-Host "PASS JSON update check"
    Write-Host "Update time $($issueObj.updatedAt)"
    if ($issueObj.body -match '```json') {
        Write-Host "PASS Contains JSON code block"
    } else {
        Write-Host "FAIL No JSON code block found"
    }
} else {
    Write-Host "FAIL JSON update check"
}

Write-Host "Test completed"