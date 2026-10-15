; Driver installer (NSIS). Built by tools/build.sh or the release workflow.
Unicode true

!define APPNAME "Driver"
!ifndef VERSION
  !define VERSION "0.1.0"
!endif
!define PUBLISHER "bhxuk"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

Name "${APPNAME}"
OutFile "../build/Driver-Setup.exe"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\${APPNAME}" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "${APPNAME} ${VERSION}"

!include "MUI2.nsh"
!define MUI_ICON "../icon.ico"
!define MUI_UNICON "../icon.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Install ${APPNAME} ${VERSION}"
!define MUI_WELCOMEPAGE_TEXT "Off-road driving, solo or with up to three friends over LAN or Tailscale.$\r$\n$\r$\nSetup will also allow ${APPNAME} through Windows Firewall so friends can join your sessions."
!define MUI_FINISHPAGE_RUN "$INSTDIR\Driver.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APPNAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "FileDescription" "${APPNAME} Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "${PUBLISHER}"

Section "Install"
  SetOutPath "$INSTDIR"
  File "../build/windows/Driver.exe"
  File "../icon.ico"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\${APPNAME}" "InstallDir" "$INSTDIR"

  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\Driver.exe" "" "$INSTDIR\icon.ico"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\Driver.exe" "" "$INSTDIR\icon.ico"

  ; Let friends connect when you host (LAN or Tailscale).
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="${APPNAME}"'
  nsExec::ExecToLog 'netsh advfirewall firewall add rule name="${APPNAME}" dir=in action=allow program="$INSTDIR\Driver.exe" enable=yes profile=any'

  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\icon.ico"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINSTKEY}" "URLInfoAbout" "https://bhxuk.github.io/driver/"
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="${APPNAME}"'
  Delete "$INSTDIR\Driver.exe"
  Delete "$INSTDIR\icon.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"
  Delete "$DESKTOP\${APPNAME}.lnk"
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\${APPNAME}"
SectionEnd
