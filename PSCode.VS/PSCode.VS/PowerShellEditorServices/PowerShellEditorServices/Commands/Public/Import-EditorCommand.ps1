# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

function Import-EditorCommand {
    <#
    .EXTERNALHELP ..\PowerShellEditorServices.Commands-help.xml
    #>
    [OutputType([Microsoft.PowerShell.EditorServices.Extensions.EditorCommand, Microsoft.PowerShell.EditorServices])]
    [CmdletBinding(DefaultParameterSetName='ByCommand')]
    param(
        [Parameter(Position=0,
                   Mandatory,
                   ValueFromPipeline,
                   ValueFromPipelineByPropertyName,
                   ParameterSetName='ByCommand')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Command,

        [Parameter(Position=0, Mandatory, ParameterSetName='ByModule')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Module,

        [switch]
        $Force,

        [switch]
        $PassThru
    )
    begin {
        function GetCommandsFromModule {
            param(
                [Parameter(ValueFromPipeline)]
                [string]
                $ModuleToSearch
            )
            process {
                if (-not $ModuleToSearch) { return }

                $caller = (Get-PSCallStack)[2]

                if ($caller.InvocationInfo.MyCommand.ScriptBlock.Module.Name -eq $ModuleToSearch) {
                    $moduleInfo = $caller.InvocationInfo.MyCommand.ScriptBlock.Module

                    return $moduleInfo.Invoke(
                        {
                            $ExecutionContext.SessionState.InvokeProvider.Item.Get('function:\*') |
                                Where-Object ModuleName -eq $args[0]
                        },
                        $ModuleToSearch)
                }

                $moduleInfo = Get-Module $ModuleToSearch -ErrorAction SilentlyContinue
                return $moduleInfo.ExportedFunctions.Values
            }
        }
        $editorCommands = @{}

        foreach ($existingCommand in $psEditor.GetCommands()) {
            $editorCommands[$existingCommand.Name] = $existingCommand
        }
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            ByModule {
                $commands = $Module | GetCommandsFromModule
            }
            ByCommand {
                $commands = $Command | Get-Command -ErrorAction SilentlyContinue
            }
        }
        $attributeType = [Microsoft.PowerShell.EditorServices.Extensions.EditorCommandAttribute, Microsoft.PowerShell.EditorServices]
        foreach ($aCommand in $commands) {
            # Get the attribute from our command to get name info.
            $details = $aCommand.ScriptBlock.Attributes | Where-Object TypeId -eq $attributeType

            if ($details) {
                # TODO: Add module name to this?
                # Name: Expand-Expression becomes ExpandExpression
                if (-not $details.Name) { $details.Name = $aCommand.Name -replace '-' }

                # DisplayName: Expand-Expression becomes Expand Expression
                if (-not $details.DisplayName) { $details.DisplayName = $aCommand.Name -replace '-', ' ' }

                # If the editor command is already loaded skip unless force is specified.
                if ($editorCommands.ContainsKey($details.Name)) {
                    if ($Force.IsPresent) {
                        $null = $psEditor.UnregisterCommand($details.Name)
                    } else {
                        $PSCmdlet.WriteVerbose($Strings.EditorCommandExists -f $details.Name)
                        continue
                    }
                }
                # Check for a context parameter.
                $contextParameter = $aCommand.Parameters.Values |
                    Where-Object ParameterType -eq ([Microsoft.PowerShell.EditorServices.Extensions.EditorContext, Microsoft.PowerShell.EditorServices])

                # If one is found then add a named argument. Otherwise call the command directly.
                if ($contextParameter) {
                    $sbText = '{0} -{1} $args[0]' -f $aCommand.Name, $contextParameter.Name
                    $scriptBlock = [scriptblock]::Create($sbText)
                } else {
                    $scriptBlock = [scriptblock]::Create($aCommand.Name)
                }

                $editorCommand = [Microsoft.PowerShell.EditorServices.Extensions.EditorCommand, Microsoft.PowerShell.EditorServices]::new(
                    <# commandName:    #> $details.Name,
                    <# displayName:    #> $details.DisplayName,
                    <# suppressOutput: #> $details.SuppressOutput,
                    <# scriptBlock:    #> $scriptBlock)

                $PSCmdlet.WriteVerbose($Strings.EditorCommandImporting -f $details.Name)
                $null = $psEditor.RegisterCommand($editorCommand)

                if ($PassThru.IsPresent -and $editorCommand) {
                    $editorCommand # yield
                }
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -ge 5) {
    Register-ArgumentCompleter -CommandName Import-EditorCommand -ParameterName Module -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        (Get-Module).Name -like ($wordToComplete + '*') | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($PSItem, $PSItem, 'ParameterValue', $PSItem)
        }
    }
    Register-ArgumentCompleter -CommandName Import-EditorCommand -ParameterName Command -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        (Get-Command -ListImported).Name -like ($wordToComplete + '*') | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($PSItem, $PSItem, 'ParameterValue', $PSItem)
        }
    }
}

# SIG # Begin signature block
# MIInvgYJKoZIhvcNAQcCoIInrzCCJ6sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBCo/8RxkJRpjfH
# tv88INxNRrHwrLnOrzrSY5Y80TZvAqCCDYUwggYDMIID66ADAgECAhMzAAACU+OD
# 3pbexW7MAAAAAAJTMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMzAwWhcNMjIwOTAxMTgzMzAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDLhxHwq3OhH+4J+SX4qS/VQG8HybccH7tnG+BUqrXubfGuDFYPZ29uCuHfQlO1
# lygLgMpJ4Geh6/6poQ5VkDKfVssn6aA1PCzIh8iOPMQ9Mju3sLF9Sn+Pzuaie4BN
# rp0MuZLDEXgVYx2WNjmzqcxC7dY9SC3znOh5qUy2vnmWygC7b9kj0d3JrGtjc5q5
# 0WfV3WLXAQHkeRROsJFBZfXFGoSvRljFFUAjU/zdhP92P+1JiRRRikVy/sqIhMDY
# +7tVdzlE2fwnKOv9LShgKeyEevgMl0B1Fq7E2YeBZKF6KlhmYi9CE1350cnTUoU4
# YpQSnZo0YAnaenREDLfFGKTdAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUlZpLWIccXoxessA/DRbe26glhEMw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzQ2NzU5ODAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AKVY+yKcJVVxf9W2vNkL5ufjOpqcvVOOOdVyjy1dmsO4O8khWhqrecdVZp09adOZ
# 8kcMtQ0U+oKx484Jg11cc4Ck0FyOBnp+YIFbOxYCqzaqMcaRAgy48n1tbz/EFYiF
# zJmMiGnlgWFCStONPvQOBD2y/Ej3qBRnGy9EZS1EDlRN/8l5Rs3HX2lZhd9WuukR
# bUk83U99TPJyo12cU0Mb3n1HJv/JZpwSyqb3O0o4HExVJSkwN1m42fSVIVtXVVSa
# YZiVpv32GoD/dyAS/gyplfR6FI3RnCOomzlycSqoz0zBCPFiCMhVhQ6qn+J0GhgR
# BJvGKizw+5lTfnBFoqKZJDROz+uGDl9tw6JvnVqAZKGrWv/CsYaegaPePFrAVSxA
# yUwOFTkAqtNC8uAee+rv2V5xLw8FfpKJ5yKiMKnCKrIaFQDr5AZ7f2ejGGDf+8Tz
# OiK1AgBvOW3iTEEa/at8Z4+s1CmnEAkAi0cLjB72CJedU1LAswdOCWM2MDIZVo9j
# 0T74OkJLTjPd3WNEyw0rBXTyhlbYQsYt7ElT2l2TTlF5EmpVixGtj4ChNjWoKr9y
# TAqtadd2Ym5FNB792GzwNwa631BPCgBJmcRpFKXt0VEQq7UXVNYBiBRd+x4yvjqq
# 5aF7XC5nXCgjbCk7IXwmOphNuNDNiRq83Ejjnc7mxrJGMIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGY8wghmLAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAJT44Pelt7FbswAAAAA
# AlMwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPZ8
# NEzZjgCyML6sujLTPgimQGyG4V5qvxM+l9MjZcEpMEIGCisGAQQBgjcCAQwxNDAy
# oBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20wDQYJKoZIhvcNAQEBBQAEggEAWchczL6YHGYTJQUXEsDF/LguKIP6e/VZBXIB
# LMn1pVLlakI87IHwY8+er2bSQafGVZPVG92coRtLszdsDgh8iZzHB2V4IOJIKzxv
# vcpPcmXKp+5FxwBT9L0XK5AOMVW2A7Q41/6tI2FOjESgaIF7ej5bNx8YjcuFeYKq
# rzaLE74Dw339XcRKvfnVVd5RVQwqAdGtn2xg4TjPsCeB37zPZuJguwxhr3jbrx7e
# M8VLJOmMbqTay3R67SqVCPLezv2kwGKeVgTNROLcMgMT6UI1nC9EQLeQF+r7FUjE
# ioYryc/vPoB0e7KDYkyRKQJXd+Q7FfEfyY6mXiABrC47fDmG+qGCFxkwghcVBgor
# BgEEAYI3AwMBMYIXBTCCFwEGCSqGSIb3DQEHAqCCFvIwghbuAgEDMQ8wDQYJYIZI
# AWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYBBAGE
# WQoDATAxMA0GCWCGSAFlAwQCAQUABCA03dZFEDhIpIbIPmavn6k7/yVnBZTSVExh
# TaUd4MhSNAIGYheY+DLsGBMyMDIyMDQxODIyMjEyNy4yOTlaMASAAgH0oIHYpIHV
# MIHSMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsT
# HVRoYWxlcyBUU1MgRVNOOkZDNDEtNEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIRaDCCBxQwggT8oAMCAQICEzMAAAGOWdtG
# AKgQlMwAAQAAAY4wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwHhcNMjExMDI4MTkyNzQ1WhcNMjMwMTI2MTkyNzQ1WjCB0jELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9z
# b2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFsZXMg
# VFNTIEVTTjpGQzQxLTRCRDQtRDIyMDElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKoj
# AqujjMy2ucK7XH+wX/X9Vl1vZKamzgc4Dyb2hi62Ru7cIMKk0Vn9RZI6SSgThuUD
# yEcu2uiBVQMtFvrQWhV+CJ+A2wX9rRrm8mPfoUVPoUXsDyR+QmDr6T4e+xXxjOt/
# jpcEV6eWBEerQtFkSp95q8lqbeAsAA7hr9Cw9kI54YYLUVYnbIg55/fmi4zLjWqV
# IbLRqgq+yXEGbdGaz1B1v06kycpnlNXqoDaKxG03nelEMi2k1QJoVzUFwwoX2udu
# p1u0UOy+LV1/S3NKILogkpD5buXazQOjTPM/lF0DgB8VXyEF5ovmN0ldoa9nXMW8
# vZ5U82L3+GQ6+VqXMLe7U3USCYm1x7F1jCq5js4pYhg06C8d+Gv3LWRODTi55ayk
# FjfWRvjsec0WqytRIUoWoTNLkDYW+gSY6d/nNHjczBSdqi2ag6dv92JeUPuJPjAx
# y04qT+lQXcXHVX3eJoK1U8d2nzuSjX4DJ4Bhn4UmsBq2kVtvBIayzrKZiMYovdhO
# 7453CdrXI4SwowQK1aT4d3GRuYN2VcuYogGqA2rMKTYJzBQCuVJ9a3ivjBYT4vYj
# J71D8LUwwybeWBA+QwE95gVMaeUB97e0YWcACTS1i7aU3hhe7m/NbEimL9mq3Wsw
# HvVy0tdLVdqDj63J4hic5V1u1T78akDcXvJQgwNtAgMBAAGjggE2MIIBMjAdBgNV
# HQ4EFgQU7EH5M/YE+ODf+RvLzR2snqfmleQwHwYDVR0jBBgwFoAUn6cVXQBeYl2D
# 9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUy
# MDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUE
# DDAKBggrBgEFBQcDCDANBgkqhkiG9w0BAQsFAAOCAgEANVCvccyHk5SoUmy59G3p
# EeYGIemwdV0KZbgqggNebJGd+1IpWhScPPhpJQy85TYUj9pjojs1cgqvJJKap31H
# NNWWgXs0MYO+6nr49ojMoN/WCX3ogiIcWDhboMHqWKzzvDJQf6Lnv1YSIg29XjWE
# 5T0pr96WpbILZK29KKNBdLlpl+BEFRikaNFBDbWXrVSMWtCfQ6VHY0Fj3hIfXBDP
# kYBNuucOVgFW/ljcdIloheIk2wpq1mlRDl/dnTagZvW09VO5xsDeQsoKTQIBGmJ6
# 0zMdTeAI8TmwAgzeQ3bxpbvztA3zFlXOqpOoigxQulqV0EpDJa5VyCPzYaftPp6F
# OrXxKRyi7e32JvaH+Yv0KJnAsKP3pIjgo2JLad/d6L6AtTtri7Wy5zFZROa2gSwT
# UmyDWekC8YgONZV51VSyMw4oVC/DFPQjLxuLHW4ZNhV/M767D+T3gSMNX2npzGbs
# 9Fd1FwrVOTpMeX5oqFooi2UgotZY2sV/gRMEIopwovrxOfW02CORW7kfLQ7hi4lb
# vyUqVRV681jD9ip9dbAiwBhI6iWFJjtbUWNvSnex3CI9p4kgdD0Dgo2JZwp8sJw4
# p6ktQl70bIrI1ZUtUaeE5rpLPqRsYjBsxefM3G/oaBSsjjbi92/rYMUwM97BdwVV
# /bpPTORfjhKHsi8hny3pDQIwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAA
# AAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBB
# dXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YB
# f2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKD
# RLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus
# 9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTj
# kY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56
# KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39
# IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHo
# vwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJo
# LhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMh
# XV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREd
# cu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEA
# AaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqn
# Uv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnp
# cjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0w
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEw
# CwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/o
# olxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNy
# b3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
# MjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+
# TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2Y
# urYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4
# U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJ
# w7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb
# 30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ
# /gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGO
# WhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFE
# fnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJ
# jXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rR
# nj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUz
# WLOhcGbyoYIC1zCCAkACAQEwggEAoYHYpIHVMIHSMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBP
# cGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkZDNDEt
# NEJENC1EMjIwMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQA9YivqT04R6oKWucbD5omK7llbjKCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUAAgUA5gfz
# zzAiGA8yMDIyMDQxODIyMjcyN1oYDzIwMjIwNDE5MjIyNzI3WjB3MD0GCisGAQQB
# hFkKBAExLzAtMAoCBQDmB/PPAgEAMAoCAQACAgueAgH/MAcCAQACAhHeMAoCBQDm
# CUVPAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAVOJdD5HwdYKz1aaxJlZ6
# I2YLSoGL9DxHp0ADUm5kRJ3PwdpYKMWZSTxnJFLv0sjCY8RbwbiMufjQ5OVRyQ6c
# 0j0JU5pZiZu7rtharbz3UCWirJYIA826cePUmZZoth+MPkP9FZL5OEdGF+ghstmL
# tAyVV308n00VHSXnpNexyu4xggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAY5Z20YAqBCUzAABAAABjjANBglghkgBZQMEAgEF
# AKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCDe+1FpXv3rrTvzJ+Oz28G8ZaaPxBjv3LpKFtVPCtwUNjCB+gYLKoZIhvcNAQkQ
# Ai8xgeowgecwgeQwgb0EIL0FjyE74oGlLlefn/5VrNwV2cCf5dZn/snpbuZ15sQl
# MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAGOWdtG
# AKgQlMwAAQAAAY4wIgQgdOe//9ONLXlbGpZ9KB9h0T1ypCqiDi1uWUa5fSLwMIIw
# DQYJKoZIhvcNAQELBQAEggIANVMFZaDa0uNTlPb+di14TN+7hAM37dLKpstpkePW
# LqELNYwmeeNusvxTvSzfKzkkR/61hJlvW0YpsjDuuKz454MQbIflSaeL0IxJhMSD
# hSAamhN3tvKjdeY5klYDM0g7FNd0A0dhJyhY80gpzjNhzXJYXxRW7JH8aF4IDTQK
# aHf/ZydZRbPhCUBPcKmhsmX8v8CdH4WT6/AKnDyucbmQKmuiS6zRRwhFiwkHqj26
# wzMK+uIye1E3D2OxTMHs4sxHvD0Vkz39GYSHY9zB/NbAady8txUt2Mf0zjmkpe0s
# wZ0/MnhkG0Ab+l1fp3VXhV5PYRkvR+q6NwGcDFycdHP5bHZnFo4pxOWLIBIRg7FV
# KbT7MdfMBkzz0sKPI3Y2vwg/6cDgfGrCdUS5Yu3GWKMFklJ689FZnWHEDIuKte03
# PIsER9PbCbDkyymWyApltnXd8/BCD9Tv1tzQBmoALFjUnS67NS5hPCokk1ivAmX4
# YNEBg3gNuCizKlrxMgcdMgeXI2q3/MLS9IQ5N11e2brD//7Z/3Gr+oaCt0fzqIWJ
# uBYIhBXff9NB2YoFKvqGATgYPFVorZZHf+ITktB+8o2RqaajTumSesdfuy5Nzq/n
# 9YE2w6qiKVju5uQ8o8aPzWmzgDRcKCnNicx7BNydX/5nmkq4M2I9KB3dBLf9sE/0
# x48=
# SIG # End signature block
