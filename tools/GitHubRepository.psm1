#requires -Version 7.0
Set-StrictMode -Version Latest

function Invoke-GitCommand {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)
    $process = $null
    try {
        $start = [Diagnostics.ProcessStartInfo]::new('git')
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.ArgumentList.Add('--no-optional-locks')
        $start.ArgumentList.Add('-C'); $start.ArgumentList.Add($Path)
        foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        foreach ($key in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE')) { $start.Environment.Remove($key) | Out-Null }
        $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
        $start.Environment['GCM_INTERACTIVE'] = 'never'
        $process = [Diagnostics.Process]::Start($start)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill($true)
            throw 'Git operation timed out.'
        }
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $outputTask.GetAwaiter().GetResult()
            StdErr = $errorTask.GetAwaiter().GetResult()
        }
    }
    catch { throw 'Git could not complete the local operation. No command output was displayed.' }
    finally { if ($null -ne $process) { $process.Dispose() } }
}

function Get-GitHubCredential {
    param([Parameter(Mandatory)][string]$Owner)
    $process = $null
    $captured = $discarded = $token = $null
    $values = @{}
    try {
        $start = [Diagnostics.ProcessStartInfo]::new('git')
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($argument in @('-c', 'credential.interactive=false', 'credential', 'fill')) { $start.ArgumentList.Add($argument) }
        $start.Environment['GIT_TERMINAL_PROMPT'] = '0'
        $start.Environment['GCM_INTERACTIVE'] = 'never'
        foreach ($key in @('GIT_TRACE', 'GIT_TRACE_CURL', 'GIT_CURL_VERBOSE', 'GCM_TRACE', 'GCM_TRACE_SECRETS')) { $start.Environment[$key] = '0' }
        $process = [Diagnostics.Process]::Start($start)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write("protocol=https`nhost=github.com`nusername=$Owner`n`n")
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(30000)) { $process.Kill($true); throw 'Credential access timed out.' }
        $captured = $outputTask.GetAwaiter().GetResult()
        $discarded = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Credential access failed.' }
        foreach ($line in $captured -split "`n") {
            $parts = $line.TrimEnd("`r").Split('=', 2)
            if ($parts.Count -eq 2) { $values[$parts[0]] = $parts[1] }
        }
        $token = $values['password']
        if ([string]::IsNullOrWhiteSpace($token)) { throw 'Credential access returned no token.' }
        return $token
    }
    catch { throw 'Saved GitHub sign-in is unavailable. Sign in with Git Credential Manager and retry. No credentials were displayed.' }
    finally {
        $values.Clear()
        $captured = $discarded = $token = $parts = $line = $outputTask = $errorTask = $null
        if ($null -ne $process) { $process.Dispose() }
    }
}

function Invoke-GitHubRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [object]$Body
    )
    $client = $request = $response = $handler = $null
    try {
        if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'api.github.com' -or -not $Uri.IsDefaultPort -or $Uri.UserInfo) {
            throw 'Unexpected GitHub API endpoint.'
        }
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $client = [Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(30)
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
        $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
        $request.Headers.Add('Accept', 'application/vnd.github+json')
        $request.Headers.Add('X-GitHub-Api-Version', '2026-03-10')
        $request.Headers.Add('User-Agent', 'WoW-Addon-Repository-Setup')
        if ($PSBoundParameters.ContainsKey('Body')) {
            $request.Content = [Net.Http.StringContent]::new(($Body | ConvertTo-Json -Compress -Depth 10), [Text.Encoding]::UTF8, 'application/json')
        }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $data = $null
        if ([int]$response.StatusCode -in @(200, 201)) { $data = $content | ConvertFrom-Json -ErrorAction Stop }
        [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $data }
    }
    catch { throw 'GitHub request could not be completed or its response was unreadable. No credentials were displayed.' }
    finally {
        if ($null -ne $request) { $request.Headers.Clear(); $request.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $client) { $client.Dispose() }
        elseif ($null -ne $handler) { $handler.Dispose() }
        $Token = $null
    }
}

