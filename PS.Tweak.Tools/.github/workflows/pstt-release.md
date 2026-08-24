<!-- ===========================================================================
     RELEASE PAGE TEMPLATE FOR PS.Tweak.Tools
     ---------------------------------------------------------------------------
     This file is used by the GitHub Actions workflow pstt-release.yml
     to build the release body dynamically.

     The following placeholders are replaced at runtime by the workflow:
       {{LOGO_URL}}          -> Raw URL to the project logo image
       {{ZIP_FILENAME}}      -> Full ZIP filename (e.g. PS.Tweak.Tools-1.00.00-Release.zip)
       {{DOWNLOAD_URL}}      -> Full direct download URL for the ZIP file
       {{REPO_URL}}          -> GitHub repository base URL
       {{VERSION}}           -> Version number (e.g. 1.00.00)
       {{UNOFFICIAL_BANNER}} -> Empty string OR unofficial warning banner
       {{RELEASE_NOTES}}     -> Additional release notes or default placeholder
       {{SYNC_STATUS}}       -> Cross-repo sync result line (set by Step 7)

     IMPORTANT - PS.Tweak.Tools is a building block of the WinTwin.Fusion
     Framework, NOT a standalone module. The ZIP package built from this
     release exists solely to allow advanced users to apply an unofficial,
     early update of this component inside an EXISTING WinTwin.Fusion
     installation, ahead of the official merge into the WinTwin.Fusion repo.
     Standalone WinTwin.Fusion tools (e.g. WTF.Console) get their own
     dedicated repository and their own release template - this notice does
     NOT apply to them.
=========================================================================== -->

{{UNOFFICIAL_BANNER}}
<p align="center">
  <img src="{{LOGO_URL}}" alt="PS.Tweak.Tools Logo" width="480" />
</p>

## 🖥️ **File Download:**

**📦 [`{{ZIP_FILENAME}}`]({{DOWNLOAD_URL}})**
<br>

## ℹ️ System Requirements:
- Windows 11, Version 24H2 or 25H2
- PowerShell 5.1 or higher
- An existing **WinTwin.Fusion** installation (PS.Tweak.Tools cannot be used standalone)
<br>

## 🪛 Installation / Usage:

> ⚠️ **Important:** PS.Tweak.Tools is **not a standalone module**. It is an integral
> building block of the **WinTwin.Fusion Framework** and only functions correctly
> when used together with an existing WinTwin.Fusion installation. Standalone
> WinTwin.Fusion tools (e.g. `WTF.Console`) are published in their own dedicated
> repositories and are **not** affected by this notice.

### 📦 About this ZIP package:

This release ZIP is **not** intended for manual, standalone usage. It exists
solely to let advanced users apply an **unofficial, early update** of the
PS.Tweak.Tools component inside an existing WinTwin.Fusion installation -
before the corresponding change has been officially merged and released
through the [WinTwin.Fusion repository]({{REPO_URL}}).

Official, fully tested integrations of PS.Tweak.Tools are always delivered
through the regular WinTwin.Fusion release channel via the automatic
cross-repo synchronization described below.

### 🔧 Manual (unofficial) update procedure:

1. Download the ZIP archive from the link above.
2. Extract the archive to a location of your choice.
3. Locate the `PS.Tweak.Tools` subdirectory inside your existing WinTwin.Fusion
   installation folder (e.g. `C:\WinTwin.Fusion\PS.Tweak.Tools`).
4. Replace the entire contents of that `PS.Tweak.Tools` subdirectory with the
   files extracted in step 2.
5. Restart WinTwin.Fusion (or reload the affected module/tool) to apply the update.

> ⚠️ Using this unofficial update path is done **at your own risk**. It is only
> meant for testing changes ahead of an official release. Always prefer the
> official, tested integration delivered through the WinTwin.Fusion repository.
<br>

## 🔄 Cross-Repo Synchronization:

{{SYNC_STATUS}}
<br>

## 📜 License/Copyright:

**PS.Tweak.Tools** is licensed for **private, non-commercial use only**.

- ❌ Commercial use of any kind is strictly prohibited.
- ❌ Editing, modifying, or manipulating this software in any form or manner without the explicit written consent of the developer is not permitted.
- ⚠️ Use of PS.Tweak.Tools is entirely at the user's own risk. No liability is assumed for any damage to hardware and/or software that may occur.
- ⚠️ Any consequences arising from the use of PS.Tweak.Tools are solely the responsibility of the user.

> **PS.Tweak.Tools™** · © 2026 by WinTwin-Fusion · All rights reserved.
<br>

## 🛟 Security Advise:

> ⚠️ **Important:** The official and only trusted source for PS.Tweak.Tools is:
>
> 🔗 **[https://github.com/WinTwin-Fusion/PS.Tweak.Tools](https://github.com/WinTwin-Fusion/PS.Tweak.Tools)**
>
> It is **strongly recommended** to download PS.Tweak.Tools **exclusively** from this official source. Do not use copies from unknown or untrusted third-party sources, as these may have been tampered with or contain malicious code.
<br>

## 📝 Additional Notes:

{{RELEASE_NOTES}}
<br>

---
Part of the WinTwin.Fusion Framework · [WinTwin-Fusion Organization](https://github.com/WinTwin-Fusion)
