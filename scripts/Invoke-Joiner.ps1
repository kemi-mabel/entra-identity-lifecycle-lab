# Invoke-Joiner.ps1
# Reads the HR feed and creates accounts for new hires (joiners),
# then adds each one to the groups their job title allows (roles.json).
# Requires an active Microsoft Graph session (Connect-MgGraph).

$domain = "oluwakemimabellgmail173.onmicrosoft.com"

# Load the role rules and the HR feed
$config = Get-Content roles.json -Raw | ConvertFrom-Json
$people = Import-Csv hr_feed.csv

foreach ($person in $people) {
    $name = "$($person.FirstName) $($person.LastName)"

    # 1. Only Active people are joiners. Leavers are handled in Phase 4.
    if ($person.Status -ne "Active") {
        Write-Host "SKIP    $name : status is $($person.Status)"
        continue
    }

    # 2. Already has an account? Then not a joiner. Matching on EmployeeId,
    #    never on name, keeps the script safe to re-run (idempotent).
    $existing = Get-MgUser -Filter "employeeId eq '$($person.EmployeeId)'" -ConsistencyLevel eventual -CountVariable count
    if ($existing) {
        Write-Host "SKIP    $name : account already exists"
        continue
    }

    # 3. Work out their groups: defaults plus their role's groups.
    #    Unknown job title = default groups only (never guess, least privilege).
    $groups = @($config.defaultGroups)
    $roleGroups = $config.roles.($person.JobTitle)
    if ($roleGroups) {
        $groups += $roleGroups
    }
    else {
        Write-Host "WARNING $name : job title '$($person.JobTitle)' not in roles.json, default groups only"
    }

    # 4. Create the account with a temporary password they must change at first sign-in.
    #    The password is never printed or logged.
    $upn = "$($person.FirstName).$($person.LastName)@$domain".ToLower()
    $tempPassword = "Lab-" + [guid]::NewGuid().ToString().Substring(0,8) + "!A1"

    $user = New-MgUser -AccountEnabled `
        -DisplayName $name `
        -GivenName $person.FirstName -Surname $person.LastName `
        -UserPrincipalName $upn `
        -MailNickname "$($person.FirstName).$($person.LastName)".ToLower() `
        -Department $person.Department -JobTitle $person.JobTitle `
        -EmployeeId $person.EmployeeId `
        -PasswordProfile @{ Password = $tempPassword; ForceChangePasswordNextSignIn = $true }

    Write-Host "CREATE  $name : $upn"

    # 5. Add them to each of their groups.
    foreach ($groupName in $groups) {
        $group = Get-MgGroup -Filter "displayName eq '$groupName'"
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
        Write-Host "  ADD   $name -> $groupName"
    }
}
