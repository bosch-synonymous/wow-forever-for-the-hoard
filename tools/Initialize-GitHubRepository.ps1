#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Path = (Split-Path -Parent $PSScriptRoot),
    [string]$Owner = 'bosch-synonymous',
    [string]$Name,
    [ValidateSet('Private', 'Public')][string]$Visibility = 'Private'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'GitHubRepository.psm1') -Force
$parameters = @{ Path = $Path; Owner = $Owner; Visibility = $Visibility }
foreach ($key in @('Name', 'WhatIf', 'Confirm')) {
    if ($PSBoundParameters.ContainsKey($key)) { $parameters[$key] = $PSBoundParameters[$key] }
}
Initialize-GitHubRepository @parameters
