# Entra ID Identity Lifecycle Automation (Joiner / Mover / Leaver)

Automating onboarding, role changes and offboarding in Microsoft Entra ID with PowerShell and Microsoft Graph, built in a personal test tenant.

> Status: in progress. This README is updated as each step is completed.

## Progress

- [x] Step 1: Create a test Entra ID tenant
- [x] Step 2: Install PowerShell 7 on macOS (Apple Silicon)
- [x] Step 3: Install the Microsoft Graph PowerShell modules
- [ ] Step 4: Connect to the tenant with Microsoft Graph

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

## Troubleshooting log

| Problem | Cause | Fix |
|---|---|---|
| `brew install --cask powershell` failed: "No Cask with this name exists" | Homebrew disabled the cask after it failed the macOS Gatekeeper check | Installed the signed `osx-arm64.pkg` from the official PowerShell releases page |
| "Untrusted repository" prompt during `Install-Module` | PSGallery is not trusted by default | Confirmed it is Microsoft's official gallery and accepted (A) |