function Test-MatchingOrigin {
    param([string]$Value, [string]$Owner, [string]$Name)
    $repository = $null
    if ($Value -match '^git@github\.com:([^/]+/[^/]+?)/?$') { $repository = $Matches[1] }
    else {
        $uri = $null
        if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) { return $false }
        if ($uri.Host -ne 'github.com' -or $uri.Query -or $uri.Fragment) { return $false }
        if ($uri.Scheme -eq 'https' -and $uri.IsDefaultPort -and -not $uri.UserInfo) { $repository = $uri.AbsolutePath.Trim('/') }
        elseif ($uri.Scheme -eq 'ssh' -and $uri.UserInfo -eq 'git' -and $uri.Port -in @(-1, 22)) { $repository = $uri.AbsolutePath.Trim('/') }
    }
    if (-not $repository) { return $false }
    $repository = $repository -replace '\.git$', ''
    return [string]::Equals($repository, "$Owner/$Name", [StringComparison]::OrdinalIgnoreCase)
}

function Assert-RepositoryMetadata {
    param([object]$Repository, [string]$Owner, [string]$Name, [bool]$Private)
    $valid = $false
    try {
        $valid = $Repository.owner.login -is [string] -and $Repository.name -is [string] `
            -and [string]::Equals($Repository.owner.login, $Owner, [StringComparison]::OrdinalIgnoreCase) `
            -and [string]::Equals($Repository.name, $Name, [StringComparison]::OrdinalIgnoreCase) `
            -and $Repository.private -is [bool] -and $Repository.private -eq $Private
        if ($Repository.PSObject.Properties['visibility']) {
            $expected = if ($Private) { 'private' } else { 'public' }
            $valid = $valid -and $Repository.visibility -is [string] -and $Repository.visibility -eq $expected
        }
    }
    catch { $valid = $false }
    if (-not $valid) { throw 'GitHub repository owner, name or visibility differs from the requested repository. Nothing was changed locally.' }
}

function Initialize-GitHubRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$Path = (Split-Path -Parent $PSScriptRoot),
        [string]$Owner = 'bosch-synonymous',
        [string]$Name,
        [ValidateSet('Private', 'Public')][string]$Visibility = 'Private'
    )
    if ($Owner -notmatch '\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?\z' -or $Owner.Contains('--')) { throw 'Owner must be a valid GitHub personal-account name.' }
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if ($resolved.Provider.Name -ne 'FileSystem' -or -not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Container)) { throw 'Path must be an existing filesystem directory.' }
    $localPath = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($resolved.ProviderPath))
    if (-not $PSBoundParameters.ContainsKey('Name')) { $Name = 'wow-forever-' + [IO.Path]::GetFileName($localPath) }
    if ($Name -notmatch '\A[A-Za-z0-9_.-]{1,100}\z' -or $Name -in @('.', '..')) { throw 'Name must contain 1-100 letters, digits, periods, underscores or hyphens, and cannot be a dot directory.' }
    $Visibility = if ($Visibility -eq 'Private') { 'Private' } else { 'Public' }
    $repositoryUrl = "https://github.com/$Owner/$Name.git"
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $root = Invoke-GitCommand -Path $localPath -Arguments @('rev-parse', '--show-toplevel')
    $hasGit = $root.ExitCode -eq 0
    $hasOrigin = $false
    if ($hasGit) {
        $gitRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($root.StdOut.Trim()))
        if (-not [string]::Equals($localPath, $gitRoot, $comparison)) { throw 'Path is inside another Git repository or worktree. Select the exact repository root.' }
        $remotes = Invoke-GitCommand -Path $localPath -Arguments @('remote')
        if ($remotes.ExitCode -ne 0) { throw 'Existing Git remotes could not be inspected.' }
        $hasOrigin = @($remotes.StdOut -split '\r?\n') -ccontains 'origin'
        if ($hasOrigin) {
            foreach ($arguments in @(@('remote', 'get-url', '--all', 'origin'), @('remote', 'get-url', '--push', '--all', 'origin'))) {
                $origin = Invoke-GitCommand -Path $localPath -Arguments $arguments
                $urls = @($origin.StdOut -split '\r?\n' | Where-Object { $_ })
                if ($origin.ExitCode -ne 0 -or $urls.Count -eq 0) { throw 'Existing origin could not be inspected.' }
                foreach ($url in $urls) {
                    if (-not (Test-MatchingOrigin -Value $url -Owner $Owner -Name $Name)) { throw 'Existing origin points somewhere else. It has been preserved; choose the matching repository or resolve the origin explicitly.' }
                }
            }
        }
    }
    else {
        $gitDirectory = Invoke-GitCommand -Path $localPath -Arguments @('rev-parse', '--git-dir')
        if ($gitDirectory.ExitCode -eq 0) { throw 'Path is not the root of a supported Git worktree.' }
        $ancestor = [IO.DirectoryInfo]::new($localPath)
        while ($null -ne $ancestor) {
            if (Test-Path -LiteralPath (Join-Path $ancestor.FullName '.git')) { throw 'Existing Git metadata could not be inspected safely.' }
            $ancestor = $ancestor.Parent
        }
    }
    $actions = [Collections.Generic.List[string]]::new()
    $actions.Add('Verify the saved GitHub account and reuse or create the requested repository')
    if (-not $hasGit) { $actions.Add('Initialize local Git on main') }
    if (-not $hasOrigin) { $actions.Add('Add origin') }
    $plan = [pscustomobject]@{
        Path = $localPath; Owner = $Owner; Name = $Name; Visibility = $Visibility
        RepositoryUrl = $repositoryUrl; RepositoryExists = $null
        LocalRepositoryExists = $hasGit; OriginExists = $hasOrigin
        Actions = $actions.ToArray(); WhatIf = [bool]$WhatIfPreference; Completed = $false
    }
    if (-not $PSCmdlet.ShouldProcess("$Owner/$Name and $localPath", 'Create or reuse GitHub repository and initialize/link local Git')) { return $plan }
    $token = $null
    try {
        try { $token = Get-GitHubCredential -Owner $Owner }
        catch { throw 'Saved GitHub sign-in is unavailable. Sign in with Git Credential Manager and retry. No credentials were displayed.' }
        if ([string]::IsNullOrWhiteSpace($token)) { throw 'Saved GitHub sign-in returned no usable credential.' }
        try { $account = Invoke-GitHubRequest -Method GET -Uri 'https://api.github.com/user' -Token $token }
        catch { throw 'GitHub account verification could not be completed. No credentials were displayed and nothing was changed.' }
        $login = $null
        try { $login = $account.Body.login } catch { }
        if ($account.StatusCode -ne 200 -or $login -isnot [string] -or -not [string]::Equals($login, $Owner, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Saved GitHub sign-in could not be verified as the requested personal account. Nothing was changed.'
        }
        $endpoint = "https://api.github.com/repos/$Owner/$Name"
        try { $remote = Invoke-GitHubRequest -Method GET -Uri $endpoint -Token $token }
        catch { throw 'GitHub repository lookup could not be completed. No credentials were displayed and nothing was changed.' }
        if ($remote.StatusCode -eq 200) {
            Assert-RepositoryMetadata -Repository $remote.Body -Owner $Owner -Name $Name -Private ($Visibility -eq 'Private')
            $plan.RepositoryExists = $true
        }
        elseif ($remote.StatusCode -eq 404) {
            try {
                $remote = Invoke-GitHubRequest -Method POST -Uri 'https://api.github.com/user/repos' -Token $token `
                    -Body @{ name = $Name; private = ($Visibility -eq 'Private'); auto_init = $false }
            }
            catch { throw 'GitHub did not confirm repository creation. Inspect the target repository and rerun; reruns check for an existing repository first. No credentials were displayed.' }
            if ($remote.StatusCode -ne 201) { throw 'GitHub did not confirm repository creation. Inspect the target repository and rerun; no local Git changes were made.' }
            Assert-RepositoryMetadata -Repository $remote.Body -Owner $Owner -Name $Name -Private ($Visibility -eq 'Private')
            $plan.RepositoryExists = $true
        }
        else { throw 'GitHub repository lookup failed. Only an explicit not-found response permits creation; no changes were made.' }
        if (-not $hasGit) {
            $created = Invoke-GitCommand -Path $localPath -Arguments @('init', '--initial-branch', 'main')
            if ($created.ExitCode -ne 0) { throw 'The remote repository exists, but local Git initialization failed. Inspect the local directory and rerun.' }
        }
        if (-not $hasOrigin) {
            $linked = Invoke-GitCommand -Path $localPath -Arguments @('remote', 'add', 'origin', $repositoryUrl)
            if ($linked.ExitCode -ne 0) { throw 'The remote repository exists, but adding origin failed. Existing local history and remotes were preserved; inspect and rerun.' }
        }
        $plan.LocalRepositoryExists = $true
        $plan.OriginExists = $true
        $plan.Completed = $true
        return $plan
    }
    finally { $token = $null }
}

Export-ModuleMember -Function Initialize-GitHubRepository
