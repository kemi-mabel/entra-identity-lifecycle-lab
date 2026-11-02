<#
.SYNOPSIS
Creates the role-based security groups used by the JML automation.

.DESCRIPTION
Idempotent: checks whether each group exists before creating it, so the
script can be run any number of times without creating duplicates.
Requires an active Microsoft Graph session with Group.ReadWrite.All.
#>

$groups = "LAB-AllStaff", "LAB-Finance", "LAB-Finance-Reports", "LAB-Finance-Payments",
          "LAB-Finance-Approvers", "LAB-IT", "LAB-IT-Helpdesk"

foreach ($name in $groups) {
    $existing = Get-MgGroup -Filter "displayName eq '$name'"
    if ($existing) {
        Write-Host "Already exists: $name"
    }
    else {
        New-MgGroup -DisplayName $name -MailEnabled:$false -MailNickname $name -SecurityEnabled:$true `
            -Description "Role group (managed by JML automation)" | Out-Null
        Write-Host "Created: $name"
    }
}

Get-MgGroup -Filter "startswith(displayName,'LAB-')" | Select-Object DisplayName, Id | Sort-Object DisplayName
