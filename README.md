# Entra ID Identity Lifecycle Automation (Joiner / Mover / Leaver)

Automating onboarding, role changes and offboarding in Microsoft Entra ID with PowerShell and Microsoft Graph, built in a personal test tenant.

> Status: in progress. This README is updated as each step is completed.

## Progress

- [x] Step 1: Create a test Entra ID tenant
- [x] Step 2: Install PowerShell 7 on macOS (Apple Silicon)
- [x] Step 3: Install the Microsoft Graph PowerShell modules
- [x] Step 4: Connect to the tenant with Microsoft Graph (least-privilege scopes)
- [ ] Step 5: Create role-based security groups

## Lab environment

| Item | Detail |
|---|---|
| Machine | MacBook Pro, Apple M1 |
| Shell | PowerShell 7.6.9 |
| Identity platform | Microsoft Entra ID (Free license), dedicated test tenant |
| Modules | Microsoft.Graph.Authentication, .Users, .Users.Actions, .Groups (v2.41.2) |

## Step 1: Test tenant

Created a new Azure free account, which provisions a dedicated Entra ID tenant. A separate tenant keeps all testing away from any real organization's identities.

![Entra tenant overview](screenshots/01-tenant-overview.png)
*Tenant ID and domain blurred.*

## Step 2: PowerShell 7 on macOS

The Homebrew `powershell` cask has been disabled (it failed the macOS Gatekeeper check), so PowerShell was installed from Microsoft's official signed package instead (`powershell-7.6.9-osx-arm64.pkg` from the PowerShell GitHub releases page).

```
$ pwsh --version
PowerShell 7.6.9
```

## Step 3: Microsoft Graph modules

Installed only the Graph submodules this project needs, rather than the full `Microsoft.Graph` bundle, to keep the install small and fast.

```powershell
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Users.Actions, Microsoft.Graph.Groups -Scope CurrentUser
```

```
Name                          Version
----                          -------
Microsoft.Graph.Authentication 2.41.2
Microsoft.Graph.Groups         2.41.2
Microsoft.Graph.Users          2.41.2
Microsoft.Graph.Users.Actions  2.41.2
```

## Step 4: Connect to Microsoft Graph with least privilege

**What:** Signed PowerShell into the test tenant and requested only the permissions this project needs.

**Why:** Microsoft Graph is the API behind Entra ID, so anything done in the portal can be automated through it. Each permission (scope) is requested explicitly, which keeps the session to least privilege:

| Scope | Why it is needed |
|---|---|
| `User.ReadWrite.All` | Create, update and disable user accounts (joiner, mover, leaver) |
| `Group.ReadWrite.All` | Create role groups and change their membership |

No mailbox, directory role or tenant-wide admin scopes were requested. These are **delegated** permissions, so the script acts as the signed-in admin and can never exceed that admin's rights. Admin consent was granted once for the tenant to the *Microsoft Graph Command Line Tools* app.

```powershell
Connect-MgGraph -TenantId "<tenant>.onmicrosoft.com" -Scopes "User.ReadWrite.All","Group.ReadWrite.All" -UseDeviceCode
Get-MgContext | Select-Object Account, TenantId, Scopes
```

```
Account TenantId                             Scopes
------- --------                             ------
        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx {Group.ReadWrite.All, openid, profile, User.ReadWrite.All}
```

Checking the session context before making changes confirms *which tenant* and *which permissions* the script will run with. Running against the wrong tenant is a common real-world mistake.

## Troubleshooting log

| Problem | Cause | Fix |
|---|---|---|
| `brew install --cask powershell` failed: "No Cask with this name exists" | Homebrew disabled the cask after it failed the macOS Gatekeeper check | Installed the signed `osx-arm64.pkg` from the official PowerShell releases page |
| "Untrusted repository" prompt during `Install-Module` | PSGallery is not trusted by default | Confirmed it is Microsoft's official gallery and accepted (A) |
| `Connect-MgGraph` returned with no output and `Get-MgContext` was empty | The interactive browser sign-in never launched on macOS, and the failure was silent | Switched to device code flow (`-UseDeviceCode`) |
| `$Error[0]` showed "Access to the path '/usr/local/share/powershell' is denied" | Unrelated: PowerShellGet tried to create an all-users folder during the earlier install. Modules were installed per-user, so it had no effect | Identified as noise, not the root cause |
| Device code sign-in failed with "The code you entered has expired" on login.live.com | The tenant admin is a personal Microsoft account. Without a tenant specified, sign-in was routed to the consumer endpoint, which did not recognize the work-tenant code | Added `-TenantId` so sign-in went to login.microsoftonline.com for this tenant |
| "Authentication timed out after 120 seconds" | Sign-in plus the first-time consent screen took longer than PowerShell's 120-second wait | Re-ran; consent was already stored, so sign-in completed quickly |

## Improvements noted
- Create a dedicated cloud-only admin account in the tenant instead of using a personal Microsoft account as admin (the `Account` field is blank for the personal account, and separating admin identities from everyday ones is standard practice).

