<#
.SYNOPSIS
    Exports Microsoft Entra Conditional Access Policies into a Mermaid.js diagram.
.DESCRIPTION
    Retrieves CA policies using Microsoft Graph PowerShell SDK and generates a clear flowchart.
#>

[CmdletBinding()]
param (
    [string]$OutputPath = ".\CAPolicies.md"
)

# 1. Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Policy.Read.All", "Group.Read.All" -NoWelcome

# 2. Retrieve Conditional Access Policies
Write-Host "Retrieving Conditional Access Policies..." -ForegroundColor Cyan
$policies = Get-MgIdentityConditionalAccessPolicy -All

if (-not $policies) {
    Write-Warning "No Conditional Access policies found or insufficient permissions."
    return
}

# 3. Build the Mermaid Markup
$mermaidBuilder = [System.Text.StringBuilder]::new()
[void]$mermaidBuilder.AppendLine("```mermaid")
[void]$mermaidBuilder.AppendLine("graph TD")
[void]$mermaidBuilder.AppendLine("    %% Styling Definitions")
[void]$mermaidBuilder.AppendLine("    classDef enabled fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#155724;")
[void]$mermaidBuilder.AppendLine("    classDef reportOnly fill:#fff3cd,stroke:#ffc107,stroke-width:2px,color:#856404;")
[void]$mermaidBuilder.AppendLine("    classDef block fill:#f8d7da,stroke:#dc3545,stroke-width:2px,color:#721c24;")
[void]$mermaidBuilder.AppendLine("    classDef grant fill:#d1ecf1,stroke:#17a2b8,stroke-width:2px,color:#0c5460;")
[void]$mermaidBuilder.AppendLine("")

$policyCount = 0

foreach ($policy in$policies) {
    # Skip disabled policies to keep the chart clean
    if ($policy.State -eq "disabled") { continue }
    $policyCount++

    # Sanitize Node IDs and Labels
    $nodeId = "P$($policy.Id -replace '[^a-zA-Z0-9]', '')"
    $cleanName =$policy.DisplayName -replace '["\(\)]', ''

    # Define User Scope / Triggers
    $userScope = "Targeted Users/Groups"
    if ($policy.Conditions.Users.IncludeUsers -contains "All") {
        $userScope = "All Users"
    } elseif ($policy.Conditions.Users.IncludeGroups) {$userScope = "Specific Groups (" + ($policy.Conditions.Users.IncludeGroups.Count) + ")"
    }

    # Define Outcome / Grant Controls
    $controls = @()
    if ($policy.GrantControls.BuiltInControls) {
        $controls +=$policy.GrantControls.BuiltInControls
    }
    if ($policy.GrantControls.CustomAuthenticationFactors) {$controls += "Custom Auth"
    }
    
    $grantText = if ($controls.Count -gt 0) {$controls -join ", " } else { "None" }
    $isBlock =$policy.GrantControls.BuiltInControls -contains "block"

    # Map Flowchart Nodes
    $userId = "U_$nodeId"
    $grantId = "G_$nodeId"

    [void]$mermaidBuilder.AppendLine("    \%\% Policy: $cleanName")
    [void]$mermaidBuilder.AppendLine("    $userId([$userScope]) --> $nodeId{""$cleanName""}")
    
    if ($isBlock) {
        [void]$mermaidBuilder.AppendLine("    $nodeId -->\vert{}Action\vert{}$grantId[/""BLOCK ACCESS""/]")
        [void]$mermaidBuilder.AppendLine("    class $grantId block;")
    } else {
        [void]$mermaidBuilder.AppendLine("    $nodeId -->|Require| $grantId[""$grantText""]")
        [void]$mermaidBuilder.AppendLine("    class $grantId grant;")
    }

    # Apply Policy Status Styling
    if ($policy.State -eq "enabled") {
        [void]$mermaidBuilder.AppendLine("    class $nodeId enabled;")
    } else {
        [void]$mermaidBuilder.AppendLine("    class $nodeId reportOnly;")
    }
    [void]$mermaidBuilder.AppendLine("")
}

[void]$mermaidBuilder.AppendLine("```")

# 4. Wrap with Markdown Header
$markdownOutput = @"
# Conditional Access Policy Architecture

> Automatically generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
> **Total Active/Report-Only Policies:** $policyCount

## Legend
- **Green Node:** Policy Enabled
- **Yellow Node:** Policy in Report-Only Mode
- **Red Node:** Explicit Block Rule
- **Blue Node:** Grant Requirements (MFA, Compliant Device, etc.)

## Flowchart Diagram

$($mermaidBuilder.ToString())
"@

# 5. Output to File
$markdownOutput | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "Diagram generated successfully at $OutputPath" -ForegroundColor Green
