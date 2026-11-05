# Invoke-JMLSync.ps1
# Keeps Entra ID in line with the HR feed: joiners, movers and leavers.
#
#   ./Invoke-JMLSync.ps1 -WhatIf    preview only, changes nothing
#   ./Invoke-JMLSync.ps1            apply the changes
#
# Every action is written to an audit log CSV in the logs folder.
# Requires an active Microsoft Graph session (Connect-MgGraph) with
# User.ReadWrite.All, Group.ReadWrite.All and User.RevokeSessions.All.

param(
    [switch]$WhatIf
)

$domain = "<your-tenant>.onmicrosoft.com"   # replace with your tenant's domain

$config = Get-Content roles.json -Raw | ConvertFrom-Json
$people = Import-Csv hr_feed.csv

# Managed groups: the only groups this script is allowed to add or remove.
$managed = @($config.defaultGroups)
foreach ($role in $config.roles.PSObject.Properties) { $managed += $role.Value }
$managed = $managed | Sort-Object -Unique

$log = @()

# Records one action. In preview mode it only records; otherwise it runs the change.
function Invoke-Action($type, $person, $action, [scriptblock]$change) {
    if ($WhatIf) {
        $result = "Preview"
    }
    else {
        try   { & $change; $result = "Success" }
        catch { $result = "Failed: $($_.Exception.Message)" }
    }
    $script:log += [pscustomobject]@{
        Timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Type       = $type
        EmployeeId = $person.EmployeeId
        Name       = "$($person.FirstName) $($person.LastName)"
        Action     = $action
        Result     = $result
    }
    Write-Host ("{0,-8} {1,-16} {2} [{3}]" -f $type, "$($person.FirstName) $($person.LastName)", $action, $result)
}

foreach ($person in $people) {
    $name = "$($person.FirstName) $($person.LastName)"

    # Find the account by EmployeeId (never by name)
    $user = Get-MgUser -Filter "employeeId eq '$($person.EmployeeId)'" -ConsistencyLevel eventual -CountVariable count `
                -Property Id, UserPrincipalName, AccountEnabled, JobTitle, Department

    # Groups this person should have
    $wanted = @($config.defaultGroups)
    if ($config.roles.($person.JobTitle)) { $wanted += $config.roles.($person.JobTitle) }

    # Managed groups this person currently has
    $current = @()
    if ($user) {
        $current = @(Get-MgUserMemberOf -UserId $user.Id |
            ForEach-Object { $_.AdditionalProperties.displayName } |
            Where-Object { $_ -in $managed })
    }

    # ---------- LEAVER ----------
    if ($person.Status -eq "Terminated") {
        if (-not $user) { continue }   # never had an account, nothing to do
        if (-not $user.AccountEnabled -and $current.Count -eq 0) {
            Write-Host ("{0,-8} {1,-16} already offboarded" -f "OK", $name)
            continue
        }
        $id = $user.Id
        if ($user.AccountEnabled) {
            Invoke-Action "LEAVER" $person "Disable account"         { Update-MgUser -UserId $id -AccountEnabled:$false }.GetNewClosure()
            Invoke-Action "LEAVER" $person "Revoke sign-in sessions" { Revoke-MgUserSignInSession -UserId $id | Out-Null }.GetNewClosure()
        }
        foreach ($g in $current) {
            $gid = (Get-MgGroup -Filter "displayName eq '$g'").Id
            Invoke-Action "LEAVER" $person "Remove from $g" { Remove-MgGroupMemberByRef -GroupId $gid -DirectoryObjectId $id }.GetNewClosure()
        }
        continue
    }

    # ---------- JOINER ----------
    if (-not $user) {
        $upn  = "$($person.FirstName).$($person.LastName)@$domain".ToLower()
        $nick = "$($person.FirstName).$($person.LastName)".ToLower()
        $pw   = "Lab-" + [guid]::NewGuid().ToString().Substring(0,8) + "!A1"
        $script:newUser = $null
        Invoke-Action "JOINER" $person "Create account $upn" {
            $script:newUser = New-MgUser -AccountEnabled -DisplayName $name `
                -GivenName $person.FirstName -Surname $person.LastName `
                -UserPrincipalName $upn -MailNickname $nick `
                -Department $person.Department -JobTitle $person.JobTitle -EmployeeId $person.EmployeeId `
                -PasswordProfile @{ Password = $pw; ForceChangePasswordNextSignIn = $true }
        }
        foreach ($g in $wanted) {
            $gid = (Get-MgGroup -Filter "displayName eq '$g'").Id
            Invoke-Action "JOINER" $person "Add to $g" { New-MgGroupMember -GroupId $gid -DirectoryObjectId $script:newUser.Id }.GetNewClosure()
        }
        continue
    }

    # ---------- ACTIVE BUT DISABLED: needs a human ----------
    if (-not $user.AccountEnabled) {
        Write-Host ("{0,-8} {1,-16} account is disabled but Active in HR (possible rehire), needs manual review" -f "REVIEW", $name)
        continue
    }

    # ---------- MOVER ----------
    $toAdd    = @($wanted  | Where-Object { $_ -notin $current })
    $toRemove = @($current | Where-Object { $_ -notin $wanted })
    $titleChanged = ($user.JobTitle -ne $person.JobTitle) -or ($user.Department -ne $person.Department)

    if (-not $titleChanged -and $toAdd.Count -eq 0 -and $toRemove.Count -eq 0) {
        Write-Host ("{0,-8} {1,-16} matches HR, no change" -f "OK", $name)
        continue
    }

    $id = $user.Id
    if ($titleChanged) {
        Invoke-Action "MOVER" $person "Update title to $($person.JobTitle), department to $($person.Department)" {
            Update-MgUser -UserId $id -JobTitle $person.JobTitle -Department $person.Department
        }.GetNewClosure()
    }
    # Remove before add, so no one ever holds old and new access at the same time
    foreach ($g in $toRemove) {
        $gid = (Get-MgGroup -Filter "displayName eq '$g'").Id
        Invoke-Action "MOVER" $person "Remove from $g" { Remove-MgGroupMemberByRef -GroupId $gid -DirectoryObjectId $id }.GetNewClosure()
    }
    foreach ($g in $toAdd) {
        $gid = (Get-MgGroup -Filter "displayName eq '$g'").Id
        Invoke-Action "MOVER" $person "Add to $g" { New-MgGroupMember -GroupId $gid -DirectoryObjectId $id }.GetNewClosure()
    }
}

# ---------- Audit log ----------
if ($log.Count -gt 0) {
    New-Item -ItemType Directory -Force -Path logs | Out-Null
    $mode = if ($WhatIf) { "preview" } else { "applied" }
    $file = "logs/jml-$mode-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $log | Export-Csv -Path $file -NoTypeInformation
    Write-Host "`nAudit log saved: $file"
}
else {
    Write-Host "`nNo changes needed."
}
