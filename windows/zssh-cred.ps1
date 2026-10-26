# zssh-cred.ps1: read/write zssh passwords in Windows Credential Manager
# (generic credential, target "ssh_pass_<alias>", user name "<alias>").
#   zssh-cred.ps1 get <alias>   write the password to stdout (used by the ssh askpass callback)
#   zssh-cred.ps1 set <alias>   read the password from stdin and save it
# Kept ASCII-only on purpose: Windows PowerShell 5.1 reads BOM-less scripts as the ANSI code page.
param(
    [Parameter(Mandatory = $true)][ValidateSet('get', 'set')][string]$Action,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Alias
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class ZsshCred {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    const int CRED_TYPE_GENERIC = 1;
    const int CRED_PERSIST_LOCAL_MACHINE = 2;

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredReadW(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CredWriteW(ref CREDENTIAL credential, int flags);

    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr buffer);

    public static string Read(string target) {
        IntPtr pointer;
        if (!CredReadW(target, CRED_TYPE_GENERIC, 0, out pointer)) {
            return null;
        }
        try {
            CREDENTIAL credential = (CREDENTIAL)Marshal.PtrToStructure(pointer, typeof(CREDENTIAL));
            return Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
        } finally {
            CredFree(pointer);
        }
    }

    public static void Write(string target, string userName, string secret) {
        byte[] blob = Encoding.Unicode.GetBytes(secret);
        CREDENTIAL credential = new CREDENTIAL();
        credential.Type = CRED_TYPE_GENERIC;
        credential.TargetName = target;
        credential.UserName = userName;
        credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
        credential.CredentialBlobSize = blob.Length;
        credential.CredentialBlob = Marshal.AllocHGlobal(blob.Length);
        try {
            Marshal.Copy(blob, 0, credential.CredentialBlob, blob.Length);
            if (!CredWriteW(ref credential, 0)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        } finally {
            Marshal.FreeHGlobal(credential.CredentialBlob);
        }
    }
}
'@

$target = "ssh_pass_$Alias"
if ($Action -eq 'get') {
    $secret = [ZsshCred]::Read($target)
    if ($null -eq $secret) { exit 1 }
    [Console]::Out.Write($secret)
    exit 0
}

$secret = [Console]::In.ReadToEnd()
if (-not $secret) {
    [Console]::Error.WriteLine('zssh: empty password, nothing saved')
    exit 1
}
[ZsshCred]::Write($target, $Alias, $secret)
