<#
.SYNOPSIS
    Password generation and Base64 decoding utility.

.DESCRIPTION
    Provides Generate-StrongPassword for STIG-compliant password generation
    and Base64 decoding for Kubernetes secret handling. Dot-sourced by
    Rotate-Credentials.ps1 and other pipeline scripts.
#>

function Generate-StrongPassword {
    param (
        [int]$Length = 20
    )

    $upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower = 'abcdefghijklmnopqrstuvwxyz'
    $digits = '0123456789'
    $special = '!@#$%^&*()-_=+[]{}|;:,.<>?'

    $passwordChars = @()
    $passwordChars += $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars += $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars += $digits[(Get-Random -Maximum $digits.Length)]
    $passwordChars += $special[(Get-Random -Maximum $special.Length)]

    $allChars = $upper + $lower + $digits + $special
    for ($i = 4; $i -lt $Length; $i++) {
        $passwordChars += $allChars[(Get-Random -Maximum $allChars.Length)]
    }

    $passwordChars = $passwordChars | Sort-Object { Get-Random }
    $password = -join $passwordChars

    return $password
}

function ConvertFrom-Base64 {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Base64String
    )

    try {
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64String))
    }
    catch {
        throw "Invalid Base64 string: $_"
    }
}
