
# ======================================================================================
# ======= [SMS Module Header] [_sms_module_header.ps1] [2018-04-20 15:42:26 UTC] =======
# ======================================================================================
<#
.SYNOPSIS
Sash's Management System (SMS)

.DESCRIPTION
This allow to manage AWS Instances as an PS objects. You can use methods, properties and commandlets based on it.

.PARAMETER sms
Parameter description

.PARAMETER Name
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>

# Version 0.6.7

# ==========================================================================================
# ======= [Logging/Remote logging support logic] [log.ps1] [2018-04-20 15:42:26 UTC] =======
# ==========================================================================================
function log {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$msg,
        [parameter(Mandatory=$false, position=1)][ValidateSet('rl', 'remotelog', 'ok', 'info', 'warning', 'error', 'exception', 'fatal', 'semi')][string]$what = "info"
    )

    # 'rl', 'remotelog' - Just remote logging without showing on the screen or in the local log file
    if($what -eq 'rl') {$what = 'remotelog'}
    # If do not just Remote Log then common logging first
    if($what -ne 'remotelog') {toLog $msg $what}

    $dat = (Get-Date).ToUniversalTime()
    $datStr = $dat.ToString('yyyy-MM-dd HH:mm:ss.ffff')
    if(!$pleaseDontDoRemoteLogging -and $remoteLogData -ne $null) {
        $remoteLogData.Add("[$datStr] [$($what.ToUpper())] $msg")
    }
    if(!$pleaseDontDoRemoteLogging -and $remoteLogData -ne $null -and $remoteLogData.Count -gt 0) {
        if(([math]::Abs(((Get-Date) - (Get-Variable remoteLogLastSave -ValueOnly)).TotalSeconds)) -ge (Get-Variable remoteLogSaveInterval -ValueOnly)) {
            Set-Variable -Name remoteLogLastSave -Value (Get-Date) -Scope Global -Option AllScope -Force
            Save-SMSRemoteLog;
        }
    }
}

function ReadForGetSmsRemoteLog {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$toProcess,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][uint32]$idx
    )

    $content = '';

    if(![string]::IsNullOrEmpty($region)) {$reg = $region} else {$reg = GetJustRegions (Get-SMSVar 'AutoRegions') 'aws'}
    $reg | %{
        $rg = $_
        $from = makeUrlPath "core.team.$rg" (Get-Variable "$($SMSPrefix)smsFolderName" -ValueOnly)
        $files = Read-S3 (makeUrlPath $from @((Get-SMSVar 'logFolderName'))) -Region $rg
        if($files -ne $null) {
            $content += "-------------------[$rg] found [$($files.Count)] ----------------------`r`n";
            foreach($f in ($files | ?{$_.Key -like "*[$($toProcess.ToLower())]*"} | Sort LastModified)) {
                if(($f.Key.Split('[]', [System.StringSplitOptions]::RemoveEmptyEntries)[$idx]) -eq $toProcess) {
                    $content += Get-S3 -s3Path $(makeUrlPath $f.BucketName $f.Key) -decompress $true -asString $true -Region $rg
                    $content += "`r`n" # Becuase there is no 13, 10 after an each last line
                }
            }
            $content += "-----------------------------------------------------------------------`r`n";
        }
    }
    $content;
}
function Get-SMSRemoteLog {
    [CmdletBinding(DefaultParameterSetName='id')]
    param(
        [parameter(ParameterSetName='id', Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][string[]]$remoteId,
        [parameter(ParameterSetName='date', Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][DateTime]$dateFrom,
        [parameter(ParameterSetName='date', Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()][DateTime]$dateTo,
        [parameter(ParameterSetName='computer', Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][string[]]$computer,
        [parameter(ParameterSetName='user', Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][string[]]$user,
        [parameter(ParameterSetName='userdns', Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][string[]]$userdns,
        [parameter(ParameterSetName='region', Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][string[]]$region,
        [parameter(Mandatory=$false)][string]$saveToFileName,
        [parameter(Mandatory=$false)][switch]$withClearLogMessages,
        [parameter(Mandatory=$false)][switch]$withSaveLogMessages,
        [parameter(Mandatory=$false)][switch]$withInvokeThisCodeMessages,
        [parameter(Mandatory=$false)][string]$regionToFindLogsIn # If defined then all searches will be performed just in this region
    )
    # --- Code ---
    # $($SMSPrefix)smsFolderPath/Logging/<GUID>/[<DateTime UTC>][<ComputerName>][<UserName>][<UserDnsDomain>][<Region>]
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {
            switch($PSCmdlet.ParameterSetName) {
                'id' {$toProcess = $remoteId; break;}
                'date' {$toProcess = @{From=$dateFrom; To=$dateTo}; break;}
                'computer' {$toProcess = $computer; break;}
                'user' {$toProcess = $user; break;}
                'userdns' {$toProcess = $userdns; break;}
            }
        }
    }
    end {
        $content = '';
        switch($PSCmdlet.ParameterSetName) {
            'id' {
                foreach($p in $toProcess){
                    if(![string]::IsNullOrEmpty($regionToFindLogsIn)) {$reg = $regionToFindLogsIn} else {$reg = GetJustRegions (Get-SMSVar 'AutoRegions') 'aws'}
                    $reg | %{
                        $rg = $_
                        $from = makeUrlPath "core.team.$rg" (Get-Variable "$($SMSPrefix)smsFolderName" -ValueOnly)
                        $files = Read-S3 (makeUrlPath $from @((Get-SMSVar 'logFolderName'), $p)) -Region $rg
                        if($files -ne $null) {
                            $content += "-------------------[$rg] found [$($files.Count)] ----------------------`r`n";
                            foreach($f in ($files | Sort LastModified)) {
                                $content += Get-S3 -s3Path (makeUrlPath $f.BucketName $f.Key) -decompress $true -asString $true -Region $rg
                                $content += "`r`n" # Becuase there is no 13, 10 after an each last line
                            }
                            $content += "-----------------------------------------------------------------------`r`n";
                        }
                    }
                }
                break;
            }
            'date' {
                if(![string]::IsNullOrEmpty($regionToFindLogsIn)) {$reg = $regionToFindLogsIn} else {$reg = GetJustRegions (Get-SMSVar 'AutoRegions') 'aws'}
                $reg | %{
                    $rg = $_
                    $from = makeUrlPath "core.team.$rg" (Get-Variable "$($SMSPrefix)smsFolderName" -ValueOnly)
                    $files = Read-S3 (makeUrlPath $from @((Get-SMSVar 'logFolderName'))) -Region $rg
                    if($files -ne $null) {
                        $content += "-------------------[$rg] found [$($files.Count)] ----------------------`r`n";
                        foreach($f in ($files | Sort LastModified)) {
                            $fDate = [DateTime]::Parse($f.Key.Split('[]',[System.StringSplitOptions]::RemoveEmptyEntries)[1].Replace('~', ':'));
                            if($fDate -ge $toProcess.From -and $fDate -le $toProcess.To) {
                                $content += Get-S3 -s3Path (makeUrlPath $f.BucketName $f.Key) -decompress $true -asString $true -Region $rg
                                $content += "`r`n" # Becuase there is no 13, 10 after an each last line
                            }
                        }
                        $content += "-----------------------------------------------------------------------`r`n";
                    }
                }
                break;
            }
            'computer' {
                $content = ReadForGetSmsRemoteLog $toProcess 2
                break;
            }
            'user' {
                $content = ReadForGetSmsRemoteLog $toProcess 3
                break;
            }
            'userdns' {
                $content = ReadForGetSmsRemoteLog $toProcess 4
                break;
            }
            'region' {
                $content = ReadForGetSmsRemoteLog $toProcess 5
                break;
            }
        }
        $content = $content.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)
        if(!($withClearLogMessages.IsPresent)) {$content = $content | ? {$_ -notlike "*$($remoteLogClearedMsg)*"}}
        if(!($withSaveLogMessages.IsPresent)) {$content = $content | ? {$_ -notlike '*Save-SMSStorageItem -Strings $remoteLogData.ToArray() -Location (createRemoteLogPath $remoteLogId.Guid)*'}}
        if(!($withInvokeThisCodeMessages.IsPresent)) {
            $content = $content | ? {
                $_ -notlike '*Code invocation successfully' -and
                $_ -notlike '*Trying to invoke AWS Code...' -and
                $_ -notlike '*Invoke-ThisCode: script*' -and
                $_ -notlike '*Code execution time*' -and
                $_ -notlike '*Code invocation error*'
            }
        }
        $content = $content | Out-String

        if(![string]::IsNullOrEmpty($saveToFileName)) {
            if(!(Test-Path -LiteralPath (Split-Path $saveToFileName) )) {md (Split-Path $saveToFileName)}
            $content | Out-File $saveToFileName -Force -Encoding utf8
        }
        else {$content}
    }
    # --- Code ---
}

function ClearSMSRemoteLog {
    if(!$pleaseDontDoRemoteLogging -and $remoteLogData -ne $null -and $remoteLogData.Count -gt 0) {
        $remoteLogData.Clear();
        $remoteLogData.Add("[$((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.ffff'))] [SEMI] $($remoteLogClearedMsg)")
    }
}

function Save-SMSRemoteLog {
    # --- Param empty ---
    # --- Code ---
    try {
        if(!$pleaseDontDoRemoteLogging -and $remoteLogData -ne $null -and $remoteLogData.Count -gt 0) {
            # $($SMSPrefix)smsFolderPath/Logging/<GUID>/[<DateTime UTC>][<ComputerName>][<UserName>][<UserDnsDomain>][<Region>]
            Invoke-ThisCode -scriptBlk {Save-SMSStorageItem -Strings $remoteLogData.ToArray() -Location (createRemoteLogPath $remoteLogId.Guid)}
        }
    }
    catch {log "Error storying Remote log [$($_.ToString())]. Remote Id: [$remoteLogId]" 'error'}
    finally {
        ClearSMSRemoteLog;
    }
    # --- Code ---
}

function Get-SMSRemoteLogSetting {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('pleaseDontDoRemoteLogging', 'remoteLogSaveInterval', 'remoteLogLastSave', 'remoteLogId')]
        [string]$name
    )
    # --- Code ---
    Get-Variable $name -ValueOnly
    # --- Code ---
}

function Set-SMSRemoteLogSetting {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('pleaseDontDoRemoteLogging', 'remoteLogSaveInterval')]
        [string]$name,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$value
    )
    # --- Code ---
    switch($name) {
        'pleaseDontDoRemoteLogging' {
            Set-Variable $name ([bool]::Parse($value)) -Scope Global -Option AllScope -Force
            break;
        }
        'remoteLogSaveInterval' {
            Set-Variable $name ([uint32]::Parse($value)) -Scope Global -Option AllScope -Force
            break;
        }
    }
    # --- Code ---
}

function FirstPreparationOfRemoteLogData {
    $remoteLogData.Add("[$((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.ffff'))] [SEMI] Remote Log Started");
    $remoteLogData.Add('SMS variables:')
    $remoteLogData.Add('-------------------');
    $remoteLogData.Add((dir "variable:$SMSPrefix*" | ft Name, Value -auto | Out-String))
    $remoteLogData.Add('-------------------')
    $remoteLogData.Add("Computername: [$($env:COMPUTERNAME)]")
    $remoteLogData.Add("UserDnsDomain: [$($env:USERDNSDOMAIN)]")
    $remoteLogData.Add("UserName: [$($env:USERNAME)]")
    $remoteLogData.Add('-------------------')
}

# =======================================================================================
# ======= [Work with Autoregions support] [autoreg.ps1] [2018-04-20 15:42:26 UTC] =======
# =======================================================================================
function Get-SMSAutoRegions {
    # --- No params ---
    # --- Code ---
    Get-SMSVar 'AutoRegions'
    # --- Code ---
}

function Set-SMSAutoRegions {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string[]]$autoRegions
    )
    # --- Code ---
    # Default region first
    $autoRegions = $autoRegions | ? {$_ -ne (Get-SMSVar 'Region')}
    $autoRegions = @((Get-SMSVar 'Region')) + $autoRegions
    Set-SMSVar 'AutoRegions' ($autoRegions | Select -Unique)
    # --- Code ---
}

function Invoke-ThisCodeByAutoregions {
    [CmdletBinding(DefaultParameterSetName='Str')]
    param(
        [parameter(ParameterSetName='Str', Mandatory=$true)][ValidateNotNullOrEmpty()][string]$scriptStr,
        [parameter(ParameterSetName='Arr', Mandatory=$true)][ValidateNotNullOrEmpty()][string[]]$scriptArr,
        [parameter(ParameterSetName='Code', Mandatory=$true)][ValidateNotNullOrEmpty()][scriptblock]$scriptBlk,
        [parameter(Mandatory=$false)][uint32]$trysCnt,
        [parameter(Mandatory=$false)][uint32]$secAprox = 180,
        [parameter(Mandatory=$false)][uint32]$pause = 5,
        [parameter(Mandatory=$false)][string[]]$stopIfErrorStartsWith=@(),
        [parameter(Mandatory=$false)][string[]]$stopIfErrorEndsWith=@(),
        [parameter(Mandatory=$false)][Hashtable[]]$stopIfErrorStartsOrEndsWith=@(), # @{starts=''; ends='';}
        [parameter(Mandatory=$false)][Hashtable[]]$stopIfErrorStartsAndEndsWith=@(), # @{starts=''; ends='';}
        [parameter(Mandatory=$false)][switch]$doNotInsertSpecialCode,
        [parameter(Mandatory=$false)][switch]$doNotIgnoreEmptyResult,
        [parameter(Mandatory=$false)][switch]$doNotContinueWhenFound,
        [parameter(Mandatory=$false)][ValidateSet('aws', 'vmw')][string]$provider='aws'
    )
    # --- Code ---
    <# ... #>
    # --- Code ---
}

# ===========================================================================
# ======= [Functions Toolset] [support.ps1] [2018-04-20 15:42:26 UTC] =======
# ===========================================================================
<# ... #>
# =====================================================================
# ======= [Tagging support] [tag.ps1] [2018-04-20 15:42:26 UTC] =======
# =====================================================================
function Get-TagFromTags {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$false, position=0)]$tags, # [Amazon.EC2.Model.Tag[]]
        [parameter(Mandatory=$false, position=1)][string]$key
    )
    # --- Code ---
    if($tags -ne $null) {
        if(![string]::IsNullOrEmpty($key)) {
            if($tags.Count -gt 0) {
                foreach($t in $tags) {
                    if($t.Key -eq $key) {
                        return $t.Value;
                    }
                }
            }
        }
        else {
            # Return all tags
            $res = New-Object PSObject
            foreach($t in $tags) {
                $res | Add-Member -MemberType NoteProperty -Name $t.Key -Value $t.Value;
            }
            $res;
        }
    }
    else {$null;}
    # --- Code ---
}

function GetSMSTag {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [string]$Name = $null,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | % {$_.GetTag($Name);}
}

function Get-SMSTag {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [string]$Name = $null,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += GetSMSTag $_ $Name
        }
        else {
            $res = GetSMSTag $sms $Name
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function AddSMSTag {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]
        [hashtable]$Tag,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | % {$_.AddTag($Tag);}
}

function Add-SMSTag {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]
        [hashtable]$Tag,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            AddSMSTag $_ $Tag
            $res += $_
        }
        else {
            AddSMSTag $sms $Tag
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function RemoveSMSTag {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [hashtable]$Tag,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | % {$_.DelTag($Tag);}
}

function Remove-SMSTag {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [hashtable]$Tag,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            RemoveSMSTag $_ $Tag
            $res += $_
        }
        else {
            RemoveSMSTag $sms $Tag
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function RemoveSMSTagByName {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [string]$Name,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | % {$_.DelTagByName($Name);}
}

function Remove-SMSTagByName {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({($_.author -ne $null -and $_.author -eq 'alex') -or ($_.__internal -ne $null -and $_.__internal.author -eq 'alex')})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [string]$Name,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            RemoveSMSTagByName $_ $Name
            $res += $_
        }
        else {
            RemoveSMSTagByName $sms $Name
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

# =================================================================================================================
# ======= [Set of AWS __internal object methods] [aws_backend_object_methods.ps1] [2018-04-20 15:42:26 UTC] =======
# =================================================================================================================
[scriptblock]$sbGetSubnet = {
    param(
        [parameter(Mandatory=$false)]$subnetId
    )

    if(![string]::IsNullOrEmpty($subnetId)) {Invoke-ThisCode -ScriptBlk {Get-EC2Subnet $subnetId -Region $this.region}}
    else {$null}
}

[scriptblock]$sbGetTag = {
    param([Amazon.EC2.Model.Tag[]]$tags, [string]$key)

    if($tags -ne $null) {
        if(![string]::IsNullOrEmpty($key)) {
            if($tags.Count -gt 0) {
                foreach($t in $tags) {
                    if($t.Key -eq $key) {
                        return $t.Value;
                    }
                }
            }
        }
        else {
            # Returning all tags
            $res = @{}
            $tags | ForEach-Object {$res.Add($_.Key, $_.Value)}
            $res;
        }
    }
    else {$null;}
}

[scriptblock]$sbGetInstanceSpec = {
    param([parameter(Mandatory=$false)][string]$instanceType)

    $res = $this.imageSpec
    "$instanceType".Split('.') | ForEach-Object {$res = $res.$_}
    $res;
}

[scriptblock]$sbNetInterfacesToStr = {
    param(
        $netInterfaces
    )

    $str = ''; $delimiter = ', ';
    foreach($n in $netInterfaces) {
        if($n.provider -eq 'aws') {
            $str += $n.PrivateIpAddress
            $str += " ($($n.MacAddress))"
            $str += $delimiter
        }
        elseif($n.provider -eq 'vmw') {
            $str = ''
            $n.IpAddress | %{$str += $_ + ' '}
            $str += " ($($n.MacAddress))"
            $str += $delimiter
        }
    }
    $str.Trim($delimiter);
}

[scriptblock]$sbVolumesToStr = {
    param(
        $volumes
    )

    $str = ''; $delimiter = ', ';
    foreach($v in $volumes) {
        $letter = $this.GetTag($v.Tags, 'Letter');
        $size = $v.Size;
        $type = $this.GetTag( $v.Tags, 'Type');
        $company = $this.GetTag( $v.Tags, 'Company');
        if([string]::IsNullOrEmpty($letter)) {$letter = '<none>'}
        if([string]::IsNullOrEmpty($size)) {$size = '0'}
        if([string]::IsNullOrEmpty($type)) {$type = '<none>'}
        if([string]::IsNullOrEmpty($company)) {$company = '<none>'}
        $str += "$($letter): $($size)Gb Role: $type Company: $company ($($v.VolumeType))" + $delimiter
    }
    $str.Trim($delimiter);
}

[scriptblock]$sbStringsToString = {
    param(
        [parameter(Mandatory=$true)][string[]] $strings,
        [parameter(Mandatory=$false)][string] $separator = ', '
    )

    if(![string]::IsInterned($strings)) {
        [string]$res = [string]::Empty;
        foreach ($s in $strings)
        {
            $res = $res + $s +$separator;
        }
        $res.Trim($separator);
    }
    else {$null}
}

[scriptblock]$sbDomainFromFqdn = {
    param(
        [parameter(Mandatory=$false)][string]$fqdn
    )

    if(![string]::IsNullOrEmpty($fqdn)) {
        $qqq = $fqdn.Split('.') | Where-Object {![string]::IsNullOrEmpty($_)};
        for($i=1; $i -lt $qqq.Count; $i++) {$domain += "$($qqq[$i])." }
        $domain = $domain.TrimEnd('.');
        $domain;
    }
    else {[string]::Empty;}
}

[scriptblock]$sbDomainShortFromFqdn = {
    param(
        [parameter(Mandatory=$false)][string]$fqdn
    )

    if(![string]::IsNullOrEmpty($fqdn)) {
        $qqq = $fqdn.Split('.') | Where-Object {![string]::IsNullOrEmpty($_)};
        if($qqq.Count -gt 2) {$qqq[1];}
        else {[string]::Empty;}
    }
    else {[string]::Empty;}
}

[scriptblock]$sbVpcToStr = {
    param(
        [parameter(Mandatory=$false)]$vpcId
    )

    if(![string]::IsNullOrEmpty($vpcId)) {
        $vpc = Invoke-ThisCode -ScriptBlk {Get-Ec2Vpc -VpcId $vpcId -Region $this.region}
        if($vpc -ne $null) {"Name: [$($this.GetTag($vpc.Tags, 'Name'))] Id: [$($vpcId)] Cidr: [$($vpc.CidrBlock)]"}
        else {"<none>"}
    }
    else {"<none>"}
}

[scriptblock]$sbAddTag = {
    param(
        [parameter(Mandatory=$true)][string]$resourceId,
        [parameter(Mandatory=$true)][hashtable]$tags
    )

    Write-Verbose "Adding Tag(s) to the [$resourceId]"
    if($tags -ne $null -and $tags.Count -gt 0) {
        $tagArr = @();
        foreach($k in $tags.Keys) {
            $tag = New-Object Amazon.EC2.Model.Tag;
            $tag.key = $k;
            $tag.value = $tags[$k];
            $tagArr += $tag;
        }
        Invoke-ThisCode -ScriptBlk {New-EC2Tag -Region $this.region -Resource $resourceId -Tag $tagArr -Force}
    }
}

[scriptblock]$sbDelTag = {
    param(
        [parameter(Mandatory=$true)][string]$resourceId,
        [parameter(Mandatory=$true)][hashtable]$tags
    )

    if($tags -ne $null -and $tags.Count -gt 0) {
        $tagArr = @();
        foreach($k in $tags.Keys) {
            $tag = New-Object Amazon.EC2.Model.Tag;
            $tag.key = $k;
            $tag.value = $tags[$k];
            $tagArr += $tag;
        }
        Invoke-ThisCode -ScriptBlk {Remove-EC2Tag -Region $this.region -Resource $resourceId -Tag $tagArr -Force}
    }
}

[scriptblock]$sbDelTagByName = {
    param(
        [parameter(Mandatory=$true)][string]$resourceId,
        [parameter(Mandatory=$true)][Amazon.EC2.Model.Tag[]]$tags,
        [parameter(Mandatory=$true)][string[]]$tagNames
    )

    $tagArr = @{}
    if($tags -ne $null -and $tags.Count -gt 0 -and $tagNames -ne $null -and $tagNames.Count -gt 0) {
        foreach($t in $tags) {
            $tagNames | ForEach-Object {
                if($t.key -eq $_) {
                    $val = .$sbGetTag $tags $_;
                    if($val -ne $null) {$tagArr.Add($t.key, $val);}
                }
            }
        }
        if($tagArr.Keys.Count -gt 0) {.$sbDelTag $resourceId $tagArr;}
    }
}

[scriptblock]$sbGetProperDedicatedHost = {
    param(
        [parameter(Mandatory=$true, position=0)][string]$instanceType,
        [parameter(Mandatory=$true, position=1)][ValidateSet('FirstAvailable','MinRooms','MaxRooms','All')][string]$algorythm='FirstAvailable',
        [parameter(Mandatory=$false, position=2)][string]$zone
    )

    Write-Verbose 'Determine proper Dedicated Host'

    if([string]::IsNullOrEmpty($zone)) {$zone = Get-SMSVar 'Zone'}
    $region = Get-SMSRegionFromZone $zone

    $res = Invoke-ThisCode -ScriptBlk {Get-EC2Hosts -Region $region -Filter (New-SMSEc2Filter @{'availability-zone'=$zone})} | ? {
        $_.State -eq 'Available' -and
        $_.HostProperties.InstanceType -eq $instanceType -and
        $_.AvailableCapacity.AvailableInstanceCapacity[0].AvailableCapacity -gt 0
    }
    switch($algorythm) {
        'All' {$res; break;}
        'FirstAvailable' {$res | Select-Object -First 1; break;}
        'MinRooms' {
            if($res -ne $null) {
                $sort = @();
                $res | ForEach-Object {$sort += New-Object PSObject -Property @{HostId=$_.HostId; Rooms=$_.AvailableCapacity.AvailableInstanceCapacity[0].AvailableCapacity}}
                $sort = $sort | Sort-Object Rooms
                ($res | Where-Object {$_.HostId -eq $sort[0].HostId}) | Select-Object * -First 1;
            }
            else {$null}
            break;
        }
        'MaxRooms' {
            if($res -ne $null) {
                $sort = @();
                $res | ForEach-Object {$sort += New-Object PSObject -Property @{HostId=$_.HostId; Rooms=$_.AvailableCapacity.AvailableInstanceCapacity[0].AvailableCapacity}}
                $sort = $sort | Sort-Object Rooms -Descending
                ($res | Where-Object {$_.HostId -eq $sort[0].HostId}) | Select-Object * -First 1;
            }
            else {$null}
            break;
        }
    }
}

[scriptblock]$sbResizeInstance = {
    param(
        [parameter(Mandatory=$true)][ValidateScript({$_ -in $this.AvailableInstanceTypes})][string]$newInstanceType,
        [parameter(Mandatory=$false)][int]$timeout = 120
    )

    # Stop Instance
    $prev = $this.State.Name
    $this.StopInstance($timeout);
    # Resize the instance
    Invoke-ThisCode -ScriptBlk {Edit-EC2InstanceAttribute -Region $($this.region) -InstanceId $($this.instanceId) -InstanceType $newInstanceType -Force -Confirm:$false}
    $this.instanceType = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.InstanceType;
    # Start the instance
    if($prev -eq 'running') {$this.StartInstance($timeout)}
}

[scriptblock]$sbStopInstance = {
    param(
        [parameter(Mandatory=$false)][int]$timeout = 300,
        [parameter(Mandatory=$false)][switch]$forceStop
    )

    Write-Verbose "Trying to stop the instance [$($this.instanceId)]"
    if(!$forceStop.IsPresent) {$result = Invoke-ThisCode -ScriptBlk {Stop-EC2Instance -Region $this.region -InstanceId $this.instanceId -Force -Confirm:$false}}
    else {$result = Invoke-ThisCode -ScriptBlk {Stop-EC2Instance -Region $this.region -InstanceId $this.instanceId -Force -Confirm:$false -ForceStop:$true}}
    $st = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State.Name.Value;
    $cur = Get-Date
    $delta = (Get-Date) - $cur
    while($st -ne 'stopped' -and [math]::Abs($delta.TotalSeconds) -lt $timeout) {
        Write-Verbose "Waiting for the instance [$($this.instanceId)] stop..."
        $delta = (Get-Date) - $cur
        $st = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State.Name.Value; Start-Sleep 5;
    }
    if([math]::Abs($delta.TotalSeconds) -lt $timeout) {
        if($st -eq 'stopped') {
            Write-Verbose "Instance [$($this.instanceId)] stopped successfully"
            $this.State = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State;
        }
        else {
            throw "Error stopping the Instance [$($this.instanceId)]"
        }
    }
    else {throw "Timeout stopping the Instance [$($this.instanceId)]"}
}

[scriptblock]$sbTerminateInstance = {
    param(
        [parameter(Mandatory=$false)][int]$timeout = 120
    )

    Write-Verbose "Trying to terminate the instance [$($this.instanceId)]"
    # Result is used for just output supression
    $result = Invoke-ThisCode -ScriptBlk {Remove-EC2Instance -Region $this.region -InstanceId $this.instanceId -Force -Confirm:$false}
    $st = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State.Name.Value;
    $cur = Get-Date
    $delta = (Get-Date) - $cur
    while($st -ne 'terminated' -and [math]::Abs($delta.TotalSeconds) -lt $timeout) {
        Write-Verbose "Waiting for the instance [$($this.instanceId)] terminate..."
        $delta = (Get-Date) - $cur
        $st = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State.Name.Value; Start-Sleep 5;
    }
    if([math]::Abs($delta.TotalSeconds) -lt $timeout) {
        if($st -eq 'terminated') {
            Write-Verbose "Instance [$($this.instanceId)] terminated successfully"
            $this.State = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State;
        }
        else {
            throw "Error terminating the Instance [$($this.instanceId)]"
        }
    }
    else {throw "Timeout terminating the Instance [$($this.instanceId)]"}

}

[scriptblock]$sbStartInstance = {
    param(
        [parameter(Mandatory=$false)][int]$timeout = 120
    )

    Write-Verbose "Trying to stop the instance [$($this.instanceId)]"
    $result = Invoke-ThisCode -ScriptBlk {Start-EC2Instance -Region $this.region -InstanceId $this.instanceId}
    $st = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State.Name.Value;
    $cur = Get-Date
    $delta = (Get-Date) - $cur
    while($st -ne 'running' -and [math]::Abs($delta.TotalSeconds) -lt $timeout) {
        Write-Verbose "Waiting for the instance [$($this.instanceId)] start..."
        $delta = (Get-Date) - $cur
        $st = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State.Name.Value; Start-Sleep 5;
    }
    if([math]::Abs($delta.TotalSeconds) -lt $timeout) {
        if($st -eq 'running') {
            Write-Verbose "Instance [$($this.instanceId)] started successfully"
            $this.State = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.instanceId}).Instances.State;
        }
        else {
            throw "Error starting the Instance [$($this.instanceId)]"
        }
    }
    else {throw "Timeout starting the Instance [$($this.instanceId)]"}
}

[scriptblock]$sbInstanceSpecToStr = {
    param(
        $spec
    )

    $str = ''; $delimiter = ', ';
    $spec.keys | ForEach-Object { $str += "$($_) = [$($spec.$_)]" + $delimiter}
    $str.Trim($delimiter);
}

[scriptblock]$sbSubnetToStr = {
    param(
        [object[]]$subnet
    )

    $str = ''; $delimiter = ', ';
    foreach($s in $subnet) {
        $str += $s.CidrBlock + $delimiter;
    }
    $str.Trim($delimiter);
}

[scriptblock]$sbPlacementToStr = {
    param(
        $placement
    )

    if($placement.Tenancy -ne $null) {
        # AWS
        if($placement.Tenancy -eq 'default') {"Tenancy: [$($placement.Tenancy)]"}
        else {"HostId: [$($placement.HostId)] Tenancy: [$($placement.Tenancy)] Affinity: [$($placement.Affinity)]"}
    }
    elseif(![string]::IsNullOrEmpty($placement.Host) -and ![string]::IsNullOrEmpty($placement.Folder)) {
        # VMWare
        "Host: [$($placement.Host.Name)] Folder: [$($placement.Folder.Name)]"
    }
}

[scriptblock]$sbTagsToStr = {
    param(
        [parameter(Mandatory=$false, position=0)][Amazon.EC2.Model.Tag[]]$tags
    )

    $res = ''; $delimiter = ', ';
    if($tags -ne $null) {
        foreach($t in $tags) {
            $res += "$($t.Key)=$($t.Value)" + $delimiter
        }
        $res.Trim($delimiter);
    }
    else {$null}
}

[scriptblock]$sbSetTerminationProtection = {
    param(
        [parameter(Mandatory=$true)][object[]]$sms,
        [parameter(Mandatory=$false)]$terminationProtection = $true
    )

    Invoke-ThisCode -ScriptBlk {Edit-EC2InstanceAttribute -Region $this.region -InstanceId $sms.InstanceId -DisableApiTermination $terminationProtection -Force -Confirm:$false}
}

[scriptblock]$sbGetTerminationProtection = {
    param(
        [parameter(Mandatory=$true)][object[]]$sms
    )

    $ins = Invoke-ThisCode -ScriptBlk {Get-EC2InstanceAttribute -Region $this.region -InstanceId $sms.instanceId -Attribute DisableApiTermination}
    $ins | % {
        ($sms | ? {$_.InstanceId -eq $_.InstanceId}).instanceTerminationProtection = $_.DisableApiTermination
    }
}

[scriptblock]$sbGetDeleteDrivesOnTermination = {
    param(
        [parameter(Mandatory=$true)][object[]]$sms
    )


    $ins = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $sms.InstanceId}).Instances
    $ins | % {
        $res = $true;
        $bdm = $_.BlockDeviceMappings;
        for($i=0; $i -lt $bdm.Count; $i++) {
            if($bdm[$i].DeviceName.StartsWith('xvd')) {
                $res = $res -and $bdm[$i].Ebs.DeleteOnTermination;
            }
        }
        ($sms | ? {$_.InstanceId -eq $_.InstanceId}).drivesDeleteOnTermination = $res;
    }
}

[scriptblock]$sbSetDeleteDrivesOnTermination = {
    param(
        [parameter(Mandatory=$true)][object[]]$sms,
        [parameter(Mandatory=$false)]$deleteOnTermination = $true
    )

    $bdms = @()
    $ins = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $sms.InstanceId}).Instances
    $ins | % {
        $bdm = $_.BlockDeviceMappings;
        for($i=0; $i -lt $bdm.Count; $i++) {
            $spec = [Amazon.EC2.Model.InstanceBlockDeviceMappingSpecification]::new();
            $spec.DeviceName = $bdm[$i].DeviceName;
            $spec.Ebs = [Amazon.EC2.Model.EbsInstanceBlockDeviceSpecification]::new();
            $spec.Ebs.VolumeId = $bdm[$i].Ebs.VolumeId;
            $spec.Ebs.DeleteOnTermination = $deleteOnTermination;
            $bdms += $spec;
        }
    }
    if($bdms.Count -gt 0) {Invoke-ThisCode -ScriptBlk {Edit-EC2InstanceAttribute -Region $this.region -InstanceId $sms.InstanceId -BlockDeviceMapping $bdms -Force -Confirm:$false}}
}

[scriptblock]$sbRefresh = {
    param(
        [parameter(Mandatory=$false, position=0)][string]$instanceId
    )

    if(![string]::IsNullOrEmpty($instanceId)) {$ins = Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $instanceId}}
    else {$ins = Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region}}
    if($ins -ne $null) {
        $ins = $ins.Instances;
        $ins =  AddSMSNetInterfaceInfo (AddSMSVolumeInfo $ins)
        foreach($i in $ins) {NewSMSObject $i}
    }
    else {$null}
}

[scriptblock]$sbGetInstanceSpecification = {
    param(
        [parameter(Mandatory=$true)][ValidateScript({$_ -in $this.AvailableInstanceTypes})][string]$InstanceType
    )

    $this.GetInstanceSpec($InstanceType);
}

[scriptblock]$sbSetSG = {
    param(
        [parameter(Mandatory=$true)]$instanceId,
        [parameter(Mandatory=$true)][string[]]$sg
    )
    Invoke-ThisCode -ScriptBlk {Edit-EC2InstanceAttribute -Region $this.region -InstanceId $instanceId -Groups $sg}
}

[scriptblock]$sbSetPrivateIp = {
    param(
        [string]$ip
    )
    $net = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.region -InstanceId $this.InstanceId}).Instances.NetworkInterfaces[0];
    Invoke-ThisCode -ScriptBlk {Unregister-Ec2PrivateIpAddress -Region $this.region -NetworkInterfaceId $net.NetworkInterfaceId -PrivateIpAddress $net.PrivateIpAddress}
    if(![string]::IsNullOrEmpty($ip)) {Invoke-ThisCode -ScriptBlk {Register-Ec2PrivateIpAddress -Region $this.region -NetworkInterfaceId $net.NetworkInterfaceId -PrivateIpAddress $ip}}
}

[scriptblock]$sbGetAvailableInstanceTypes={$this.imageSpec.Keys | % {if($_ -ne 'custom') {$first = $_; $this.imageSpec."$_" | % {$this.imageSpec.$first.Keys | % {"$first.$_"}}}}}

$OSProperties = @(
    New-Object PSObject -Property @{Script='gwmi Win32_OperatingSystem'; Dest='OSInfo'}
    New-Object PSObject -Property @{Script='[System.Net.Dns]::gethostbyname($env:COMPUTERNAME).HostName'; Dest='OSComputerName'}
    New-Object PSObject -Property @{Script='[System.Net.Dns]::gethostbyname($env:COMPUTERNAME).AddressList'; Dest='OSIp'}
)

[scriptblock]$sbOSPropertiesWork = {
    param(
        [object[]]$sms,
        [string[]]$dest,
        [string]$code # This parameter mustn't be filled. This is a "Magic". I need to ensure $code has type of String
    )

    if($this.author -eq 'alex' -and $this.state.Name -eq 'running') {
        for($i=0; $i -lt $dest.Count; $i++) {
            $isFinal = ($i -eq $dest.Count-1)
            $script = ($OSProperties | ? {$_.Dest -eq $dest[$i]} | Select Script).Script
            $code += "Out-Result ($script) -Final:$" + $isFinal + "`r`n"
        }
        InvokeSMSInstanceScript -sms $sms -script $code
        $sms | % {
            $res = $_.LastScriptRun.Result
            if($res -ne $null) {
                if($res.Count -gt 0 ) {
                    for($i=0; $i -lt $dest.Count; $i++) {
                        $_.__internal."$($dest[$i])" = $res[$i]
                    }
                }
                elseif($dest.Count -eq 1) {
                    $_.__internal."$dest" = $res
                }
            }
            else {throw "sbOSPropertiesWork: Returned results Count [$($res.Count)] is less then expected [$($dest.Count)]"}
        }
    }
}

<# ... #>

# =================================================================================================================
# ======= [Set of VMW __internal object methods] [vmw_backend_object_methods.ps1] [2018-04-20 15:42:26 UTC] =======
# =================================================================================================================
[scriptblock]$sbConnectProperRegionVMW = {
    if((Test-SMSVMWareConnected -returnConnectedRegion) -ne $this.region) {Connect-SMSVMWare -region $this.region}
}

[scriptblock]$sbGetInstanceSpecVMW = {
    param(
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][uint32]$cpu,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][uint32]$cpuCore,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][float]$ghzMax,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][float]$ram
    )

    $imageSpecName = Find-NearestSutableInstanceSpec $this.imageSpec $cpu $cpuCore $ghzMax $ram
    (Convert-InstancesSpecificationToHashtable $this.imageSpec).$imageSpecName
}

[scriptblock]$sbGetInstanceTypeVMW = {
    param(
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][uint32]$cpu,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][uint32]$cpuCore,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][float]$ghzMax,
        [parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][float]$ram
    )

    Find-NearestSutableInstanceSpec $this.imageSpec $cpu $cpuCore $ghzMax $ram
}

# ----------------- Tagging start ---------------------
[scriptblock]$sbGetTagFromVMW = {
    param([string]$key)

    if($this.ConnectProperRegionVMW) {
        $tmp = Invoke-ThisCode -scriptBlk {Get-TagAssignment -Entity $($this.instanceName)} -provider 'vmw'
        if($tmp -ne $null) {
            $res = @{};
            ($tmp | Select tag).Tag | %{$res.Add($_.Category.Name , $_.Name)}
            if(![string]::IsNullOrEmpty($key)) {$res.$key}
            else {$res;}
        }
        else {$null}
    }
    else {$null}
}

[scriptblock]$sbGetTagVMW = {
    param([Hashtable]$tags, [string]$key)

    if($tags -ne $null) {
        if(![string]::IsNullOrEmpty($key)) {$tags.$key}
        else {$tags}
    }
    else {$null}
}

[scriptblock]$sbAddTagVMW= {
    param(
        [parameter(Mandatory=$true)][string]$resourceId, # does not used in VMWare because we need to use Name instead of Id
        [parameter(Mandatory=$true)][hashtable]$tags
    )

    if($this.ConnectProperRegionVMW) {
        if($tags -ne $null) {
            $descr = 'Autocreated by SMS AddTag method';
            foreach($t in $tags) {
                $tags.Keys | % {
                    $tagVal = '';
                    $tagCat = Invoke-ThisCode -scriptBlk {Get-TagCategory -Name $_} -provider 'vmw'
                    if($tagCat -eq $null) {
                        # Create new TagCategory
                        $tagCat = Invoke-ThisCode -scriptBlk {New-TagCategory -Name $_ -Cardinality Single -EntityType VirtualMachine -Description $descr} -provider 'vmw'
                    }
                    if($tagCat -ne $null) {
                        $tagVal = $this.GetTagFromVMW($_);
                        $tag = $null;
                        if([string]::IsNullOrEmpty($tagVal)) {
                            # Category exists. Tag exists? If it so then tag exists but doesn't assign to the Category
                            $tag = Invoke-ThisCode -scriptBlk {Get-Tag -Category $_ -Name $t.$_} -provider 'vmw'
                            if($tag -eq $null) {$tag = Invoke-ThisCode -scriptBlk {New-Tag -Name $t.$_ -Category $_ -Description $descr} -provider 'vmw'}
                            # Assign tag to the Instance
                            $tagAss = Invoke-ThisCode -scriptBlk {New-TagAssignment -Tag $tag -Entity $this.instanceName} -provider 'vmw'
                        }
                        else {
                            # Work with Existent tag (Category exists)
                            if($tagVal -ne $t.$_) {
                                # Tag is present and it has a different value
                                # do we already have a proper tag value?
                                $tag = Invoke-ThisCode -scriptBlk {Get-Tag -Category $_ -Name $t.$_} -provider 'vmw'
                                if($tag -ne $null) {
                                    # Yes we already have a proper tag belonging to the desired categoy but it not assigned to this VM
                                    $tagAss = Invoke-ThisCode -scriptBlk {Get-TagAssignment -Entity $($this.instanceName) -Category $_} -provider 'vmw'
                                    if($tagAss -ne $null) {$tmp = Invoke-ThisCode -scriptBlk {Remove-TagAssignment $tagAss -Confirm:$false} -provider 'vmw'}
                                    $tagAss = Invoke-ThisCode -scriptBlk {New-TagAssignment -Tag $tag -Entity $this.instanceName} -provider 'vmw'
                                }
                                else {
                                    # No, we have not proper tag belonging to the desired category
                                    $tag = Invoke-ThisCode -scriptBlk {New-Tag -Name $t.$_ -Category $_ -Description $descr} -provider 'vmw'
                                    $tagAss = Invoke-ThisCode -scriptBlk {New-TagAssignment -Tag $tag -Entity $this.instanceName} -provider 'vmw'
                                }
                            }
                            # Else tag exists and have the same value
                        }
                    }
                    else {throw "AddTagVMW: Can't create a Tag Category [$_]"}
                    # --- Changing VM Name if you pass the Tag "Name" ---
                    if($_ -eq 'Name') {
                        if($t.$_ -ne $this.instanceName) {
                            $ins = Get-VM $this.instanceName
                            $tmp = Set-VM -VM $ins -Name $t.$_ -Confirm:$false
                            toLog "Name of VM [$($this.instanceName)] has been changed to [$($t.$_)] according to the new tag Name value" 'semi'
                            $this.instanceName = $t.$_
                        }
                    }
                    # ---------------------------------------------------
                } # $tags.Keys | % {
            } # foreach($t in $tags) {
        }
        else {throw "AddTagVMW: You are trying to add an empty Tag"}
    }
    else {throw "AddTagVMW: Can't connect to the VMW region [$($this.region)]"}
}

[scriptblock]$sbDelTagVMW = {
    param(
        [parameter(Mandatory=$true)][string]$resourceId,
        [parameter(Mandatory=$true)][hashtable]$tags # Tags with their values to be deleted
    )

    if($this.ConnectProperRegionVMW) {
        $tagCat = $null; $tagVal = $null;
        $tags.Keys | %{
            $tagCat = Invoke-ThisCode -scriptBlk {Get-TagCategory -Name $_} -provider 'vmw'
            if(![string]::IsNullOrEmpty($tagCat)) {$tagVal = $this.GetTagFromVMW($_);}

            if(![string]::IsNullOrEmpty($tagCat) -and
            ![string]::IsNullOrEmpty($tagVal) -and
            $tagVal -eq $tags.$_)
            {
                $tagAss = Get-TagAssignment -Entity $($this.instanceName) -Category $_
                if($tagAss -ne $ull) {$tmp = Remove-TagAssignment $tagAss -Confirm:$false}
                else {throw "Something went wrong: RemoveTagVMW: Tag with it's value present but can't get tag assignment VM: [$($this.instanceName)] [$_ = '$tagVal']"}
            }
        }
    }
    else {throw "DelTagVMW: Can't connect to the VMW region [$($this.region)]"}
}

[scriptblock]$sbDelTagByNameVMW = {
    param(
        [parameter(Mandatory=$true)][string]$resourceId,
        [parameter(Mandatory=$true)][Hashtable]$tags,
        [parameter(Mandatory=$true)][string[]]$tagNames
    )

    if($this.ConnectProperRegionVMW) {
        $tagArr = @{}
        if($tags -ne $null -and $tags.Keys.Count -gt 0 -and $tagNames -ne $null -and $tagNames.Count -gt 0) {
            $tags.Keys | %{
                $key = $_
                $tagNames | % {
                    if($key -eq $_) {$tagArr.Add($key, (.$sbGetTagVMW $tags $_));}
                }
            }
            if($tagArr.Keys.Count -gt 0) {.$sbDelTagVMW $resourceId $tagArr;}
        }
    }
    else {throw "DelTagByNameVMW: Can't connect to the VMW region [$($this.region)]"}
}

[scriptblock]$sbTagsToStrVMW = {
    param(
        [parameter(Mandatory=$false, position=0)][Hashtable[]]$tags
    )

    $res = ''; $delimiter = ', ';
    if($tags -ne $null) {
        $tags.Keys | %{$res += "[$_=$($tags.$_)]$delimiter"}
        $res.Trim($delimiter);
    }
    else {$null}
}
# ----------------- Tagging end   ---------------------

# ================================================================================================================
# ======= [Set of AWS external object methods] [aws_frontend_object_methods.ps1] [2018-04-20 15:42:26 UTC] =======
# ================================================================================================================
    [scriptblock]$sbCheckInit = {
        if(($this | Get-Member -MemberType ScriptProperty | Where-Object {$_.Name -eq 'CheckResult'}) -eq $null) {
            $this.__internal | Add-Member -MemberType NoteProperty -Name CheckResult -Value @()
            $this | Add-Member -MemberType ScriptProperty -Name CheckResult -Value {$this.__internal.StringsToString($this.__internal.CheckResult.Msg)} | Out-Null
        }
    }

    [scriptblock]$sbCheckClear = {
        $this.CheckInit();
        $this.__internal.CheckResult = @();
    }

    [scriptblock]$sbCheckAll = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll = $true
        )

        Write-Verbose "Checking Instance: [$($this.InstanceId)]"
        $sms | % {$_.CheckInit(); if($clearAll) {$_.CheckClear();}}
        $this | Get-Member -MemberType ScriptMethod | Where-Object {$_.Name.StartsWith('CheckThis')} | ForEach-Object {.([scriptblock]::Create('$this.' + $_.Name + '($sms);'))}
    }

    [scriptblock]$sbCheckVolumesDeleteOnTermination = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )

        # ($sms | Select -First 1).GetDeleteDrivesOnTermination($sms)
        $sms | % {
            Write-Verbose "Checking Instance: [$($_.InstanceId)] volumes delete on termination"
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            if($_.drivesDeleteOnTermination) {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=0;
                    Msg=$_.__internal.checkErr[0].Replace('{info}', "Instance's DeleteOnTermination");
                }
            }
            else {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=9;
                    Msg=$_.__internal.checkErr[9];
                }
            }
        }
    }

    [scriptblock]$sbCheckVolumesType = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )

        $sms | % {
            Write-Verbose "Checking Instance: [$($_.InstanceId)] type of volumes"
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            $volOk = $true;
            $obj = $_
            foreach($v in $_.__internal.Volumes) {
                if($v.VolumeType -ne 'gp2') {
                    $volOk = $false;
                    Write-Verbose "Instance: [$($obj.InstanceId)] Volume: [$($v.VolumeId)] has inproper type: [$($v.VolumeType)]"
                    $obj.__internal.CheckResult += New-Object PSObject -Property @{
                        err=1;
                        Msg=$obj.__internal.checkErr[1].Replace('{volumeId}', $v.VolumeId).
                                            Replace('{volumeType}', $v.VolumeType).
                                            Replace('{additional}',[string]::Empty);
                        volumeId=$v.VolumeId;
                    };
                }
            }
            if($volOk) {
                $obj.__internal.CheckResult += New-Object PSObject -Property @{
                    err=0;
                    Msg=$obj.__internal.checkErr[0].Replace('{info}', 'Volumes Type');
                }
            }
        }
    }

    [scriptblock]$sbCheckInstanceTerminationProtection = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )


        # ($sms | Select -First 1).GetTerminationProtection($sms);
        $sms | % {
            Write-Verbose "Checking Instance: [$($_.InstanceId)] termination protection"
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            if($_.InstanceTerminationProtection) {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=0;
                    Msg=$_.__internal.checkErr[0].Replace('{info}', 'Instance TerminationProtection');
                }
            }
            else {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=8;
                    Msg=$_.__internal.checkErr[8];
                }
            }
        }
    }

    [scriptblock]$sbCheckPlatform = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )

        $sms | % {
            Write-Verbose "Checking Instance: [$($_.InstanceId)] platform"
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            if($_.Platform -eq 'Windows') {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=0;
                    Msg=$_.__internal.checkErr[0].Replace('{info}', 'Platform');
                }
            }
            else {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=3;
                    Msg=$_.__internal.checkErr[3].Replace('{platform}', $_.Platform).Replace('{additional}',[string]::Empty);
                };
            }
        }
    }

    [scriptblock]$sbCheckPageFileSettings = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )

        $code = @'
....
'@
        Write-Verbose "Checking Instance: [$(StringsToString $sms.InstanceId)] PageFile settings"
        InvokeSMSInstanceScript -sms $sms -script (DecodeString $code)
        $sms | % {
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            if($_.LastScriptRun.Result -ne $null) {
                if($_.LastScriptRun.Result.err -eq 0) {
                    $_.__internal.CheckResult += New-Object PSObject -Property @{
                        err=0;
                        Msg=$_.__internal.checkErr[0].Replace('{info}', 'Platform');
                    }
                }
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=10;
                    Msg=$_.LastScriptRun.Result.Msg;
                };
            }
            else {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=10;
                    Msg=$_.__internal.checkErr[10];
                };
            }
        }
    }

    [scriptblock]$sbCheckRequiredTags = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )

        $sms | % {
            Write-Verbose "Checking Instance: [$($_.InstanceId)] required tags"
            $tagNames = 'Name','env','tier','domain','department','description','role'
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            $tagsOk = $true;
            $tagNames | ForEach-Object {
                if([string]::IsNullOrEmpty(!($_ -in $_.__internal.tag.Key))) {
                    $tagsOk = $false;
                    $_.__internal.CheckResult += New-Object PSObject -Property @{
                        err=4;
                        Msg=$_.__internal.checkErr[4].Replace('{tag}', $_).Replace('{additional}',[string]::Empty);
                    };
                }
            }
            if($tagsOk) {
                $_.__internal.CheckResult += New-Object PSObject -Property @{
                    err=0;
                    Msg=$_.__internal.checkErr[0].Replace('{info}', 'Tags');
                }
            }
        }
    }

    [scriptblock]$sbCheckRequiredSecurityGroups = {
        param(
            [parameter(Mandatory=$true)][object[]]$sms,
            [parameter(Mandatory=$false)][bool]$clearAll=$false
        )

        $sms | % {
            $obj = $_
            Write-Verbose "Checking Instance: [$($_.InstanceId)] required security groups"
            $grpNames = "SG_{domainShort}_ALL", 'SG_GLOBAL_PORTAL', 'SG_GLOBAL_MANAGEMENT';
            $_.CheckInit(); if($clearAll) {$_.CheckClear();}
            if(![string]::IsNullOrEmpty($_.SecurityGroups)) {
                if([string]::IsNullOrEmpty($_.Name)) {
                    $_.__internal.CheckResult += New-Object PSObject -Property @{
                        err=5;
                        Msg=$_.__internal.checkErr[5].Replace('{additional}',[string]::Empty);
                    };
                }
                else {
                    $sg = $_.SecurityGroups.Split(', ') | Where-Object {![string]::IsNullOrEmpty($_)};
                    $gn = @(); $grpNames | % {$gn += $_.Replace('{domainShort}', ($obj.__internal.DomainShortFromFqdn($obj.Name)))}
                    $grpOk = $true;
                    $gn | % {
                        if(!($_ -in $sg)) {
                            $grpOk = $false;
                            $obj.__internal.CheckResult += New-Object PSObject -Property @{
                                err=6;
                                Msg=$obj.__internal.checkErr[6].Replace('{grp}',$_.Replace('{domainShort}', ($obj.__internal.DomainShortFromFqdn($obj.Name)))).Replace('{additional}',[string]::Empty);
                            };
                        }
                    }
                    if($grpOk) {
                        $_.__internal.CheckResult += New-Object PSObject -Property @{
                            err=0;
                            Msg=$_.__internal.checkErr[0].Replace('{info}', 'SG');
                        }
                    }
                }
            }
            else {
                $grpNames | ForEach-Object{
                    $_.__internal.CheckResult += New-Object PSObject -Property @{
                        err=6;
                        Msg=$_.__internal.checkErr[6].Replace('{grp}',$_.Replace('{domainShort}', ($_.__internal.DomainShortFromFqdn($_.Name)))).Replace('{additional}',[string]::Empty);
                    };
                }
            }
        }
    }

# ========================================================================================================
# ======= [This code is for the NewObject functions] [aws_NewObject.ps1] [2018-04-20 15:42:26 UTC] =======
# ========================================================================================================
function New-SMSObject {
    param(
        [parameter(Mandatory=$true, position=0)][object[]]$Instances
    )

    # --- Code ---
    $res = @(); $cnt = 0;
    $Instances | %{
        # Because function below use those 2 properties
        $_ | Add-Member -MemberType NoteProperty -Name provider -Value (Get-SMSProvider -Instance $_) -Force
        $_ | Add-Member -MemberType NoteProperty -Name region -Value (GetRegionFromNativeObject $_) -Force
    }
    $smsObjects = AddSMSNetInterfaceInfo (AddSMSVolumeInfo $Instances)
    foreach($s in $smsObjects) {
        $cnt++;
        Write-Verbose "Creating SMS object from #[$cnt]..."
        $res += NewSMSObject $s
        Write-Verbose "SMS object created #[$cnt]"
    }
    if($res -ne $null -and $res.Count -gt 0) {$res} else {$null}
    # --- Code ---
}

function New-SMSObjects {
    param(
        [parameter(Mandatory=$true, position=0)][object[]]$Instances
    )
    # --- Code ---
    $res = @()
    $Instances | % {
        if((Test-SMSIs -Instance $_ -provider 'suitable')) {$res += New-SMSObject $_}
        else {throw "Unknown Instance Type of [$_] Type: [$($_.GetType() | Out-String)]"}
    }
    if($res -ne $null -and $res.Count -gt 0) {$res | ?{$_ -ne $null}} else {$null}
    # --- Code ---
}

function SMSStateToVMWState {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$a
    )

    switch($a) {
        'running' {
            $vmwState = 'PoweredOn'
            break;
        }
        'stopped' {
            $vmwState ='PoweredOff'
            break;
        }
        'suspended' {
            $vmwState ='Suspended'
            break;
        }
        default {
            $vmwState = 'Unknown'
            break;
        }
    }
    $vmwState;
}

function VMWStateToSMSState {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$a
    )

    switch($a) {
        'PoweredOn' {
            $vmwState = 'running'
            break;
        }
        'PoweredOff' {
            $vmwState = 'stopped'
            break;
        }
        'Suspended' {
            $vmwState =$_.ToLower()
            break;
        }
    }
    $vmwState;
}

function ConvertStatePropertyForVMW {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][object]$a
    )

    VMWStateToSMSState @{Name=$a.PowerState.ToString()}
}

function FillVMWBackendObject {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][object]$internalObject,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][object]$a
    )

    $internalObject | Add-Member -MemberType ScriptMethod -Name StringsToString -Value $sbStringsToString
    $internalObject | Add-Member -MemberType ScriptMethod -Name DomainFromFqdn -Value $sbDomainFromFqdn
    $internalObject | Add-Member -MemberType ScriptMethod -Name DomainShortFromFqdn -Value $sbDomainShortFromFqdn

    $internalObject | Add-Member -MemberType ScriptMethod -Name InstanceSpecToStr -Value $sbInstanceSpecToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name PlacementToStr -Value $sbPlacementToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name TagsToStr -Value $sbTagsToStrVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name NetInterfacesToStr -Value $sbNetInterfacesToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name VolumesToStr -Value $sbVolumesToStr

    $internalObject | Add-Member -MemberType ScriptMethod -Name GetInstanceSpec -Value $sbGetInstanceSpec
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetInstanceSpecification -Value $sbGetInstanceSpecification
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetTerminationProtection -Value {$false}
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetTerminationProtection -Value {}
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetDeleteDrivesOnTermination -Value {$false}
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetDeleteDrivesOnTermination -Value {}
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetLastScriptRun -Value {$this.LastScriptRun = $args[0]}
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetTag -Value $sbGetTagVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name AddTag -Value $sbAddTagVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name DelTag -Value $sbDelTagVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value $sbDelTagByNameVMW

    $internalObject | Add-Member -MemberType ScriptMethod -Name GetInstanceSpecVMW -Value $sbGetInstanceSpecVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetInstanceTypeVMW -Value $sbGetInstanceTypeVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetTagFromVMW -Value $sbGetTagFromVMW
    $internalObject | Add-Member -MemberType ScriptMethod -Name ConnectProperRegionVMW -Value $sbConnectProperRegionVMW

    $internalObject | Add-Member -MemberType NoteProperty -Name instanceId -Value $a.Id;
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceName -Value $a.Name;
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceSpec -Value ($internalObject.GetInstanceSpecVMW($a.NumCpu, $a.CoresPerSocket, $a.GhzMax, $a.MemoryGb))
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceType -Value ($internalObject.GetInstanceTypeVMW($a.NumCpu, $a.CoresPerSocket, $a.GhzMax, $a.MemoryGb))
    $internalObject | Add-Member -MemberType NoteProperty -Name platform -Value $a.Guest.OSFullName;
    $internalObject | Add-Member -MemberType NoteProperty -Name privateIp -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name publicIp -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name securityGroups -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name subnetId -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name state -Value (ConvertStatePropertyForVMW $a);
    $internalObject | Add-Member -MemberType NoteProperty -Name tags -Value ($internalObject.GetTagFromVMW());
    $internalObject | Add-Member -MemberType NoteProperty -Name Volumes -Value $a.Volumes;
    $internalObject | Add-Member -MemberType NoteProperty -Name NetInterfaces -Value $a.NetInterfaces;
    $internalObject | Add-Member -MemberType NoteProperty -Name vpcId -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name placement -Value (@{Host=$a.VMHost; Folder=$a.Folder});
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceTerminationProtection -Value $false
    $internalObject | Add-Member -MemberType NoteProperty -Name drivesDeleteOnTermination -Value $false
    $internalObject | Add-Member -MemberType NoteProperty -Name rootDeviceName -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name rootDeviceType -Value $null;
    $internalObject | Add-Member -MemberType NoteProperty -Name OSInfo -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name OSComputerName -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name OSIp -Value @()
    $internalObject | Add-Member -MemberType NoteProperty -Name WorkplaceInfo -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name LastScriptRun -Value (New-Object PSObject -Property @{Result=$null; TimeStamp=$null; Duration=$null;})
    $internalObject | Add-Member -MemberType NoteProperty -Name subnet -Value $null;

    $internalObject
}

function FillAWSBackendObject {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][object]$internalObject,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][Amazon.EC2.Model.Instance]$a
    )

    $internalObject | Add-Member -MemberType ScriptMethod -Name GetSubnet -Value $sbGetSubnet
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetTerminationProtection -Value $sbGetTerminationProtection
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetInstanceSpec -Value $sbGetInstanceSpec
    $internalObject | Add-Member -MemberType ScriptMethod -Name VolumesToStr -Value $sbVolumesToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name NetInterfacesToStr -Value $sbNetInterfacesToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name StringsToString -Value $sbStringsToString
    $internalObject | Add-Member -MemberType ScriptMethod -Name DomainFromFqdn -Value $sbDomainFromFqdn
    $internalObject | Add-Member -MemberType ScriptMethod -Name DomainShortFromFqdn -Value $sbDomainShortFromFqdn
    $internalObject | Add-Member -MemberType ScriptMethod -Name VpcToStr -Value $sbVpcToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetProperDedicatedHost -Value $sbGetProperDedicatedHost
    $internalObject | Add-Member -MemberType ScriptMethod -Name ResizeInstance -Value $sbResizeInstance
    $internalObject | Add-Member -MemberType ScriptMethod -Name StartInstance -Value $sbStartInstance
    $internalObject | Add-Member -MemberType ScriptMethod -Name StopInstance -Value $sbStopInstance
    $internalObject | Add-Member -MemberType ScriptMethod -Name TerminateInstance -Value $sbTerminateInstance
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetTag -Value $sbGetTag
    $internalObject | Add-Member -MemberType ScriptMethod -Name AddTag -Value $sbAddTag
    $internalObject | Add-Member -MemberType ScriptMethod -Name DelTag -Value $sbDelTag
    $internalObject | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value $sbDelTagByName
    $internalObject | Add-Member -MemberType ScriptMethod -Name Refresh -Value $sbRefresh
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetSG -Value $sbSetSG
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetPrivateIp -Value $sbSetPrivateIp
    $internalObject | Add-Member -MemberType ScriptMethod -Name OSPropertiesWork -Value $sbOSPropertiesWork
    $internalObject | Add-Member -MemberType ScriptMethod -Name RunScript -Value $sbInvokeScriptOnInstance
    $internalObject | Add-Member -MemberType ScriptMethod -Name ClearLastScriptRun -Value {$this.LastScriptRun = New-Object PSObject -Property @{Result=$null; TimeStamp=$null; Duration=$null;};}

    $internalObject | Add-Member -MemberType ScriptMethod -Name InstanceSpecToStr -Value $sbInstanceSpecToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name SubnetToStr -Value $sbSubnetToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name PlacementToStr -Value $sbPlacementToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name TagsToStr -Value $sbTagsToStr
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetTerminationProtection -Value $sbSetTerminationProtection
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetDeleteDrivesOnTermination -Value $sbGetDeleteDrivesOnTermination
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetDeleteDrivesOnTermination -Value $sbSetDeleteDrivesOnTermination
    $internalObject | Add-Member -MemberType ScriptMethod -Name GetInstanceSpecification -Value $sbGetInstanceSpecification
    $internalObject | Add-Member -MemberType ScriptMethod -Name SetLastScriptRun -Value {$this.LastScriptRun = $args[0]}

    $internalObject | Add-Member -MemberType NoteProperty -Name instanceId -Value $a.InstanceId;
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceSpec -Value $internalObject.GetInstanceSpec($a.InstanceType);
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceType -Value $a.InstanceType
    $internalObject | Add-Member -MemberType NoteProperty -Name platform -Value $a.Platform;
    $internalObject | Add-Member -MemberType NoteProperty -Name privateIp -Value $a.PrivateIpAddress;
    $internalObject | Add-Member -MemberType NoteProperty -Name publicIp -Value $a.PublicIpAddress;
    $internalObject | Add-Member -MemberType NoteProperty -Name securityGroups -Value $a.SecurityGroups;
    $internalObject | Add-Member -MemberType NoteProperty -Name subnetId -Value $a.SubnetId;
    $internalObject | Add-Member -MemberType NoteProperty -Name state -Value $a.State;
    $internalObject | Add-Member -MemberType NoteProperty -Name tags -Value $a.Tags;
    $internalObject | Add-Member -MemberType NoteProperty -Name Volumes -Value $a.Volumes;
    $internalObject | Add-Member -MemberType NoteProperty -Name NetInterfaces -Value $a.NetInterfaces;
    $internalObject | Add-Member -MemberType NoteProperty -Name vpcId -Value $a.VpcId;
    $internalObject | Add-Member -MemberType NoteProperty -Name placement -Value $a.Placement;
    $internalObject | Add-Member -MemberType NoteProperty -Name instanceTerminationProtection -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name drivesDeleteOnTermination -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name rootDeviceName -Value $a.RootDeviceName;
    $internalObject | Add-Member -MemberType NoteProperty -Name rootDeviceType -Value $a.RootDeviceType;
    $internalObject | Add-Member -MemberType NoteProperty -Name OSInfo -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name OSComputerName -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name OSIp -Value @()
    $internalObject | Add-Member -MemberType NoteProperty -Name WorkplaceInfo -Value $null
    $internalObject | Add-Member -MemberType NoteProperty -Name LastScriptRun -Value (New-Object PSObject -Property @{Result=$null; TimeStamp=$null; Duration=$null;})
    $internalObject | Add-Member -MemberType NoteProperty -Name subnet -Value $internalObject.GetSubnet($internalObject.subnetId);

    $internalObject.GetDeleteDrivesOnTermination($internalObject);
    $internalObject.GetTerminationProtection($internalObject);

     # --- Changing ec2volume object to my own start ---
     if($a.Volumes -ne $null -and $a.Volumes.Count -gt 0) {
        $a.Volumes | ForEach-Object {$_ | Add-Member -MemberType NoteProperty -Name sms -Value $internalObject -Force}
    }
    # --- Changing ec2volume oibject to my own end -----

    $internalObject
}

function GetRegionFromNativeObject {
    param(
        [parameter(Mandatory=$true, position=0)][object]$a
    )

    switch ((Get-SMSProvider -Instance $a)) {
        'aws' {
            Get-SMSRegionFromZone $a.Placement.AvailabilityZone
            break;
        }
        'vmw' {
            $a.region;
            break;
        }
    }
}

function NewSMSObject {
    param(
        [parameter(Mandatory=$true, position=0)][object]$a
    )

    if(!(Test-SMSIs -Instance $a -provider 'suitable')) {throw "NewSMSObject: Instance [$($a | Out-String)] is not supported by SMS"}
    # --- Fill internal object start ---
    $internalObject = New-Object PSObject -Property @{
        author='alex';
        type='instance';
        provider=(Get-SMSProvider -Instance $a);
        region=(GetRegionFromNativeObject $a);
        checkErr=$null;
        drivePurpose=$null;
        imageSpec=$instancesSpec;
    }
    $internalObject.checkErr = @{
        0 = 'OK: {info}';
        1 = 'Error: Inproper Volume Type [{volumeType}] VolumeId [{volumeId}]{additional}';
        2 = 'Error: Inproper Volume Size [{volumeSize}] VolumeId [{volumeId}]{additional}';
        3 = 'Error: Platform [{platform}] is wrong{additional}';
        4 = 'Error: Absent tag with name [{tag}]{additional}';
        5 = 'Error: There is no tag "Name". Can not completely check for SG{additional}';
        6 = 'Error: Instance is not joined to SG [{grp}]{additional}';
        7 = 'Error: All/Some disk(s) are not set as DeleteOnTermination';
        8 = 'Error: Instance TerminationProtection is not set';
        9 = 'Error: VolumesDeleteOnTermination is not set'
        10 = 'Error: Can not get information from OS Level'
    }
    $internalObject.drivePurpose = @{
        'c' = 'System';
        'd' = 'Data';
        'l' = 'Log';
        'p' = 'Page File';
        'r' = 'Archives';
        't' = 'Temporary drive';
        'v' = 'VSS Copies';
    }
    $internalObject | Add-Member -MemberType ScriptProperty -Name AvailableInstanceTypes -Value $sbGetAvailableInstanceTypes

    switch((Get-SMSProvider -Instance $a)) {
        'aws' {
            $internalObject = (FillAWSBackendObject $internalObject $a)
            break;
        }
        'vmw' {
            $internalObject = (FillVMWBackendObject $internalObject $a)
            break;
        }
    }
    # --- Fill Internal object end ---



    # --- Fill Frontend object start ---
    $obj = New-Object PSObject -Property @{
        __internal = $internalObject;
    }
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisDeleteOnTermination -Value $sbCheckVolumesDeleteOnTermination
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisVolumesType -Value $sbCheckVolumesType
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisTerminationProtection -Value $sbCheckInstanceTerminationProtection
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisPlatform -Value $sbCheckPlatform
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisTags -Value $sbCheckRequiredTags
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisPageFileSettings -Value $sbCheckPageFileSettings
    $obj | Add-Member -MemberType ScriptMethod -Name CheckThisSecurityGroups -Value $sbCheckRequiredSecurityGroups
    $obj | Add-Member -MemberType ScriptMethod -Name CheckInit -Value $sbCheckInit
    $obj | Add-Member -MemberType ScriptMethod -Name CheckClear -Value $sbCheckClear
    $obj | Add-Member -MemberType ScriptMethod -Name CheckAll -Value $sbCheckAll
    $obj | Add-Member -MemberType ScriptMethod -Name GetProperDedicatedHost -Value {if(![string]::IsNullOrEmpty($args[1])){$this.__internal.GetProperDedicatedHost($this.InstanceType, $args[0], $args[1])} else {$this.__internal.GetProperDedicatedHost($this.InstanceType, $args[0])}}
    $obj | Add-Member -MemberType ScriptMethod -Name ResizeInstance -Value {if(![string]::IsNullOrEmpty($args[1])) {$this.__internal.ResizeInstance($args[0], $args[1])} else {$this.__internal.ResizeInstance($args[0])}}
    $obj | Add-Member -MemberType ScriptMethod -Name Stop -Value {if(![string]::IsNullOrEmpty($args[0])) {$this.__internal.StopInstance($args[0])} else {$this.__internal.StopInstance()}}
    $obj | Add-Member -MemberType ScriptMethod -Name Terminate -Value {if([string]::IsNullOrEmpty($args[0])) {$this.__internal.TerminateInstance()} else {$this.__internal.TerminateInstance($args[0])}}
    $obj | Add-Member -MemberType ScriptMethod -Name Start -Value {if([string]::IsNullOrEmpty($args[0])) {$this.__internal.StartInstance()} else {$this.__internal.StartInstance($args[0])}}
    $obj | Add-Member -MemberType ScriptMethod -Name GetTag -Value {$this.__internal.GetTag($this.__internal.Tags, $args[0]);}
    $obj | Add-Member -MemberType ScriptMethod -Name AddTag -Value {
        $this.__internal.AddTag($this.__internal.instanceId, $args[0]);
        if($this.provider -eq 'aws') {
            $this.__internal.Tags = (Invoke-ThisCode -ScriptBlk {Get-Ec2Instance -Region $this.__internal.region -InstanceId $this.__internal.InstanceId}).Instances.Tags;
        }
        elseif($this.provider -eq 'vmw') {$this.__internal.Tags = $this.__internal.GetTagFromVMW()}
    }
    $obj | Add-Member -MemberType ScriptMethod -Name DelTag -Value {
        $this.__internal.DelTag($this.__internal.instanceId, $args[0]);
        if($this.provider -eq 'aws') {
            $this.__internal.Tags = (Invoke-ThisCode -ScriptBlk {Get-Ec2Instance -Region $this.__internal.region -InstanceId $this.__internal.InstanceId}).Instances.Tags;
        }
        elseif($this.provider -eq 'vmw') {$this.__internal.Tags = $this.__internal.GetTagFromVMW()}
    }
    $obj | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value {
        $this.__internal.DelTagByName($this.__internal.instanceId, $this.__internal.Tags, $args[0]);
        if($this.provider -eq 'aws') {
            $this.__internal.Tags = (Invoke-ThisCode -ScriptBlk {Get-Ec2Instance -Region $this.__internal.region -InstanceId $this.__internal.InstanceId}).Instances.Tags;
        }
        elseif($this.provider -eq 'vmw') {$this.__internal.Tags = $this.__internal.GetTagFromVMW()}
    }
    $obj | Add-Member -MemberType ScriptMethod -Name Refresh -Value {$this.__internal.Refresh($this.__internal.instanceId)}
    $obj | Add-Member -MemberType ScriptMethod -Name GetInstanceSpecification -Value {$this.__internal.GetInstanceSpecification($args[0])}
    $obj | Add-Member -MemberType ScriptMethod -Name GetOSInfo -Value {$this.__internal.OSPropertiesWork($args[0], (($OSProperties | ? {$_.Dest -eq 'OSInfo'} | Select Dest).Dest));}
    $obj | Add-Member -MemberType ScriptMethod -Name GetOSComputerName -Value {$this.__internal.OSPropertiesWork($args[0], (($OSProperties | ? {$_.Dest -eq 'OSComputerName'} | Select Dest).Dest));}
    $obj | Add-Member -MemberType ScriptMethod -Name GetOSIp -Value {$this.__internal.OSPropertiesWork($args[0], (($OSProperties | ? {$_.Dest -eq 'OSIp'} | Select Dest).Dest));}
    $obj | Add-Member -MemberType ScriptMethod -Name GetOSAll -Value {$this.__internal.OSPropertiesWork($args[0], (($OSProperties | Select Dest).Dest));}
    $obj | Add-Member -MemberType ScriptMethod -Name RunScript -Value {$this.__internal.RunScript($args[0], $args[1], $args[2], $args[3], $args[4], $args[5], $args[6], $args[7]);}
    $obj | Add-Member -MemberType ScriptMethod -Name ClearLastScriptRun -Value {$this.__internal.ClearLastScriptRun();}
    $obj | Add-Member -MemberType ScriptMethod -Name SetLastScriptRun -Value {$this.__internal.SetLastScriptRun($args[0])}

    $obj | Add-Member -MemberType ScriptProperty -Name AvailableInstanceTypes -Value {$this.__internal.AvailableInstanceTypes}
    $obj | Add-Member -MemberType ScriptProperty -Name Region -Value {$this.__internal.region} -PassThru -Force | Out-Null
    $obj | Add-Member -MemberType ScriptProperty -Name Provider -Value {$this.__internal.provider} -PassThru -Force | Out-Null
    $obj | Add-Member -MemberType ScriptProperty -Name InstanceId -Value {$this.__internal.instanceId} -PassThru -Force | Out-Null
    $obj | Add-Member -MemberType ScriptProperty -Name InstanceName -Value {$this.__internal.instanceName} -PassThru -Force | Out-Null
    $obj | Add-Member -MemberType ScriptProperty -Name InstanceType -Value {$this.__internal.instanceType} -SecondValue {if(![string]::IsNullOrEmpty($args[1])) {$this.__internal.ResizeInstance($args[0], $args[1])} else {$this.__internal.ResizeInstance($args[0])}; $this.__internal.instanceType = $args[0]} -PassThru -Force | Out-Null
    $obj | Add-Member -MemberType ScriptProperty -Name InstanceSpec -Value {$this.__internal.InstanceSpecToStr($this.__internal.GetInstanceSpec($this.__internal.InstanceType))} -PassThru -Force | Out-Null
    $obj | Add-Member -MemberType ScriptProperty -Name SecurityGroups -Value {$this.__internal.StringsToString($this.__internal.SecurityGroups.GroupName)} -SecondValue {$this.__internal.SetSG($this.__internal.instanceId, $args[0]); $this.__internal.securityGroups = (Invoke-ThisCode -ScriptBlk {Get-EC2Instance -Region $this.__internal.region -InstanceId $this.__internal.InstanceId}).Intances.SecurityGroups} -PassThru -Force | Out-Null
    <# ... #>
    $obj | Add-Member -MemberType ScriptProperty -Name IsRunning -Value {$this.__internal.state.Name -eq 'running'}
    $obj | Add-Member -MemberType ScriptProperty -Name IsStopped -Value {$this.__internal.state.Name -eq 'stopped'}
    $obj | Add-Member -MemberType ScriptProperty -Name IsTerminated -Value {$this.__internal.state.Name -eq 'terminated'}
    $obj | Add-Member -MemberType ScriptProperty -Name RootDeviceName -Value {$this.__internal.rootDeviceName}
    $obj | Add-Member -MemberType ScriptProperty -Name RootDeviceType -Value {$this.__internal.rootDeviceType}
    $obj | Add-Member -MemberType ScriptProperty -Name LastScriptRun -Value {$this.__internal.LastScriptRun}
    $obj | Add-Member -MemberType ScriptProperty -Name OSCaption -Value {if($this.__internal.OSInfo) {$this.__internal.OSInfo.Caption}}
    $obj | Add-Member -MemberType ScriptProperty -Name OSInfo -Value {$this.__internal.OSInfo}
    $obj | Add-Member -MemberType ScriptProperty -Name OSComputerName -Value {$this.__internal.OSComputerName}
    $obj | Add-Member -MemberType ScriptProperty -Name OSIp -Value {$this.__internal.OSIp}
    $obj | Add-Member -MemberType ScriptProperty -Name WorkplaceInfo {$this.__internal.WorkplaceInfo}
    # $obj | Add-Member -MemberType ScriptProperty -Name Regions -Value {$this.__internal.regions}
    # --- Fill Frontend object end ---
    $obj
}

function AddSMSVolumeInfo {
    param(
        [parameter(Mandatory=$true, position=0)][object[]]$all
    )

    if($all -ne $null) {
        for($i=0; $i -lt $all.Count; $i++) {
            if((Test-SMSIs -Instance $all[$i] -provider 'aws')) {
                $runStr = "Get-Ec2Volume -Region $(Get-SMSRegionFromZone $all[$i].Placement.AvailabilityZone) -Filter (New-SMSEc2Filter @{'attachment.instance-id'= @('$($all[$i].InstanceId)');})"
            }
            elseif((Test-SMSIs -Instance $all[$i] -provider 'vmw')) {
                if(!(Connect-SMSVMWare -Region $all[$i].region -ConnectToProperRegion)) {throw "(AddSMSVolumeInfo): Can't connect to the [$($all[$i].provider.ToUpper())] region [$($all[$i].region)]"}
                $runStr = "Get-HardDisk -VM (Get-VM '$($all[$i].Name)')"
            }
            $all[$i] | Add-Member -MemberType NoteProperty -Name Volumes -Value (Invoke-ThisCode -ScriptStr $runStr) -Force
            if($all[$i].Volumes -ne $null -and $all[$i].Volumes.Count -gt 0) {
                $all[$i].Volumes | ForEach-Object {$_ = AddSmsToVolume -sms $all[$i] -vol $_}
            }
        }
        $all
    }
    else {$null}
}

function AddSMSNetInterfaceInfo {
    param(
        [parameter(Mandatory=$true, position=0)][object[]]$all
    )

    if($all -ne $null) {
        for($i=0; $i -lt $all.Count; $i++) {
            if((Test-SMSIs -Instance $all[$i] -provider 'aws')) {
                $runStr = "Get-Ec2NetworkInterface -Region $(Get-SMSRegionFromZone $all[$i].Placement.AvailabilityZone) -Filter (New-SMSEc2Filter @{'attachment.instance-id'= @('$($all[$i].InstanceId)');})"
            }
            elseif((Test-SMSIs -Instance $all[$i] -provider 'vmw')) {
                if(!(Connect-SMSVMWare -Region $all[$i].region -ConnectToProperRegion)) {throw "(AddSMSNetInterfaceInfo): Can't connect to the [$($all[$i].provider.ToUpper())] region [$($all[$i].region)]"}
                $runStr = "(Get-VM '$($all[$i].Name)').Guest.Nics"
            }
            $all[$i] | Add-Member -MemberType NoteProperty -Name NetInterfaces -Value (Invoke-ThisCode -scriptStr $runStr) -Force
            if($all[$i].NetInterfaces -ne $null -and $all[$i].NetInterfaces.Count -gt 0) {
                $all[$i].NetInterfaces | ForEach-Object {$_ = AddSmsToNetInterface $all[$i] $_}
            }
        }
        $all
    }
    else {$null}
}

function AddSmsToNetInterface {
    param (
        [parameter(Mandatory=$true, position=0)][ValidateNotNull()]$sms,
        [parameter(Mandatory=$true, position=1)][ValidateNotNull()]$net
    )

    if($net -ne $null -and $sms -ne $null) {
        $net | Add-Member -MemberType NoteProperty -Name sms -Value $sms -Force
        $net | Add-Member -MemberType NoteProperty -Name author -Value 'alex' -Force
        $net | Add-Member -MemberType NoteProperty -Name type -Value 'net' -Force
        $net | Add-Member -MemberType NoteProperty -Name region -Value $sms.region -Force
        $net | Add-Member -MemberType NoteProperty -Name provider -Value $sms.provider -Force
        if((Test-SMSIs -Instance $sms -provider 'aws')) {
            $net | Add-Member -MemberType ScriptMethod -Name GetTag -Value {if(![string]::IsNullOrEmpty($args[0])) {.$sbGetTag $this.TagSet $args[0]} else {.$sbGetTag $this.TagSet}}
            $net | Add-Member -MemberType ScriptMethod -Name AddTag -Value {.$sbAddTag $this.NetworkInterfaceId $args[0]; $this.TagSet = (Invoke-ThisCode -RunBlk {Get-Ec2NetworkInterface -Region $this.region -NetworkInterfaceId $this.NetworkInterfaceId}).TagSet;}
            $net | Add-Member -MemberType ScriptMethod -Name DelTag -Value {.$sbDelTag $this.NetworkInterfaceId $args[0]; $this.TagSet = (Invoke-ThisCode -RunBlk {Get-Ec2NetworkInterface -Region $this.region -NetworkInterfaceId $this.NetworkInterfaceId}).TagSet;}
            $net | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value {.$sbDelTagByName $this.NetworkInterfaceId $this.TagSet $args[0]; $this.TagSet = (Invoke-ThisCode -RunBlk {Get-Ec2NetworkInterface -Region $this.region -NetworkInterfaceId $this.NetworkInterfaceId}).TagSet;}
        }
        elseif((Test-SMSIs -Instance $sms -provider 'vmw')) {
            $net | Add-Member -MemberType ScriptMethod -Name GetTag -Value {toLog 'Method GetTag for VMWare NetworkAdapters is unexists' 'warning'}
            $net | Add-Member -MemberType ScriptMethod -Name AddTag -Value {toLog 'Method AddTag for VMWare NetworkAdapters is unexists' 'warning'}
            $net | Add-Member -MemberType ScriptMethod -Name DelTag -Value {toLog 'Method DelTag for VMWare NetworkAdapters is unexists' 'warning'}
            $net | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value {toLog 'Method DelTagByName for VMWare NetworkAdapters is unexists' 'warning'}
        }
    }
    $net
}

function AddSmsToVolume {
    param (
        [parameter(Mandatory=$false)][ValidateNotNull()]$sms = $null,
        [parameter(Mandatory=$true)][ValidateNotNull()]$vol,
        [parameter(Mandatory=$false)][ValidateNotNull()][string]$zone
    )

    if($vol -ne $null) {
        $vol | Add-Member -MemberType NoteProperty -Name author -Value 'alex' -Force
        $vol | Add-Member -MemberType NoteProperty -Name type -Value 'volume' -Force
        $vol | Add-Member -MemberType NoteProperty -Name OSDriveLetter -Value $null -Force

        if($vol.AvailabilityZone -ne $null) {$provider = 'aws'}
        elseif(!([string]::IsNullOrEmpty($zone))) {$provider = Get-SMSProvider (Get-SMSRegionFromZone $zone)}
        else {$provider = 'vmw'}
        $vol | Add-Member -MemberType NoteProperty -Name provider -Value $provider -Force

        if($provider -eq 'aws') {
            if($sms -ne $null) {
                $vol | Add-Member -MemberType NoteProperty -Name sms -Value $sms -Force
            }
            $vol | Add-Member -MemberType NoteProperty -Name region -Value (Get-SMSRegionFromZone $vol.AvailabilityZone) -Force
            $vol | Add-Member -MemberType ScriptProperty -Name DriveLetter -Value {.$sbGetTag $this.Tags 'Letter'} -Force
            $vol | Add-Member -MemberType ScriptMethod -Name Set -Value $sbVolumeSet
            $vol | Add-Member -MemberType ScriptMethod -Name Dismount -Value $sbVolumeDismount
            $vol | Add-Member -MemberType ScriptMethod -Name Mount -Value $sbVolumeMount
            $vol | Add-Member -MemberType ScriptMethod -Name Delete -Value $sbVolumeDelete
            $vol | Add-Member -MemberType ScriptMethod -Name GetTag -Value {if(![string]::IsNullOrEmpty($args[0])) {.$sbGetTag $this.Tags $args[0]} else {.$sbGetTag $this.Tags}}
            $vol | Add-Member -MemberType ScriptMethod -Name AddTag -Value {.$sbAddTag $this.VolumeId $args[0]; $this.Tags = (Invoke-ThisCode -ScriptBlk {Get-Ec2Volume -Region $this.region -VolumeId $this.VolumeId}).Tags;}
            $vol | Add-Member -MemberType ScriptMethod -Name DelTag -Value {.$sbDelTag $this.VolumeId $args[0]; $this.Tags = (Invoke-ThisCode -ScriptBlk {Get-Ec2Volume -Region $this.region -VolumeId $this.VolumeId}).Tags;}
            $vol | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value {.$sbDelTagByName $this.VolumeId $this.Tags $args[0]; $this.Tags = (Invoke-ThisCode -ScriptBlk {Get-Ec2Volume -Region $this.region -VolumeId $this.VolumeId}).Tags;}
        }
        elseif($provider -eq 'vmw') {
            if($sms -ne $null) {
                $vol | Add-Member -MemberType NoteProperty -Name sms -Value $sms -Force
                $vol | Add-Member -MemberType NoteProperty -Name region -Value $sms.region -Force
            }
            $vol | Add-Member -MemberType NoteProperty -Name Size -Value ([math]::Round($vol.CapacityGb))
            $vol | Add-Member -MemberType NoteProperty -Name VolumeType -Value "$($vol.StorageFormat)/$($vol.DiskType)"
            $vol | Add-Member -MemberType ScriptProperty -Name DriveLetter -Value {} -Force
            $vol | Add-Member -MemberType ScriptMethod -Name Set -Value {}
            $vol | Add-Member -MemberType ScriptMethod -Name Dismount -Value {}
            $vol | Add-Member -MemberType ScriptMethod -Name Mount -Value {}
            $vol | Add-Member -MemberType ScriptMethod -Name Delete -Value {}
            $vol | Add-Member -MemberType ScriptMethod -Name GetTag -Value {toLog 'Method GetTag for VMWare Volume is unexists' 'warning'}
            $vol | Add-Member -MemberType ScriptMethod -Name AddTag -Value {toLog 'Method AddTag for VMWare Volume is unexists' 'warning'}
            $vol | Add-Member -MemberType ScriptMethod -Name DelTag -Value {toLog 'Method DelTag for VMWare Volume is unexists' 'warning'}
            $vol | Add-Member -MemberType ScriptMethod -Name DelTagByName -Value {toLog 'Method DelTagByName for VMWare Volume is unexists' 'warning'}
        }
    }
    $vol
}

# ====================================================================================================================
# ======= [Methods for the AWS Volume in SMS object] [aws_volume_object_methods.ps1] [2018-04-20 15:42:26 UTC] =======
# ====================================================================================================================
[scriptblock]$sbVolumeSet = {
    param(
        [parameter(Mandatory=$true)][ValidateSet('size', 'type')][string]$what,
        [parameter(Mandatory=$true)][string]$val,
        [parameter(Mandatory=$false)][int]$timeout = 180,
        [parameter(Mandatory=$false)][bool]$alsoInOs = $true
    )

    if($this.VolumeType -ne 'standard') {
        switch($what) {
            'size' {
                $size = [UInt32]$val;
                if($size -ge $this.Size) {
                    $result = Invoke-ThisCode -ScriptBlk {Edit-EC2Volume -Region $this.region -VolumeId $this.VolumeId -Size $size -Force -Confirm:$false};
                }
                else {throw "[$($this.VolumeId)] Can't set new size for the drive because new size is less then the current one."}
                break;
            }
            'type' {
                if($val -in @('gp2','io1','sc1','st1')) {
                    $result = Invoke-ThisCode -ScriptBlk {Edit-EC2Volume -Region $this.region -VolumeId $this.VolumeId -VolumeType $val -Force -Confirm:$false};
                }
                else {throw "[$($this.VolumeId)] Can't set new type. Because type you specified is unknown [$val]. Valid are: gp2, io1, sc1, st1"}
                break;
            }
        }
        if($result.ModificationState -ne 'failed') {
            $state = (Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}).State
            $cur = Get-Date
            $delta = $cur - (Get-Date)
            while((($result.ModificationState -ne 'failed' -and $result.ModificationState -ne 'completed') -and $state.Value -ne 'available') -and [math]::Abs($delta.TotalSeconds) -lt $timeout)
            {
                $state = (Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}).State
                $result = Invoke-ThisCode -ScriptBlk {Get-EC2VolumeModification -Region $this.region -VolumeId $this.VolumeId}
                Write-Verbose "[$($this.VolumeId)] Waiting for modification. Current State is [$($state.Value)] ModificationState is [$($result.ModificationState)]";
                Start-Sleep 5;
                $delta = $cur - (Get-Date)
            }
            if(($result.ModificationState -eq 'completed' -or $state.Value -eq 'available') -and [math]::Abs($delta.TotalSeconds) -lt $timeout) {
                $new = Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId};
                $this.Size = $new.Size;
                $this.VolumeType = $new.VolumeType;
                if($this.sms -ne $null -and $this.sms.author -eq 'alex') {
                    # Modifying live object
                    # $this.sms.AddTag($this.VolumeId, @{Size=$new.Size});
                    if($alsoInOs-and $what -eq 'size') {
                        $script = @'
....
'@
                        Write-Verbose "Trying to modify Volume [$($this.VolumeId)] on OS level..."
                        $letter = $this.DriveLetter
                        if(![string]::IsNullOrEmpty($letter)) {
                            [string[]]$tmp = (DecompressString $script).Replace('{letter}', $letter).Split("`r`n") | ? {![string]::IsNullOrEmpty($_)}
                            InvokeSMSInstanceScript -sms $this.sms -script $tmp
                            $ret = $this.sms.LastScriptRun.Result;
                            if($ret -ne $null) {
                                if(($ret.GetType()).Name -ne 'Hashtable') {
                                    if([math]::Round($ret.Size/1Gb) -ne [math]::Round($new.Size)) {throw "Volume [$($this.VolumeId)] has been expanded on Cloud Level, but something went wrong while extension on OS level. [$($ret | Out-String)]"}
                                    else {Write-Verbose "Volume [$($this.VolumeId)] modification on OS level is OK. Now it has [$([math]::Round($ret.Size/1Gb))] Gb size"}
                                }
                                else {
                                    if('Error' -in $ret.Keys) {throw "Volume [$($this.VolumeId)] has been expanded on Cloud Level, but we've got error [$($ret.Error)] during expansion on OS Level"}
                                    else {throw "Volume [$($this.VolumeId)] has been expanded on Cloud Level, but we've got error [$($ret | Out-String)] during expansion on OS Level"}
                                }
                            }
                            else {throw "Volume [$($this.VolumeId)] has been expanded on Cloud Level, but during expansion on OS Level possible there were some errors. You need to check it manually"}
                        }
                        else {throw "Volume [$($this.VolumeId)] has been expanded on Cloud Level, but it's not properly tagged. Won't be expanded on OS Level"}
                    }
                }
            }
            else {throw "[$($this.VolumeId)] Can't change [$what] to [$vol]. Modification failed with reason: [$($result.StatusMessage)]"}
        }
        else {throw "[$($this.VolumeId)] Can't change [$what] to [$vol]. Modification failed with reason: [$($result.StatusMessage)]"}
    }
    else {throw "[$($this.VolumeId)] We mustn't change anything for the VolumeType [standard]"}
}

[scriptblock]$sbVolumeDismount = {
    param(
        [parameter(Mandatory=$true)][string]$instanceId,
        [parameter(Mandatory=$false)][int]$timeout = 30,
        [parameter(Mandatory=$false)][switch]$forceDismount
    )

    Write-Verbose "Trying to Dismount volume [$($this.VolumeId)] from the Instance [$instanceId]"
    if($instanceId -eq $this.Attachments.InstanceId -and $this.Sms -ne $null) {
        toLog "Dismounting device [$($this.VolumeId)] [$($this.Attachments[0].Device)] [$($this.GetTag('Letter'))]" 'semi'
        if(!$forceDismount.IsPresent) {$state = Invoke-ThisCode -ScriptBlk {Dismount-EC2Volume -Region $this.region -VolumeId $this.VolumeId -InstanceId $instanceId -Force}}
        else {$state = Invoke-ThisCode -ScriptBlk {Dismount-EC2Volume -Region $this.region -VolumeId $this.VolumeId -InstanceId $instanceId -Force -ForceDismount:$true}}
        $cur = Get-Date
        $delta = $cur - (Get-Date)
        $state = Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}
        while([math]::Abs($delta.TotalSeconds) -lt $timeout -and $state.Status.Value -ne 'available') {
            Write-Verbose "Waiting for the volume [$($this.VolumeId)]. Current state is [$($state.Status.Value)]..."
            $state = Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}
            $delta = $cur - (Get-Date)
            Start-Sleep 5;
        }
        if([math]::Abs($delta.TotalSeconds) -lt $timeout) {
            Write-Verbose "[$($this.VolumeId)] Has been detached Ok from the Instance [$instanceId]"
            #$v = $this.Sms.Volumes | Where-Object {$_.VolumeId -eq $this.VolumeId}
            #$v = AddSmsToVolume $sms.region $sms $state;
            $this.Sms.Volumes = $this.Sms.Volumes | Where-Object {$_.VolumeId -ne $this.VolumeId}
            $this.Sms = $null;
            $this.Attachments | ForEach-Object {if($_.InstanceId -eq $instanceId) {$_.InstanceId = $null;}}
        }
        else {throw "Error detaching this volume [$($this.VolumeId)] belonging to the [$($this.Sms.InstanceId)]. Reason: Timeout.  It's current state is [$($state.Status.Value)]"}
    }
   else {throw "This volume [$($this.VolumeId)] doesn't belong to the current Instance [$instanceId/$($this.Attachments.InstanceId)/$($this.Sms.InstanceId)]"}
}

[scriptblock]$sbVolumeMount = {
    param(
        [parameter(Mandatory=$true)][object]$sms,
        [parameter(Mandatory=$false)][string]$device,
        [parameter(Mandatory=$false)][int]$timeout = 30
    )

    if([string]::IsNullOrEmpty($this.Attachments.InstanceId) -and $this.Sms -eq $null) {
        $cur = Get-Date
        # $this.Attachments is an Array
        if([string]::IsNullOrEmpty($device)) {$device = "$($this.Attachments.Device)"}
        Write-Verbose "Trying to attach the Volume [$($this.VolumeId)] to the Instance [$($sms.instanceId)] as Device [$device]"
        $state = Invoke-ThisCode -ScriptBlk {Add-EC2Volume -Region $this.region -VolumeId $this.VolumeId -InstanceId $sms.instanceId -Device $device}
        $delta = $cur - (Get-Date)
        while([math]::Abs($delta.TotalSeconds) -lt $timeout -and $state.Status.Value -ne 'in-use') {
            Write-Verbose "Waiting for the volume [$($this.VolumeId)]. Current state is [$($state.Status.Value)]..."
            $state = Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId};
            $delta = $cur - (Get-Date)
            Start-Sleep 5;
        }
        if([math]::Abs($delta.TotalSeconds) -lt $timeout) {
            Write-Verbose "[$($this.VolumeId)] Has been attached Ok to the Instance [$($sms.instanceId)]"
            if($this.sms -ne $null -and $this.sms.author -eq 'alex') {
                #$v = $this.Sms.Volumes | Where-Object {$_.VolumeId -eq $this.VolumeId}
                #$v = AddSmsToVolume $sms.region $sms $state;
                $this.Sms.Volumes = $this.Sms.Volumes += $this;
                $this.Attachments | ForEach-Object {if([string]::IsNullOrEmpty($_.InstanceId)) {$_.InstanceId = $sms.instanceId;}}
            }
        }
        else {Write-Host "Delta=$([math]::Abs($delta.TotalSeconds))" -Fore Yellow; throw "Error attaching this volume [$($this.VolumeId)] as Device [$device] to the Instance [$($sms.instanceId)]. Reason: Timeout.  It's current state is [$($state.Status.Value)]"}
    }
    else {throw "This volume [$($this.VolumeId)] is attached to the Instance [$($this.Attachments.InstanceId)/$($this.sms.instanceId)]. You must detach it first."}
}

[scriptblock]$sbVolumeDelete = {
    param(
        [parameter(Mandatory=$false)][int]$timeout = 30
    )

    Write-Verbose "Trying to Delete volume [$($this.VolumeId)]"
    if([string]::IsNullOrEmpty($this.Attachments.InstanceId) -and $this.Sms -eq $null) {
        if((Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}).Status.Value -eq 'available') {
            toLog "Deleting device [$($this.VolumeId)] [$($this.Attachments[0].Device)] [$($this.GetTag('Letter'))]" 'semi'
            $state = Invoke-ThisCode -ScriptBlk {Remove-EC2Volume -Region $this.region -VolumeId $this.VolumeId -PassThru -Force}
            $cur = Get-Date
            $delta = $cur - (Get-Date)
            try {$state = Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}} catch {$state = @{Status=@{Value='deleting'}}}
            while([math]::Abs($delta.TotalSeconds) -lt $timeout -and $state.Status.Value -ne 'deleting') {
                Write-Verbose "Waiting for the volume [$($this.VolumeId)]. Current state is [$($state.Status.Value)]..."
                $state = Invoke-ThisCode -ScriptBlk {Get-EC2Volume -Region $this.region -VolumeId $this.VolumeId}
                $delta = $cur - (Get-Date)
                Start-Sleep 5;
            }
            if([math]::Abs($delta.TotalSeconds) -lt $timeout) {
                Write-Verbose "[$($this.VolumeId)] Has been deleted Ok"
            }
            else {throw "Error removing this volume [$($this.VolumeId)]. Reason: Timeout. It's current state is [$($state.VolumeStatus.Status.Value)]"}
        }
        else {throw "Error removing this volume [$($this.VolumeId)]. Reason: It's not in 'available' state. Current state is [$($state.Status.Value)]"}
    }
   else {throw "This volume [$($this.VolumeId)] doesn't belong to the current Instance [$instanceId/$($this.Attachments.InstanceId)/$($this.Sms.InstanceId)]"}
}

# ==================================================================================================================================
# ======= [Dedicated Commandlets those duplicate functions of objects] [functions_duplication.ps1] [2018-04-20 15:42:26 UTC] =======
# ==================================================================================================================================
function Get-SMSDedicatedHost {
    param(
        [parameter(Mandatory=$true, position=0)][string]$InstanceType,
        [parameter(Mandatory=$false, position=1)][ValidateSet('FirstAvailable','MinRooms','MaxRooms','All')][string]$Algorythm='FirstAvailable',
        [parameter(Mandatory=$false, position=2)][string]$Zone
    )
    # --- Code ---
    if([string]::IsNullOrEmpty($Zone)) {$Zone = Get-SMSVar 'Zone'}
    .$sbGetProperDedicatedHost $InstanceType $Algorythm $Zone;
    # --- Code ---
}

function Get-SMSInstanceSpecification {
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string]$InstanceType,
        [parameter(Mandatory=$false, position=1)]
        [switch]$AsString
    )
    # --- Code ---
    $q = New-Object PSObject -Property @{imageSpec = $instancesSpec}
    $q | Add-Member -MemberType ScriptMethod -Name GetInstanceSpec -Value $sbGetInstanceSpec
    $q | Add-Member -MemberType ScriptMethod -Name GetInstanceSpecToStr -Value $sbInstanceSpecToStr
    if(!$AsString.IsPresent) {$q.GetinstanceSpec($InstanceType);}
    else {$q.GetInstanceSpecToStr($q.GetinstanceSpec($InstanceType));}
    # --- Code ---
}

function Get-SMSAvailableInstanceTypes {
    # --- Param empty ---
    # --- Code ---
    $q = New-Object PSObject -Property @{imageSpec = $instancesSpec}
    $q | Add-Member -MemberType ScriptMethod -Name GetAvailableInstanceTypes -Value $sbGetAvailableInstanceTypes
    $q.GetAvailableInstanceTypes();
    # --- Code ---
}

# =====================================================================
# ======= [SMS Tests work] [test.ps1] [2018-04-20 15:42:26 UTC] =======
# =====================================================================
function InvokeSMSTest {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [ValidateSet('All', 'DeleteOnTermination', 'VolumesType', 'TerminationProtection', 'Platform', 'Tags', 'SecurityGroups', 'PageFileSettings')]
        [string]$Check = 'All',
        [parameter(Mandatory=$false, position=2)]
        [switch]$safePrevious,
        [parameter(Mandatory=$false, position=3)]
        [bool]$Logging=$true
    )

    if($check -eq 'All') {
        . ([scriptblock]::Create('($sms | Select -First 1).CheckAll($sms, $' + (!$safePrevious.IsPresent) + ')'));
    }
    else {
        . ([scriptblock]::Create('($sms | Select -First 1).CheckThis' + $Check + '($sms, $' + (!$safePrevious.IsPresent) + ')'));
    }
}

function Invoke-SMSTest {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [ValidateSet('All', 'DeleteOnTermination', 'VolumesType', 'TerminationProtection', 'Platform', 'Tags', 'SecurityGroups','PageFileSettings')]
        [string]$Check = 'All',
        [parameter(Mandatory=$false, position=2)]
        [switch]$safePrevious,
        [parameter(Mandatory=$false, position=3)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        InvokeSMSTest $toProcess $Check $SafePrevious
        $toProcess
    }
    # --- Code ---
}

# ============================================================================
# ======= [SMS Instance work] [instance.ps1] [2018-04-20 15:42:26 UTC] =======
# ============================================================================
function ResizeSMSInstance {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [string]$NewType,
        [parameter(Mandatory=$false, position=2)]
        [int]$timeout = 600,
        [parameter(Mandatory=$false, position=3)]
        [bool]$Logging=$true
    )

    $sms | % {
        $_.ResizeInstance($NewType, $timeout);
    }
}

function Resize-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [string]$NewType,
        [parameter(Mandatory=$false, position=2)]
        [int]$timeout = 600,
        [parameter(Mandatory=$false, position=3)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            ResizeSMSInstance $_ $NewType $Timeout
            # $res += $_.Refresh();
            $res += $_
        }
        else {
            ResizeSMSInstance $sms $NewType $Timeout
            #$sms | % {$res += $_.Refresh();}
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}


function InvokeSMSRefresh {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $sms | % {$_.Refresh();}
}

function Invoke-SMSRefresh {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += InvokeSMSRefresh $_
        }
        else {
            $res = InvokeSMSRefresh $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function StopSMSInstance {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 300,
        [parameter(Mandatory=$false, position=2)]
        [switch]$ForceStop,
        [parameter(Mandatory=$false, position=3)]
        [switch]$Terminate,
        [parameter(Mandatory=$false, position=4)]
        [bool]$Logging=$true
    )

    $sms | % {
        if(!$Terminate.IsPresent) {
            if(!$ForceStop.IsPresent) {$_.Stop($timeout);}
            else {$_.Stop($timeout, $forceStop);}
        }
        else {$_.Terminate($timeout);}
    }
}

function Stop-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 300,
        [parameter(Mandatory=$false, position=2)]
        [switch]$ForceStop,
        [parameter(Mandatory=$false, position=3)]
        [switch]$Terminate,
        [parameter(Mandatory=$false, position=4)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            StopSMSInstance $_
            $res += $_
        }
        else {
            StopSMSInstance $sms
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function RemoveSMSInstance {
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 120,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | % {$_.Terminate($timeout);}
}

function Remove-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 120,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            RemoveSMSInstance $_
            $res += $_
        }
        else {
            RemoveSMSInstance $sms
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function StartSMSInstance {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 120,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $sms | % {$_.Start($timeout);}
}

function Start-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 120,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            StartSMSInstance $_
            $res += $_
        }
        else {
            StartSMSInstance $sms
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function RestartSMSInstance {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 120,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | % {$_.Stop($timeout); $_.Start($timeout);}
}

function Restart-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [int]$timeout = 120,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            RestartSMSInstance $_
            $res += $_
        }
        else {
            RestartSMSInstance $sms
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function WaitSMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [ValidateSet('pending', 'running', 'shutting-down', 'terminated', 'stopping', 'stopped','suspended')]
        [string]$State='running',
        [parameter(Mandatory=$false, position=2)]
        [ValidateSet('any', 'ok', 'impaired', 'insufficient-data', 'not-applicable', 'initializing')]
        [string]$Status='ok',
        [parameter(Mandatory=$false, position=3)]
        [int]$Timeout = 600,
        [parameter(Mandatory=$false, position=4)]
        [bool]$Logging=$true
    )

    $sms | % {
        if($_.provider -eq 'vmw') {$Status = 'any'}

        $cur = Get-Date
        Write-Verbose "Waiting the instance [$($sms.InstanceId)] for the state [$State] and Status [$Status]"
        $tmp0 = $sms | Get-SMS -What State
        if($Status -ne 'any') {$tmp1 = $sms | Get-SMS -What Status}
        else {$tmp1 = 'any'}
        $delta = $cur - (Get-Date)
        while(
                (
                    (($tmp0 | Where-Object {$_ -ne $State}) -ne $null -and (($tmp0 | Where-Object {$_ -eq $State}).Count -ne $tmp0.Count)) -or
                    (($tmp1 | Where-Object {$_ -ne $Status}) -ne $null -and (($tmp1 | Where-Object {$_ -eq $Status}).Count -ne $tmp1.Count))
                ) -and
                [math]::Abs($delta.TotalSeconds) -lt $Timeout
            )
        {
            Write-Verbose "Waiting the instance [$($sms.InstanceId)] for the state [$State] status [$Status]. Current: State [$($tmp0)] Status [$($tmp1)]"
            Start-Sleep 5;
            $tmp0 = $sms | Get-SMS -What State
            if($Status -ne 'any') {$tmp1 = $sms | Get-SMS -What Status}
            else {$tmp1 = 'any'}
            $delta = $cur - (Get-Date)
        }
        Write-Verbose "Finally: State [$tmp0] Status [$tmp1] Delta [$([math]::Abs($delta.TotalSeconds))]"
        if([math]::Abs($delta.TotalSeconds) -lt $Timeout) {$sms}
        else {throw "Timeout waiting instance [$($sms.InstanceId)] for the state [$state]"}
    }
}

function Wait-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [ValidateSet('pending', 'running', 'shutting-down', 'terminated', 'stopping', 'stopped','suspended')]
        [string]$State='running',
        [parameter(Mandatory=$false, position=2)]
        [ValidateSet('any', 'ok', 'impaired', 'insufficient-data', 'not-applicable', 'initializing')]
        [string]$Status='ok',
        [parameter(Mandatory=$false, position=3)]
        [int]$Timeout = 600,
        [parameter(Mandatory=$false, position=4)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $tmp = WaitSMSInstance $_ $State $Status $Timeout
            $res += $_
        }
        else {
            $tmp = WaitSMSInstance $sms $State $Status $Timeout
            $res = $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function GetSMSInstancePlacement {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $sms | % {$_.__internal.placement}
}

function Get-SMSInstancePlacement {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += GetSMSInstancePlacement $_
        }
        else {
            $res = GetSMSInstancePlacement $sms
        }

    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function GetSmsInstance {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]
        [object[]]$instances,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    try {
        if($instances -ne $null) {
            log "Creating SMS Object(s) from the Instance(s)" 'semi'
            New-SMSObjects $instances
        }
        else {$null}
    }
    finally {
        Save-SMSRemoteLog;
    }
}

function GetInstanceFromProvider {
    [CmdletBinding(DefaultParameterSetName='InstanceId')]
    param(
        [parameter(ParameterSetName='InstanceId', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$InstanceId,
        [parameter(ParameterSetName='Instance', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.Instance[]]$Instance,
        [parameter(ParameterSetName='Reservation', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.Reservation[]]$Reservation,
        [parameter(ParameterSetName='Name', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,
        [parameter(ParameterSetName='PrivateIp', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$PrivateIp,
        [parameter(ParameterSetName='Domain', Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domain,
        [parameter(Mandatory=$false)]
        [ValidateSet('aws', 'vmw', 'suitable')]
        [string]$Provider='suitable',
        [parameter(Mandatory=$false)][switch]$doNotContinueWhenFound
    )

    begin {
        # How to get GhzMax from VMWare VM: https://communities-gbot.vmware.com/thread/528098
        $nameAndDomainScript = @'
                $tmp = Get-TagAssignment -Category "{tagCat}" {silentlyContinue};
                if($tmp -ne $null) {
                    $all = @();
                    $tmp | Select Entity, @{n="TagValue"; e={$_.Tag.ToString().Split("/")[1]}} | ?{
                        $_.TagValue -eq "{nameVal}"
                    } | %{
                        $vm = Get-VM $_.Entity;
                        $tmp = $vm | select @{n="GhzMax"; e={$_.NumCpu * $_.VMHost.CpuTotalMhz / $_.VMHost.NumCpu/1Kb}};
                        $vm | Add-Member -MemberType NoteProperty -Name GhzMax -Value $tmp.GhzMax -Force;
                        $all += $vm;
                    };
                    if($all.Count -gt 0) {$all} else {$null};
                } else {$null}
'@
        $instanceIdScript = @'
        $vm = Get-VM -Id "{instanceId}" {silentlyContinue};
        if($vm -ne $null) {
            $all = @();
            $vm | %{
                $tmp = $_ | select @{n="GhzMax"; e={$_.NumCpu * $_.VMHost.CpuTotalMhz / $_.VMHost.NumCpu/1Kb}};
                $_ | Add-Member -MemberType NoteProperty -Name GhzMax -Value $tmp.GhzMax -Force;
                $all += $_;
            };
            if($all.Count -gt 0) {$all} else {$null};
        } else {$null}
'@
        $ins = @()
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            'Instance' {
                $Instance | %{
                    if((Test-SMSIs -Instance $_ -Provider $Provider)) {
                        if($Provider -ne 'aws') {$_ | Add-Member -MemberType NoteProperty -Name region -Value (Get-SMSVar 'Region') -Force}
                        $ins += $_
                    }
                    else {throw "You passed Instance [$($_ | Out-String)] of type [$($_.GetType() | Out-String)] that is not supported by SMS"}
                }
                break;
            }
            'Reservation' {
                $Reservation | %{
                    if($_ -ne 'aws') {throw "You can't use Provider [$_] with Reservation variable. Just with 'AWS'"}
                    $ins += $_.Instances;
                }
                break;
            }
            'InstanceId' {
                $found = $null;
                $InstanceId | %{
                    if((Test-SMSIs -InstanceId $_ -Provider 'aws')) {
                        $scr = "(Get-Ec2Instance -InstanceId '$_' {autoregion}).Instances";
                    }
                    elseif((Test-SMSIs -InstanceId $_ -Provider 'vmw')) {
                        $scr = $instanceIdScript.Replace('{instanceId}', $_);
                    }
                    else {throw "InstanceId [$InstanceId] is wrong for provider [$Provider]"}
                    $found = Invoke-ThisCodeByAutoregions -provider (Get-SMSProvider -InstanceId $_) -scriptStr $scr -doNotIgnoreEmptyResult -doNotInsertSpecialCode  -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    if($found) {
                        $found.Result | Add-Member -MemberType NoteProperty -Name region -Value ($found.Region) -Force
                        $ins += $found.Result;
                    }
                }
                break;
            }
            'Name' {
                $Name | %{
                    $nameVal = $_;
                    if($provider -eq 'aws' -or $provider -eq 'suitable') {
                        $found = @();
                        $tmp = Invoke-ThisCodeByAutoregions -Provider 'aws' -scriptStr "Get-Ec2Instance -Filter (New-SMSEc2Filter -filter @{'tag:Name'='$_'})"  -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                        $found += $tmp.Result
                        if($found.Count -gt 0) {$ins += $found.Instances}
                    }
                    if($provider -eq 'vmw' -or $provider -eq 'suitable') {
                        $found = @();
                        $tmp = Invoke-ThisCodeByAutoregions -provider 'vmw' -scriptStr ($nameAndDomainScript.Replace('{nameVal}', $nameVal).Replace('{tagCat}','Name')) -doNotInsertSpecialCode  -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                        $found += $tmp.Result
                        if($found.Count -gt 0) {
                            $found | Select -Unique | %{
                                $_ | Add-Member -MemberType NoteProperty -Name region -Value ($tmp.Region) -Force
                                $ins += $_
                            }
                        }
                    }
                }
                if($ins.Count -eq 0) {throw "(GetInstanceFromProvider): There is no Instance(s) found"}
                break;
            }
            'Domain' {
                $Domain | %{
                    $nameVal = $_;
                    if($provider -eq 'aws' -or $provider -eq 'suitable') {
                        $found = @();
                        $tmp = Invoke-ThisCodeByAutoregions -scriptStr "Get-Ec2Instance -Filter (New-SMSEc2Filter -filter @{'tag:domain'='$_'})" -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                        $found += $tmp.Result
                        if($found -ne $null) {$ins += $found.Instances}
                    }
                    if($provider -eq 'vmw' -or $provider -eq 'suitable') {
                        $found = @();
                        $tmp = Invoke-ThisCodeByAutoregions -provider 'vmw' -scriptStr ($nameAndDomainScript.Replace('{nameVal}', $nameVal).Replace('{tagCat}','domain')) -doNotInsertSpecialCode -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                        $found += $tmp.Result
                        if($found -ne $null) {
                            $found | Select -Unique | %{
                                $_ | Add-Member -MemberType NoteProperty -Name region -Value ($tmp.Region) -Force
                                $ins += $_
                            }
                        }
                    }
                }
                if($ins.Count -eq 0) {throw "(GetInstanceFromProvider): There is no Instance(s) found"}
                break;
            }
            'PrivateIp' {
                if($provider -eq 'aws' -or $provider -eq 'suitable') {
                    $found = Invoke-ThisCodeByAutoregions -scriptStr "Get-Ec2Instance -Filter (New-SMSEc2Filter -filter @{'private-ip-address'='$_'})" -doNotIgnoreEmptyResult -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    if($found -ne $null) {$ins += $found.Instances}
                }
                if($provider -eq 'vmw' -or $provider -eq 'suitable') {

                }
                break;
            }
        }
    }

    end {
        if($ins -ne $null -and $ins.Count -gt 0) {$ins | ?{$_ -ne $null}}
        else {$null}
    }
}

function Get-SMSInstance {
    [CmdletBinding(DefaultParameterSetName='InstanceId')]
    param(
        [parameter(ParameterSetName='InstanceId', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$InstanceId,
        [parameter(ParameterSetName='Instance', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.Instance[]]$Instance,
        [parameter(ParameterSetName='Reservation', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.Reservation[]]$Reservation,
        [parameter(ParameterSetName='Name', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,
        [parameter(ParameterSetName='PrivateIp', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$PrivateIp,
        [parameter(ParameterSetName='Domain', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Domain,
        [parameter(Mandatory=$false)]
        [switch]$OSInfo,
        [parameter(Mandatory=$false)]
        [switch]$WorkplaceInfo,
        [parameter(Mandatory=$false)]
        [switch]$DoNotLog,
        [parameter(Mandatory=$false)]
        [ValidateSet('aws', 'vmw', 'suitable')]
        [string]$Provider='suitable',
        [parameter(Mandatory=$false)][switch]$doNotContinueWhenFound
    )
    # --- Code ---
    begin {$ins = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            switch ($PSCmdlet.ParameterSetName) {
                'Instance' {
                    $ins += GetInstanceFromProvider -Instance $Instance -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'Reservation' {
                    $ins += GetInstanceFromProvider -Reservation $Reservation -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'InstanceId' {
                    $ins += GetInstanceFromProvider -InstanceId $InstanceId -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'Name' {
                    $ins += GetInstanceFromProvider -Name $Name -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'PrivateIp' {
                    $ins += GetInstanceFromProvider -PrivateIp $PrivateIp -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'Domain' {
                    $ins += GetInstanceFromProvider -Domain $Domain -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
            }
        }
        else {
            switch ($PSCmdlet.ParameterSetName) {
                'Instance' {
                    $ins = GetInstanceFromProvider -Instance $Instance -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'Reservation' {
                    $ins = GetInstanceFromProvider -Reservation $Reservation -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'InstanceId' {
                    $ins = GetInstanceFromProvider -InstanceId $InstanceId -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'Name' {
                    $ins = GetInstanceFromProvider -Name $Name -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'PrivateIp' {
                    $ins = GetInstanceFromProvider -PrivateIp $PrivateIp -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
                'Domain' {
                    $ins = GetInstanceFromProvider -Domain $Domain -Provider $Provider -doNotContinueWhenFound:($doNotContinueWhenFound.IsPresent)
                    break;
                }
            }
        }
    }
    end {
        $ins = ($ins | ?{$_ -ne $null})
        if($ins -ne $null) {
            $tmp = GetSmsInstance $ins
            if($OSInfo.IsPresent) {$tmp | Get-SMSOperatingSystem | Out-Null}
            if($WorkplaceInfo.IsPresent) {$tmp | Get-SMSWorkplaceInfo | Out-Null}
            $tmp
        }
        else {$null}
    }
    # --- Code ---
}

# =============================================================================
# ======= [SMS Security Group works] [sg.ps1] [2018-04-20 15:42:26 UTC] =======
# =============================================================================
function GetSMSSecurityGroup {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms
    )

    $sms | % {$_.__internal.SecurityGroups}
}

function Get-SMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms
    )
    # --- Code ---
    begin {$res = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += GetSMSSecurityGroup $_
        }
        else {
            $res = GetSMSSecurityGroup $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function ImportSMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [string]$path,
        [parameter(Mandatory=$true, position=1)]
        [string]$vpcId
    )

    if(Test-Path $Path) {
        $files = dir (Join-Path -Path $Path -Child '*.csv') | ? {!$_.PsIsContiner}
        if($files -ne $null) {

            foreach($f in $files) {
                $descr = '';
                $sgName = (Split-Path $f.FullName -Leaf).Replace('.csv', '')
                $tmp = Import-Csv $f.FullName -Encoding ascii
                foreach($t in $tmp) {
                    if([string]::IsNullOrEmpty($descr)) {$descr = $t.Descr}
                    $sgId = New-SMSSecurityGroup -Name $sgName -Permission (New-SMSIpPermission $t.IpProtocol $t.FromPort $t.ToPort ($t.IpRange.Split('|'))) -VpcId $vpcId -Descr $descr
                    if([string]::IsNullOrEmpty($sgId)) {throw "Can't create Security group with name [$sgName] using it's settings"}
                    else {$sgId}
                }
            }
        }
        else {throw "There is no necessary files in the directoery [$Path]"}
    }
    else {throw "There is no such directory [$Path]"}
}

function Import-SMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [string]$Path,
        [parameter(Mandatory=$true, position=1)]
        [string]$VpcId
    )
    # --- Code ---
    ImportSMSSecurityGroup $Path $VpcId
    # --- Code ---
}


function ExportSMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [string[]]$GroupId,
        [parameter(Mandatory=$true, position=1)]
        [string]$Path
    )

    $res = @()
    $sg = Invoke-ThisCode -ScriptBlk {Get-Ec2SecurityGroup -GroupId $GroupId}
    if($sg -ne $null) {
        if(!(Test-Path $Path)) { md $Path -Force -Confirm:$false | Out-Null}
        foreach($s in $sg) {
            $lines = @()
            $fName = $s.GroupName
            $descr = $s.Description

            foreach($p in $s.IpPermissions) {
                $range =  @()
                $range = StringsToString $p.IpRanges '|'
                $lines += "$($p.IpProtocol),$($p.FromPort),$($p.ToPort),$range,$descr"
            }

            $fullName = Join-Path -Path $path -Child "$fName.csv"
            'IpProtocol,FromPort,ToPort,IpRange,Descr' | Out-File $fullName -Encoding ascii
            $lines | % {$_ | Out-File $fullName -Append -Encoding ascii}
            $res += $fullName
        }
    }
    $res
}

function Export-SMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string[]]$GroupId,
        [parameter(Mandatory=$true, position=1)]
        [string]$Path
    )
    # --- Code ---
    begin {$res = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += ExportSMSSecurityGroup $_ $Path
        }
        else {
            $res = ExportSMSSecurityGroup $GroupId $Path
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function New-SMSIpPermission {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('tcp', 'udp')]
        [string]$Protocol,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [uint32]$FromPort,
        [parameter(Mandatory=$true, position=2)]
        [ValidateNotNullOrEmpty()]
        [uint32]$ToPort,
        [parameter(Mandatory=$true, position=3)]
        [ValidateNotNullOrEmpty()]
        [string[]]$IpRange
    )
    # --- Code ---
    $ip1 = New-Object Amazon.EC2.Model.IpPermission
    $ip1.IpProtocol = $Protocol
    $ip1.FromPort = $FromPort
    $ip1.ToPort = $ToPort
    $ip1.IpRanges.AddRange($IpRange)
    $ip1
    # --- Code ---
}

function NewSMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.IpPermission[]]$permission,
        [parameter(Mandatory=$true, position=2)]
        [ValidateNotNullOrEmpty()]
        [string]$vpcId,
        [parameter(Mandatory=$false, position=3)]
        [string]$descr
    )

    $sg = Invoke-ThisCode ScriptBlk {New-EC2SecurityGroup -VpcId $vpcId -GroupName $name -GroupDescription $descr}
    if($sg -ne $null) {
        Invoke-ThisCode -ScriptBlk {Grant-EC2SecurityGroupIngress -GroupId $sg -IpPermissions $permission | Out-Null}
    }
    $sg
}

function New-SMSSecurityGroup {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.IpPermission[]]$Permission,
        [parameter(Mandatory=$true, position=2)]
        [ValidateNotNullOrEmpty()]
        [string]$VpcId,
        [parameter(Mandatory=$false, position=3)]
        [string]$Descr
    )
    # --- Code ---
    NewSMSSecurityGroup -name $Name -permission $Permission -vpcId $VpcId -descr $Descr
    # --- Code ---
}

# =========================================================================
# ======= [SMS subnet works] [subnet.ps1] [2018-04-20 15:42:26 UTC] =======
# =========================================================================
function GetSMSSubnet {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms
    )

    $sms | % {
        $_.__internal.subnet;
    }
}

function Get-SMSSubnet {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += GetSMSSubnet $_
        }
        else {
            $res = GetSMSSubnet $sms
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

# =========================================================================
# ======= [SMS Volumes work] [volume.ps1] [2018-04-20 15:42:26 UTC] =======
# =========================================================================
function GetSMSVolume {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [string]$id,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    $sms | ForEach-Object {
        if(![string]::IsNullOrEmpty($id)) {
            try {$order = $id.ToUInt16($null)} catch{}
            switch($order) {
                $null {
                    $_.__internal.Volumes | Where-Object {$_.VolumeId -eq $id}
                    break;
                }
                {$order -in @(0..($_.__internal.Volumes.Count-1))} {
                    $_.__internal.Volumes[$order];
                    break;
                }
                default {$null; break;}
            }
        }
        else {
            $_.__internal.Volumes
        }
    }
}

function Get-SMSVolume {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('bject')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1, HelpMessage='It could be a VolumeId rather then Volume order in Volumes array')]
        [string]$id,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += GetSMSVolume $_ $id
        }
        else {
            $res = GetSMSVolume $sms $id
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function SetSMSVolume {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [object[]]$Volume,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][ValidateSet('type', 'size')]
        [string]$What,
        [parameter(Mandatory=$true, position=2)]
        [string]$Value,
        [parameter(Mandatory=$false, position=3)]
        [int]$Timeout = 180,
        [parameter(Mandatory=$false, position=4)]
        [switch]$alsoInOS= $true,
        [parameter(Mandatory=$false, position=5)]
        [bool]$Logging=$true
    )

    $volume | ForEach-Object {
        $ok =$false;
        switch($what) {
            'type' {$ok = $value -in @('gp2','io1','sc1','st1'); break;}
            'size' {try {$ok = $value.ToUInt32($null); $ok = $true;} catch{}}
        }
        if($ok) {
            $_.Set($what, $value, $timeout, $alsoInOS.IsPresent);
        }
        else {throw "Something wrong with parameters passed.[$($_.VolumeId)] [$what]=[$value]"}
    }
}

function Set-SMSVolume {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [Alias('disk')]
        [object[]]$Volume,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][ValidateSet('type', 'size')]
        [string]$What,
        [parameter(Mandatory=$true, position=2)]
        [string]$Value,
        [parameter(Mandatory=$false, position=3)]
        [int]$Timeout = 180,
        [parameter(Mandatory=$false, position=4)]
        [switch]$AlsoInOS = $true,
        [parameter(Mandatory=$false, position=5)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            SetSMSVolume $_ $What $Value $Timeout $AlsoInOS
            $res += $_
        }
        else {
            SetSMSVolume $volume $What $Value $Timeout $AlsoInOS
            $res = $volume
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function WaitSMSVolume {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateScript({$_.author -eq 'alex' -and $_.type -eq 'volume'})]
        [object[]]$volume,
        [parameter(Mandatory=$true, position=1)]
        [ValidateSet('available', 'creating','deleted','deleting','error','in-use')]
        [string]$State,
        [parameter(Mandatory=$false, position=2)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=3)]
        [bool]$Logging=$false
    )

    $volume | ForEach-Object {
        $cur = Get-Date
        Write-Verbose "Waiting the volume [$($volume.VolumeId)] for state [$State]"
        $tmp = $volume | Get-SMS -What State
        $delta = $cur - (Get-Date)
        while(
                ($tmp | Where-Object {$_ -ne $State}) -ne $null -and
                (($tmp | Where-Object {$_ -eq $State}).Count -ne $tmp.Count) -and
                [math]::Abs($delta.TotalSeconds) -lt $Timeout
            )
        {
            Start-Sleep 5;
            $tmp = $volume | Get-SMS -What State
            $delta = $cur - (Get-Date)
            Write-Verbose "Waiting the volume [$($volume.VolumeId)] for state [$State]. Current is [$($tmp)]"
        }
        if([math]::Abs($delta.TotalSeconds) -lt $Timeout) {$volume}
        else {throw "Timeout waiting Volume [$($volume.VolumeId)] for state [$State]"}
    }
}

function Wait-SMSVolume {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateScript({$_.author -eq 'alex' -and $_.type -eq 'volume'})]
        [Alias('disk')]
        [object[]]$volume,
        [parameter(Mandatory=$true, position=1)]
        [ValidateSet('available', 'creating', 'deleted', 'deleting', 'error', 'in-use')]
        [string]$State,
        [parameter(Mandatory=$false, position=2)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=3)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            WaitSMSVolume $_ $State $Timeout
            $res += $_
        }
        else {
            WaitSMSVolume $volume $State $Timeout
            $res = $volume
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function DisconnectSmsVolume {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [object[]]$volume,
        [parameter(Mandatory=$false, position=1)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=2)]
        [switch]$ForceDismount,
        [parameter(Mandatory=$false, position=3)]
        [bool]$Logging=$true
    )

    $volume | ForEach-Object {$_.Dismount($_.sms.instanceId, $timeout, $ForceDismount);}
}

function Disconnect-SMSVolume {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [Alias('disk')]
        [object[]]$volume,
        [parameter(Mandatory=$false, position=1)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=2)]
        [switch]$ForceDismount,
        [parameter(Mandatory=$false, position=3)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            DisconnectSmsVolume $_ $timeout $forceDismount
            $res += $_
        }
        else {
            DisconnectSmsVolume $volume $timeout $forceDismount
            $res = $volume
        }

    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}


function RemoveSMSVolume {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [object[]]$volume,
        [parameter(Mandatory=$false, position=1)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=2)]
        [switch]$ForceDismount,
        [parameter(Mandatory=$false, position=3)]
        [bool]$Logging=$true
    )

    $volume | ForEach-Object {
        if(![string]::IsNullOrEmpty($_.Attachments.InstanceId) -and $_.Sms -ne $null) {
            if($ForceDismount.IsPresent) {$_.Dismount($_.sms.instanceId, $timeout, $ForceDismount);}
            else {throw "Volume [$($_.VolumeId)] must be disconnected first. In order to do so in this commandlet use -Force key or use Disconnect-SMSVolume instead"}
        }
        $_.Delete();
    }
}
function Remove-SMSVolume {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [Alias('disk')]
        [object[]]$volume,
        [parameter(Mandatory=$false, position=1)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=2)]
        [switch]$ForceDismount,
        [parameter(Mandatory=$false, position=3)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            RemoveSMSVolume $_ $Timeout $ForceDismount
            $res += $_
        }
        else {
            RemoveSMSVolume $volume $Timeout $ForceDismount
            $res = $volume;
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

function NewSMSVolume {
    [CmdletBinding(DefaultParameterSetName='default', ConfirmImpact='Low')]
    param(
        [parameter(ParameterSetName='size')]
        [parameter(ParameterSetName='snapshotId')]
        [parameter(Mandatory=$false)]
        [ValidateSet('gp2','io1','sc1','st1')]
        [ValidateNotNullOrEmpty()]
        [string]$Type = 'gp2',

        [parameter(ParameterSetName='size', Mandatory=$true)]
        [ValidateNotNull()]
        [uint32]$Size,

        [parameter(ParameterSetName='snapshotId', Mandatory=$true)]
        [string]$SnapshotId,

        [parameter(ParameterSetName='volumeId', Mandatory=$true)]
        [string]$VolumeId,

        [parameter(Mandatory=$false)]
        [uint32]$Timeout,

        [parameter(Mandatory=$true)]
        [string]$Zone,

        [parameter(Mandatory=$false)]
        [hashtable]$Tag,

        [parameter(Mandatory=$false)]
        [bool]$Logging=$true
    )

    <# ... #>
}

function New-SMSVolume {
    [CmdletBinding(DefaultParameterSetName='default', ConfirmImpact='Low')]
    param(
        [parameter(ParameterSetName='size')]
        [parameter(ParameterSetName='snapshotId')]
        [parameter(Mandatory=$false)]
        [ValidateSet('gp2','io1','sc1','st1')]
        [ValidateNotNullOrEmpty()]
        [string]$Type = 'gp2',

        [parameter(ParameterSetName='size', Mandatory=$true)]
        [ValidateNotNull()]
        [uint32]$Size,

        [parameter(ParameterSetName='snapshotId', Mandatory=$true)]
        [string]$SnapshotId,

        [parameter(ParameterSetName='volumeId', Mandatory=$true)]
        [string]$VolumeId,

        [parameter(Mandatory=$false)]
        [uint32]$Timeout = 600,

        [parameter(Mandatory=$false)]
        [string]$Zone,

        [parameter(Mandatory=$false)]
        [hashtable]$Tag,

        [parameter(Mandatory=$false)]
        [switch]$DoNotLog
    )
    # --- Code ---
    if([string]::IsNullOrEmpty($Zone)) {$Zone = Get-SMSVar 'Zone'}
    switch ($PSCmdlet.ParameterSetName) {
        'size' {
            NewSMSVolume -Zone $Zone -Type $Type -Size $Size -Timeout $Timeout -Tag $Tag
            break;
        }
        'snapshotId' {
            NewSMSVolume -Zone $Zone -Type $Type -SnapshotId $SnapshotId -Timeout $Timeout -Tag $Tag
            break;
        }
        'volumeId' {
            NewSMSVolume -Zone $Zone -VolumeId $VolumeId -Timeout $Timeout -Tag $Tag
            break;
        }
    }
    # --- Code ---
}

function ConnectSMSVolume {
    param(
        [parameter(Mandatory=$true, position=0)]
        [object[]]$volume,
        [parameter(Mandatory=$true, position=1)]
        [object]$sms,
        [parameter(Mandatory=$false, position=2)]
        [string]$device = $null,
        [parameter(Mandatory=$false, position=3)]
        [int]$Timeout,
        [parameter(Mandatory=$false, position=4)]
        [bool]$Logging=$true
    )

    $volume | ForEach-Object {
        if([string]::IsNullOrEmpty($device)) {$device = "$($_.Attachments.Device)"}
        $_.Mount($sms, $device, $timeout);
    }
}

function Connect-SMSVolume {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.author -eq 'alex'})]
        [Alias('disk')]
        [object[]]$volume,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object]$sms,
        [parameter(Mandatory=$false, position=2)]
        [Alias('awsDevice')]
        [string]$device = $null,
        [parameter(Mandatory=$false, position=3)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=4)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            ConnectSMSVolume $_ $sms $device $timeout
            $res += $_;
        }
        else {
            ConnectSMSVolume $volume $sms $device $timeout
            $res = $volume;
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

# =====================================================================================
# ======= [SMS NetInterface works] [netInterface.ps1] [2018-04-20 15:42:26 UTC] =======
# =====================================================================================
function GetSMSNetInterface {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [string]$id
    )

    <# ... #>

}

function Get-SMSNetInterface {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1, HelpMessage='It could be a VolumeId rather then Volume order in Volumes array')]
        [string]$id
    )
    # --- Code ---
    begin {$res = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += GetSMSNetInterface $_ $id
        }
        else {
            $res = GetSMSNetInterface $sms $id
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

# ==================================================================================
# ======= [Work with SMS Snapshots] [snapshot.ps1] [2018-04-20 15:42:26 UTC] =======
# ==================================================================================
function New-SMSSnapshot {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$volumeId,
        [parameter(Mandatory=$false, position=1)]
        [uint32]$Timeout = 120,
        [parameter(Mandatory=$false, position=2)]
        [switch]$DoNotLog
    )
    # --- Code ---
    $snap = Invoke-ThisCode -ScriptBlk {New-Ec2Snapshot -VolumeId $volumeId}
    if($snap -ne $null) {
        $curr = Get-Date
        $state = (Invoke-ThisCode -ScriptBlk {Get-Ec2Snapshot -SnapshotId $snap.SnapshotId}).State.Value
        $delta = (Get-Date) - $curr
        while(
            ([math]::Abs($delta.TotalSeconds) -lt $Timeout) -and ($state -ne 'completed' -and $state -ne 'error')
        ) {
            Write-Verbose "Waiting for Snapshot [$($snap.SnapshotId)] for readyness"
            Sleep 5;
            $state = (Invoke-ThisCode -ScriptBlk {Get-Ec2Snapshot -SnapshotId $snap.SnapshotId}).State.Value
            $delta = (Get-Date) - $curr
        }
        if([math]::Abs($delta.TotalSeconds) -lt $Timeout) {
            if($state -eq 'completed') {
                Write-Verbose "Snapshot [$($snap.SnapshotId)] is ready"
                Invoke-ThisCode -ScriptBlk {Get-Ec2Snapshot -SnapshotId $snap.SnapshotId}
            }
            else {throw "Error creating a snapshot from [$VolumeId]. Current snapshot [$($snap.SnapshotId)] state is [$state]"}
        }
        else {throw "Waiting snapshot [$($snap.SnapshotId)] timeout"}
    }
    else {throw "Can't create snapshot from the VolumeId [$VolumeId]"}
    # --- Code ---
}

# ===============================================================================
# ======= [SMS PrivateIP works] [privateIp.ps1] [2018-04-20 15:42:26 UTC] =======
# ===============================================================================
function Set-SMSInstancePrivateIp {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true)][string]$ip
    )
    # --- Code ---
    begin {$res = @();}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $_.PrivateIp = $ip; $res +=$_;
        }
        else {
            $sms | ForEach-Object {$_.PrivateIp = $ip;}
            $res = $sms;
        }
    }
    end {
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

# ========================================================================
# ======= [SMS some functions] [any.ps1] [2018-04-20 15:42:26 UTC] =======
# ========================================================================
function Get-SMSScriptTemplate {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNull()][string]$Path
    )
    # --- Code ---
    $ret = @'
...
'@

    try {
        if(!(Test-Path $Path)) {md $Path;}
        $smsPath = Join-Path -Path $Path -Child 'SMS';
        if(!(Test-Path $smsPath)) {md $smsPath | Out-Null}

        $def = (Get-Module -Name 'alexCommon' | select Definition).Definition
        if(![string]::IsNullOrEmpty($def)) {
            $def | Out-File (Join-Path -Path $smsPath -Child 'AlexCommon.psm1') -Encoding ascii
            $def = (Get-Module -Name 'smsCommon' | select Definition).Definition
            if(![string]::IsNullOrEmpty($def)) {
                $def | Out-File (Join-Path -Path $smsPath -Child 'SmsCommon.psm1') -Encoding ascii
                DecompressString $ret | Out-File (Join-Path -Path $smsPath -Child 'ScriptTemplate.ps1') -Encoding ascii
                ZipFiles -ZipFileName (Join-Path -Path $Path -Child 'SmsBootstrap.zip') -SourceDir $smsPath
            }
        }
        else {log "Error finding [AlexCommon] PowerShell module. Check it is loaded."}
    }
    finally {
        del $smsPath -Force -Recurse -Confirm:$false
    }
    # --- Code ---
}

function Get-SMSAbout {
    [CmdletBinding(ConfirmImpact="Low")]
    param(
        [parameter(Mandatory=$false, position=0)][ValidateSet('all', 'ver', 'built')][string]$what = 'all'
    )

    switch($what) {
        'all' {'Single Management System (SMS) v0.6.7 Copyright (c) 2017-2018 OS33 os33@os33.com. Built 2018-04-20 15:42:28 UTC'; break;}
        'ver' {'0.6.7'; break;}
        'built' {'2018-04-20 15:42:28 UTC'; break;}
    }
}

# =============================================================================
# ======= [Just SMS Data. No code] [data.ps1] [2018-04-20 15:42:26 UTC] =======
# =============================================================================
$drivePurpose = @{
    'c' = 'System';
    'd' = 'Data';
    'e' = 'Data';
    'f' = 'Data';
    'g' = 'Data';
    'h' = 'Data';
    'i' = 'Data';
    'j' = 'Data';
    'k' = 'Data';
    'l' = 'Log';
    'p' = 'Page File';
    'r' = 'Archives';
    't' = 'Temporary drive';
    'v' = 'VSS Copies';
}

$RoleData = @{
    'Mb2008' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet='AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 'm4.large';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_GLOBAL_PORTAL', 'SG_GLOBAL_MANAGEMENT');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = 'MaxRooms';
        ProdKeypair='instance-deployment';
    };
    'Mb2012' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet='AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 'm4.large';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_GLOBAL_PORTAL', 'SG_GLOBAL_MANAGEMENT');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = '';
        ProdKeypair='instance-deployment';
    };
    'Fs' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet = 'AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 'm4.large';
        ProdSG=@('SG_{DomainShort}_ALL', '1', 'SG_2');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = 'MaxRooms';
        ProdKeypair='instance-deployment';
    };
    'Be' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet = 'AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 'm4.large';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_1', 'SG_2');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = 'MaxRooms';
        ProdKeypair='instance-deployment';
    };
    'FirstDc' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet = 'AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 't2.medium';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_1', 'SG_2');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = '';
        ProdKeypair='instance-deployment';
    };
    'Dc' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet = 'AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 't2.medium';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_1', 'SG_2');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = '';
        ProdKeypair='instance-deployment';
    };
    'XenApp' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet = 'AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 'm4.xlarge';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_1', 'SG_2');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = 'MaxRooms';
        ProdKeypair='instance-deployment';
    };
    'Vda64' = @{
        DevImage = 'Core-Team-2012-R2';
        DevInstanceType = 't2.medium';
        DevSG=@('WKS-DEV3');
        DevSubnet = 'AWS-FR-DEV3_WKS_SUBNET';
        DevDedicatedHost = '';
        DevKeypair = 'aivanov';

        ProdImageName = 'OS33_2012R2_GENERAL'
        ProdInstanceType = 'm4.xlarge';
        ProdSG=@('SG_{DomainShort}_ALL', 'SG_1', 'SG_2');
        ProdSubnet = '{DomainLong}';
        ProdDedicatedHost = 'MaxRooms';
        ProdKeypair='instance-deployment';
    };
}

$runCmdStatusDetail = @{
    'Pending' = 'The command has not been sent to any instances.';
    'InProgress' = 'The command has been sent to at least one instance but has not reached a final state on all instances.';
    'Success' = 'The command successfully executed on all invocations. This is a terminal state.';
    'DeliveryTimedOut' = 'The value of MaxErrors or more command invocations shows a status of Delivery Timed Out. This is a terminal state.';
    'ExecutionTimedOut' = 'The value of MaxErrors or more command invocations shows a status of Execution Timed Out. This is a terminal state.';
    'Failed' = 'The value of MaxErrors or more command invocations shows a status of Failed. This is a terminal state.';
    'Incomplete' = 'The command was attempted on all instances and one or more invocations does not have a value of Success but not enough invocations failed for the status to be Failed. This is a terminal state.';
    'Canceled' = ' The command was terminated before it was completed. This is a terminal state.';
    'RateExceeded' = 'The number of instances targeted by the command exceeded the account limit for pending invocations. The system has canceled the command before executing it on any instance. This is a terminal state.';
}

# If I didn't find CpuCore from oficial sites, I'v "invent" it below.
$instancesSpec = @{
    <# ... #>
}

# =======================================================================================
# ======= [New SMS Instance creation] [newInstance.ps1] [2018-04-20 15:42:26 UTC] =======
# =======================================================================================
function Get-SMSDrivePurpose {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$Letter
    )
    # --- Code ---
    if($letter -in $drivePurpose.Keys) {
        $drivePurpose.$Letter
    }
    else {$null}
    # --- Code ---
}

function Get-SMSRoleData {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$Role,
        [parameter(Mandatory=$false, position=1)][ValidateNotNullOrEmpty()][ValidateSet('Dev','Prod')][string]$Environment = 'Prod'
    )
    # --- Code ---
    $res = @{}
    if($Role -in $RoleData.Keys) {
        $all = $RoleData.$Role; $first = $true;
        foreach($k in $all.Keys) {
            if($k.StartsWith($Environment)) {
                if($first) {$res = @{$k.TrimStart($Environment) = $all.$k} }
                else {$res.Add($k.TrimStart($Environment), $all.$k);}
            }
            $first = $false;
        }
        $res;
    }
    else {$null}
    # --- Code ---
}

function Get-OsImage {
    param(
        [parameter(Mandatory=$false)][string]$region,
        [parameter(Mandatory=$false)][string[]]$name
    )

    if([string]::IsNullOrEmpty($region)) {$region = Get-SMSVar 'Region'}
    $provider = Get-SMSProviderFromRegion -region $region
    switch($provider) {
        'aws' {GetImageAWS -region $region -name $name; break;}
        'vmw' {GetImageVMW -region $region -name $name; break;}
    }
}

function GetImageVMW {
    param(
        [parameter(Mandatory=$true, position=0)][string]$region,
        [parameter(Mandatory=$false, position=1)][string[]]$name
    )

    if((Connect-SMSVMWare -Region $region -ConnectToProperRegion)) {
        if([string]::IsNullOrEmpty($name)) {Get-Template -Name $name}
        else {Get-Template}
    }
    else {throw "(GetImageVMW): Can't connect to the region [$region]"}
}

function GetImageAWS {
    param(
        [parameter(Mandatory=$true, position=0)][string]$region,
        [parameter(Mandatory=$false, position=1)][string[]]$name
    )

    $res = @()
    $res += GetImageWithSingleOwner -region $region -name $name -owner 'self'
    if($res.Count -eq 0) {
        $res += GetImageWithSingleOwner -region $region -name $name -owner 'amazon'
    }
    $res;
}

function GetImageWithSingleOwner {
    param(
        [parameter(Mandatory=$true, position=0)][string]$region,
        [parameter(Mandatory=$false, position=1)][string[]]$name,
        [parameter(Mandatory=$false, position=2)][ValidateSet('amazon', 'self')][string]$owner = 'self'
    )

    toLog "Getting appropriate image from the owner: [$owner]" 'semi'
    $res = @()
    try {
        if(![string]::IsNullOrEmpty($name)) {
            $name | % {
                $g = Invoke-ThisCode -ScriptBlk {Get-EC2Image -Region $region -Owner $owner -Filter (New-SMSEc2Filter @{'name'=$_}) -ErrorAction SilentlyContinue};
                if($g -ne $null) {$res += $g}
            }
        }
        else {$res = Invoke-ThisCode -ScriptBlk {Get-EC2Image -Region $region -Owner '$owner' -ErrorAction SilentlyContinue}}
    }
    catch {throw}
    $res;
}

function GetSG {
    param(
        [parameter(Mandatory=$false, position=0)][string]$region,
        [parameter(Mandatory=$false, position=1)][string[]]$name
    )

    toLog 'Getting appropriate Security Groups...' 'semi'
    $res = @();
    if([string]::IsNullOrEmpty($region)) {$region = Get-SMSVar 'Region'}
    try {
        if(![string]::IsNullOrEmpty($name)) {$name | % {$s = Invoke-ThisCode -ScriptBlk {Get-EC2SecurityGroup -Region $region -Filter (New-SMSEc2Filter @{'group-name'=$name})}; if($s -ne $null) {$res += $s}}}
        else {$res = Invoke-ThisCode -ScriptBlk {Get-EC2SecurityGroup -Region $region}}
        toLog 'Security Groups finish' 'semi'
    }
    catch {throw}
    $res
}

function GetSubnet {
    param(
        [parameter(Mandatory=$true, position=0)][string]$zone,
        [parameter(Mandatory=$false, position=1)][string]$name
    )

    toLog 'Getting appropriate Subnets...' 'semi'
    $region = Get-SMSRegionFromZone $Zone
    try {
        if([string]::IsNullOrEmpty($name)) {Invoke-ThisCode -ScriptBlk {Get-EC2Subnet -Region $region -Filter (New-SMSEc2Filter @{'availabilityZone'=$Zone})}}
        else {Invoke-ThisCode -ScriptBlk {Get-EC2Subnet -Region $region -Filter (New-SMSEc2Filter @{'availabilityZone'=$Zone; 'tag:Name'=$name})}}
        toLog 'Subnets finish' 'semi'
    }
    catch {throw}
}

function GetKeypair {
    param(
        [parameter(Mandatory=$false, position=0)][string]$region,
        [parameter(Mandatory=$false, position=1)][string]$name
    )

    toLog 'Getting appropriate Keypair' 'semi'
    if([string]::IsNullOrEmpty($region)) {$region = Get-SMSVar 'Region'}
    try {
        if(![string]::IsNullOrEmpty($name)) {Invoke-ThisCode -ScriptBlk {Get-Ec2KeyPair -Region $region -KeyName $name}}
        else {Invoke-ThisCode -ScriptBlk {Get-Ec2KeyPair -Region $region}}
        toLog 'Keypair finish' 'semi'
    }
    catch {throw}
}

function ResolveSMSRoleData {
    param(
        [parameter(Mandatory=$true, Position=0)][ValidateNotNullOrEmpty()][string]$Zone,
        [parameter(Mandatory=$true, Position=1)][ValidateNotNullOrEmpty()][object]$RoleName,
        [parameter(Mandatory=$true, Position=2)][ValidateNotNullOrEmpty()][string]$Fqdn,
        [parameter(Mandatory=$false, position=3)][ValidateSet('Dev','Prod')][string]$Environment = 'Prod',
        [parameter(Mandatory=$false, Position=4)][string]$KeyPairName,
        [parameter(Mandatory=$false, Position=5)][string]$ImageName
    )
    # --- Code ---
    $rd = Get-SMSRoleData $RoleName $Environment
    if($rd -ne $null) {
        $rd = Copy-PsObject $rd
        $Region = Get-SMSRegionFromZone $Zone
        $Provider = Get-SMSProviderFromRegion -Region $Region

        # ImageName
        if(![string]::IsNullOrEmpty($ImageName)) {$rd.ImageName= $ImageName}
        $rd.Image = Get-OsImage -Region $region -Name $rd.ImageName

        switch($Provider) {
            'aws' {
                $origCnt = $rd.SG.Count;
                # Security Groups
                for($i=0; $i -lt $rd.SG.Count; $i++) {
                    $rd.SG[$i] = $rd.SG[$i].Replace('{DomainShort}', (DomainShortFromFqdn $Fqdn))
                    $rd.SG[$i] = $rd.SG[$i].Replace('{DomainLong}', (DomainFromFqdn $Fqdn))
                    $rd.SG[$i] = GetSG $region $rd.SG[$i]
                }
                $rd.SG = $rd.SG | ? {![string]::IsNullOrEmpty($_)}
                if($origCnt -eq $rd.SG.Count) {
                    # Subnets
                    $rd.Subnet = $rd.Subnet.Replace('{DomainShort}', (DomainShortFromFqdn $Fqdn))
                    $rd.Subnet = $rd.Subnet.Replace('{DomainLong}', (DomainFromFqdn $Fqdn))
                    $rd.Subnet = GetSubnet $zone $rd.Subnet
                    # KeyPairName
                    if(![string]::IsNullOrEmpty($KeyPairName)) {$rd.KeyPair = $KeyPairName}
                    $rd.KeyPair = (GetKeypair $region $rd.KeyPair).KeyName

                    $rd
                }
                else {$null}
                break;
            }
            'vmv' {

                break;
            }
        }
    }
    else {$null}
    # --- Code ---
}

function Import-SMSNewServerData {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$Csv,
        [parameter(Mandatory=$true, position=1)][ValidateNotNull()][System.Management.Automation.PSCredential]$Credential,
        [parameter(Mandatory=$false, position=2)][string]$Delimiter = ','
    )
    # --- Code ---
    $res = @();
    if(Test-Path $Csv) {
        # ---Check for available columns ---
        $keys = @('Zone','Role','Fqdn','Ip','ImageName','DedicatedHost','KeypairName','Description')
        $all = Import-Csv $Csv -Delimiter $Delimiter
        $csvNames =  ($all | gm -MemberType NoteProperty).Name
        $keys | % {if($_ -notin $csvNames) {throw "Csv file can't contains the [$_] column name."}}
        # ----------------------------------

        $all | % {
            $disks = @(); $record = $_
            if ($record.DedicatedHost -notin @('FirstAvailable','MinRooms','MaxRooms','All', '')) {throw "DedicatedHost field must be empty or one of the followed: FirstAvailable, MinRooms, MaxRooms, All or <Empty>"}
            $csvDisks = $csvNames | ? {$_.ToLower().StartsWith('disk')}
            if($csvDisks.Count -gt 0) {
                $csvDisks | % {
                    if(![string]::IsNullOrEmpty($record.$_)) {
                        $letter = $_.Substring($_.length-1, 1)
                        if($letter -ne 'P' -and $letter -ne 'V') {
                            $company = $null; $size = '';
                            $val = $record.$_.Split('/')
                            if($val.Count -eq 1) { $size=$val[0].ToUint32($null)}
                            elseif($val.Count -eq 2) {$company=$val[0]; $size = $val[1].ToUint32($null)}
                            else {throw "Invalid record in CSV file: [$($record | Out-String)]. Check drive(s) definition"}
                            $disks += @{Letter=$letter.ToUpper(); Company=$company; Size=$size;}
                        }
                    }
                }
            }
           $res += ConvertTo-SMSNewServerRecord -Zone $record.Zone -Role $record.Role -Fqdn $record.Fqdn -Ip $record.Ip -ImageName $record.ImageName -DedicatedHost $record.DedicatedHost -KeypairName $record.KeyPairName -Description $Description -Disk $disks -Credential $Credential
        }
        $res;
    }
    else {throw "(Import-SMSNewServerData): There is no such file [$fileName]"}
    # --- Code ---
}
function ConvertTo-SMSNewServerRecord {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)][ValidateSet('Mb2008', 'Mb2012', 'Fs', 'Be','FirstDc', 'Dc', 'XenApp', 'Vda64')][ValidateNotNullOrEmpty()][string]$Role,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][string]$Fqdn,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()][System.Management.Automation.PSCredential]$Credential,
        [parameter(Mandatory=$false)][string]$Ip = $null,
        [parameter(Mandatory=$false)][string]$ImageName = $null,
        [parameter(Mandatory=$false)][string]$DedicatedHost = '',
        [parameter(Mandatory=$false)][string]$KeypairName = $null,
        [parameter(Mandatory=$false)][string]$Description = $null,
        [parameter(Mandatory=$false)][hashtable[]]$Disk = $null, # {Letter, Size, Company}
        [parameter(Mandatory=$false)][string]$Zone = $null
    )
    # --- Code ---
    New-Object PSObject -Property @{Zone=$Zone; Role=$Role; Fqdn=$Fqdn; Credential=$Credential; Ip=$ip; ImageName=$ImageName; DedicatedHost=$DedicatedHost; KeyPairName=$KeyPairName; Description=$Descriprion; Disk=$Disk}
    # --- Code ---
}

function CheckDataValid {
    param(
        [parameter(Mandatory=$false, position=0)][ValidateNotNullOrEmpty()]$region,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]$roleData,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()]$serverRecord
    )

    if([string]::IsNullOrEmpty($region)) {$region = Get-SMSVar 'Region'}
    switch((Get-SMSProviderFromRegion $serverRecord.Zone)) {
        'aws' {
            CheckDataValidAWS $region $roleData $serverRecord
            break;
        }
        'vmw' {
            CheckDataValidVMW $region $roleData $serverRecord
            break;
        }
        default {
            throw "(CheckDataValid): Unknown Region [$(Get-SMSProviderFromRegion $serverRecord.Zone)]"
        }
    }
}

function CheckDataValidVMW {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$region,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]$roleData,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()]$serverRecord
    )

    if($roleData.Image -eq $null) {throw "(CheckDataValidVMW): There is no valid AMI Image defined"}

    if($serverRecord -ne $null) {
        if(![string]::IsNullOrEmpty($serverData.Ip)) {
        }
    }
}

function CheckDataValidAWS {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$region,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]$roleData,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()]$serverRecord
    )

    if($roleData.Image -eq $null) {throw "(CheckDataValidAWS): There is no valid AMI Image defined"}
    if($roleData.Subnet -eq $null) {throw "(CheckDataValidAWS): There is no valid Subnet defined"}
    if($roleData.SG -eq $null) {throw "(CheckDataValidAWS): There is no valid Security Group(s)"}
    if($roleData.KeyPair -eq $null) {throw "(CheckDataValidAWS): There is no valid KeyPair defined"}

    if($serverRecord -ne $null) {
        if(![string]::IsNullOrEmpty($serverData.Ip)) {
            # Is IP valid?
            if(!(Test-IPValid $serverData.Ip)) {throw "IP address [$($serverData.Ip)] has invalid format"}
            # Is IP belongs to our Subnet?
            if(!($serverData.Ip -in (Get-NetworkRangeSimple -IP $roleData.Subnet.CidrBlock))) {throw "Requested IP Address [$($serverData.Ip)] does not belong to [$($roleData.Subnet.CidrBlock)]"}
            # Is IP already used?
            $networkInterfaces = Invoke-ThisCode -ScriptBlk {Get-EC2NetworkInterface -Region $region | Where-Object {$_.SubnetId = ($roleData.Subnet.SubnetId)}}
            if($networkInterfaces -and $networkInterfaces.Count -gt 0) {
                foreach($n in $networkInterfaces) {
                    if($n.PrivateIpAddress -eq $serverData.Ip) {throw "You request IP [$($serverData.Ip)] that already used in Network interface Id=[$($n.NetworkInterfaceId)] with Description [$($n.Description)]";}
                }
            }
        }
    }
}

function OverwriteFromCommandletParamsAWS {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$region,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]$roleData,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()]$serverRecord
    )

    if(![string]::IsNullOrEmpty($serverRecord.ImageName)) {$roleData.Image = Get-OsImage -region $region -Name $serverRecord.ImageName;}

    $provider = Get-SMSProviderFromRegion -region $region
    switch($provider) {
        'aws' {
            if(![string]::IsNullOrEmpty($serverRecord.DedicatedHost)) {
                if(($serverRecord.DedicatedHost.ToString().ToLower()) -eq '<none>') {$roleData.DedicatedHost = ''}
                else {$roleData.DedicatedHost = $serverRecord.DedicatedHost}
            }
            if(![string]::IsNullOrEmpty($serverRecord.KeyPairName)) {$roleData.KeyPair = (GetKeypair $region $serverRecord.KeyPairName).KeyName}
            break;
        }
        'vmw' {
            break;
        }
    }
}

function CalcVDrive {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$serverRecord
    )

    $total = 0;
    if($serverRecord.Disk -ne $null) {
        $serverRecord.Disk | % {
            # if(![string]::IsNullOrEmpty($_.Company)) {
                if([math]::Truncate($_.Size * 5 / 100) -gt 0) {$total += $_.Size}
                else {$total += 20;}
            # }
        }
    }
    if($total -gt 0) {
        $vssSize = $total * 5 / 100;
        if($vssSize -lt 1) {$vssSize = 1;}
        $vssDriveSize = $vssSize + ($vssSize * 12 / 100);
        if($vssDriveSize -le 2) {$vssDriveSize = 2;}
        if(($vssDriveSize - [int]$vssDriveSize) -gt 0) {$size = [int]($vssDriveSize) + 1;}
        else {$size = [int]($vssDriveSize)}
        if($size -eq 0) {$size = 1;}
        $serverRecord.Disk += @{Letter='V'; Size=$size; Company=''}
    }
}

# ------------------------- WC compatibility support functions start -----------------------
function RoleToWCRole {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$role
    )

    $qqq = @{
        'Dc' = 'AD domain controller';
        'Fs' = 'File server';
        'Sql' = 'SQL Server';
        'Vda64' = 'XenApp Delivery Controller';
        'XenApp' = 'XenApp';
        'Be' = 'Backend custom server'
    }
    $qqq.$role
}

function DiskRoleFromLetter {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$letter
    )

    $qqq = @{
        'c' = 'os';
        'd' = 'data'; 'e' = 'data'; 'f' = 'data'; 'g' = 'data'; 'h' = 'data'; 'i' = 'data'; 'j' = 'data'; 'k' = 'data';
        'l' = 'log';
        'p' = 'page';
        'v' = 'vss';
        't' = 'tempdb';
    }

    $qqq.$letter
}

function GetBusNumAndTargetIdForWC {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$letter
    )

    @{
        BusNumber = 0;
        TargetId = [system.Text.Encoding]::UTF8.GetBytes($letter.ToLower())[0] - 97;
        Lun = 0;
    }
}

function ConvertTempCredToWC {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$tmpCred
    )

    @{AccessKeyId=$tmpCred.tmpAccessKey; SecretAccessKey=$tmpCred.tmpSecretKey; SessionToken=$tmpCred.tmpSessionToken}
}

function CreateAndCallWCMagicFunction {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$roleData,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]$serverRecord,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()]$tmpCred
    )

    # Network interface
    $networks = @()
    if(![string]::IsNullOrEmpty($serverRecord.Ip)) {
        $net = @{private_ip=$null; gateway=$null; dns=$null;}
        $net.private_ip = $serverRecord.Ip
        $net.gateway = CalculateFromIp $serverRecord.Ip 'router'
        $net.dns = CalculateFromIp $serverRecord.Ip 'dns'
        $networks += $net;
    }

    # Disks
    $disks = @()
    if($serverRecord.Disk.Count -gt 0) {
        for($i= 0; $i -lt $serverRecord.Disk.Count; $i++) {
            $bt = GetBusNumAndTargetIdForWC $serverRecord.Disk[$i].Letter
            $disk = @{role=$null; size_gb=$null; bus_number=$null; target_id=$null;}
            $disk.role = DiskRoleFromLetter $serverRecord.Disk[$i].Letter
            $disk.size_gb = $serverRecord.Disk[$i].Size
            $disk.bus_number = $bt.BusNumber;
            $disk.target_id = $bt.TargetId;
            $disk.lun = $bt.Lun;
            $disks += $disk
        }
    }

    $wcCredentials = @{
        DomainJoinUser = @{
            Password=(UnsecureString ($serverRecord.Credential.Password))
            Username=$serverRecord.Credential.UserName
        }
    }

    # Below function is $(Get-Variable Invoke-wpSMSProvisioning ("$($SMSPrefix)wc_cat_magicFunction" -ValueOnly))
    # This function must return Cfg for providing it to the UserData code (see. CreateEmbeddedWpScript)
    $runStr = Get-SMSVar 'wc_cat_magicFunction'
    $runStr += ' -Environment (Get-Variable "$($SMSPrefix)Environment" -ValueOnly)'
    $runStr += ' -AwsTempLogin (ConvertTempCredToWC $tmpCred)'
    # $runStr += ' -InitialConfiguration $true'
    $runStr += ' -DomainName (DomainFromFqdn $serverRecord.fqdn)'
    $runStr += ' -ServerName (CompFromFqdn $serverRecord.fqdn)'
    $runStr += ' -ServerRoles @((RoleToWCRole $serverRecord.Role))'
    $runStr += ' -NetworkInterfaces $networks'
    $runStr += ' -Disks $disks'
    $runStr += ' -Region (Get-SMSRegionFromZone $serverRecord.Zone)'
    $runStr += ' -Credentials $wcCredentials'
    try {
        .([scriptblock]::Create($runStr))
    }
    catch {
        log "Run [$(Get-SMSVar 'wc_cat_magicFunction')] exception. [$($_.ToString())]" 'exception'
        $null
    }
}

function CreateEmbeddedWpScript {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$roleData,
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()]$serverRecord
    )

    $cred = (Get-AWSCredentials -ProfileName $myEnv).GetCredentials()
    $tmpCred = Get-AwsTempLogin $cred.AccessKey $cred.SecretKey 'us-east-1'
    CreateAndCallWCMagicFunction $roleData $serverRecord $tmpCred
}

# ------------------------- WC compatibility support functions end   -----------------------

function ConvertWcCodeToWC {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$wcCode
    )

    $lines = $wcCode.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)
    $lines = $lines | % {$_ = $_.Trim(); $_} | ?{!($_.StartsWith('#'))}
    if(![string]::IsNullOrEmpty($lines)) {
        [scriptblock]::Create(($lines | Out-String))
    }
    else {$null}
}

function DownloadWCCode {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]$provider
    )

    # We are interested just in Invoke-wpSMSProvisioning function.
    #if((dir "function:$(Get-SMSVar 'wc_cat_magicFunction')" -ErrorAction SilentlyContinue) -eq $null) {
        try {
            $cred = (Get-AWSCredentials -ProfileName $myEnv).GetCredentials()
            $tmpCred = Get-AWSTempLogin $cred.AccessKey $cred.SecretKey (Get-SMSVar 'wc_cat_region') 900
            $wcCode = Get-S3 -Region (Get-SMSVar 'wc_cat_region') -AccessKey $tmpCred.tmpAccessKey -SecretKey $tmpCred.tmpSecretKey -SessionToken $tmpCred.tmpSessionToken -s3Path (Get-SMSVar 'wc_cat_codeBase') -Decompress $false -AsString $true
            if(!([string]::IsNullOrEmpty($wcCode))) {
                [scriptblock]$sb = ConvertWcCodeToWC $wcCode
                return $sb
            }
            else {throw "Dowload WC Error: File is empty or error downloaing it"}
        }
        catch {
            log "Dowload WC Error: Something went in wrong way. Let me guess... something wrong with WC code file. [$($_.ToString())]" 'exception'
        }
    #}
}

function NewSMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$NewServerRecord,
        [parameter(Mandatory=$false, position=1)]
        [bool]$WithoutWC=$false,
        [parameter(Mandatory=$false, position=2)]
        [bool]$Logging=$true
    )

    <#
    $NewServerRecord:
    [string] Zone - could be ommited. In this case (Get-SMSVar 'Zone') will be used
    [string] Role <Mb2008, Mb2012, Fs, Be, FirstDc, Dc, XenApp, Vda64> - must have
    [string] Fqdn - must have
    [credential] DomainCred  - must have
    [string] Ip - could be ommited
    [string] Ou - could be ommited
    [string] ImageName - could be ommited. It needs to overwrite defaults
    [string] Dedicated - could be ommited. It needs to overwrite defaults
    [string] KeyPairName - could be ommited. It needs to overwrite defaults
    [string] Description - could be ommited
    [hashtable] Disks
        [string] Letter - must have
        [uint32] Size - must have
        [string] Company
    #>

    if($logging) {$logType = 'info'} else {$logType = 'rl'}
    try {
        # Check Data valid
        foreach($new in $NewServerRecord) {
            log "Doing preparation for creation [$($new.Fqdn)]" $logType
            if([string]::IsNullOrEmpty($new.Zone)) {$new.Zone = Get-SMSVar 'Zone'}
            $provider = Get-SMSProviderFromRegion -region (Get-SMSRegionFromZone $new.Zone)

            if($provider -ne 'unknown') {
                # Get Role data
                $rd = ResolveSMSRoleData -Zone $new.Zone -RoleName $new.Role -Fqdn $new.Fqdn -Environment (Get-SMSVar 'Environment') -KeyPairName $new.KeyPairName -ImageName $new.ImageName
                # Overwrites Role data from Commandlet parameters
                OverwriteFromCommandletParamsAWS (Get-SMSRegionFromZone $new.Zone) $rd $new
                # Checks
                Invoke-ThisCode -scriptBlk {CheckDataValid (Get-SMSRegionFromZone $new.Zone) $rd $new} # if something is invalid then exception will thrown from CheckDataValid function
                $new | Add-Member -MemberType NoteProperty -Name Wrong -Value $false
            }
            else {
                $new | Add-Member -MemberType NoteProperty -Name Wrong -Value $true
                log "Unknown provider for the Zone: [$($new.Zone)] Server FQDN: [$($new.Fqdn)]. This entry will not used" $logType
            }

            log "Preparation done for [$($new.Fqdn)]" $logType
        }
        # Cut wrong entries
        $NewServerRecord = $NewServerRecord | ? {!($_.Wrong)}

        foreach($new in $NewServerRecord) {
            switch(Get-SMSProviderFromRegion (Get-SMSRegionFromZone $new.Zone)) {
                'aws' {
                    log "Creating a new Instance for [$($new.Fqdn)] Role [$($new.Role)] Image: [$($rd.Image.ImageId)] Keypair: [$($rd.keyPair)] Type: [$($rd.InstanceType)]" $logType
                    $runStr = 'New-EC2Instance -DisableApiTermination $true -ImageId $rd.Image.ImageId -MinCount 1 -MaxCount 1 -KeyName $rd.keyPair -SecurityGroupIds $rd.SG.GroupId -InstanceType $rd.InstanceType -SubnetId $rd.subnet.SubnetId -Region "' + (Get-SMSRegionFromZone $new.Zone) + '"';
                    if(![string]::IsNullOrEmpty($new.Ip)) {$runStr += ' -PrivateIpAddress $new.Ip.Split("/")[0]'; log "IP: [$($new.Ip)]" $logType}
                    # Run PowerShell Policy
                    if((Get-SMSVar 'Environment') -eq 'Prod') {$runStr += ' -InstanceProfile_Name Run-Powershell-Instances'}
                    else {$runStr += ' -InstanceProfile_Name RunPowershellInstances'}
                    # DedicatedHost
                    if(![string]::IsNullOrEmpty($rd.DedicatedHost)) {
                        $host = Invoke-ThisCode -scriptBlk {Get-SMSDedicatedHost $rd.InstanceType MaxRooms $new.Zone}
                        if($host -ne $null) {
                            $runStr += ' -Tenancy host -HostId ' + $host.HostId
                            log "Dedicated Host: [$($host.HostId)]" $logType
                        }
                        else {throw "There is not enough rooms on dedicatd hosts of type [$($rd.InstanceType)]"}
                    }

                    # Add drives
                    $spec = Get-SMSInstanceSpecification $rd.InstanceType
                    # P:
                    $new.Disk += @{Letter='P'; Size=([math]::Round($spec.ram * 1.5 + ($spec.ram * 1.5 / 100 * 11))); Company=''}
                    # V:
                    if($new.Role -eq 'Fs') {CalcVDrive $new}

                    if($WithoutWC -eq $false) {
                         # --- Initializing WC start ---
                        toLog 'UserData Invoked' 'warning';
                         # --- Get WC logic. Main function is: Invoke-wpSMSProvisioning ("$($SMSPrefix)wc_cat_magicFunction") ---
                        if(
                            $WithoutWC -eq $false -or
                            (dir "function:$(Get-SMSVar 'wc_cat_magicFunction')" -ErrorAction SilentlyContinue) -eq $null
                        ) {
                            $sb = DownloadWCCode (Get-SMSProviderFromRegion (Get-SMSVar 'Region')) # We use a default region because at this point we don't know which ones will be used
                            if($sb -ne $null) {Invoke-Command -ScriptBlock $sb -NoNewScope}
                            else {throw "Error in WC code during integration into SMS"}
                        }
                        # ------------------------------------------------------------------------------------------------------
                        $runStr += ' -UserData (CreateEmbeddedWpScript $rd $new)';
                        # --- Initializing WC end   ---
                    }
                    else {toLog 'UserData is not used' 'warning'}

                    # --- Code invocation ---
                    $reservation = Invoke-ThisCode -scriptStr $runStr
                    # -----------------------

                    if($reservation -ne $null) {
                        log "New Instance for [$($new.Fqdn)] with role [$($new.Role)] has been created. Doing postpreparation" $logType
                        $sms = Get-SMSInstance -InstanceId $reservation.Instances.InstanceId -Provider 'aws' -doNotContinueWhenFound
                        Invoke-ThisCode -scriptBlk {$sms | Wait-SMSInstance -State 'running' -Status 'initializing' -Timeout 120 | Add-SMSTag -Tag @{Name=$new.Fqdn.ToLower(); env='prod-us'; tier='customer'; domain=(DomainFromFqdn $new.Fqdn); department='core';} | Out-Null}
                        # Adding a Drives
                        $new.Disk | % {
                            if($_.Size -gt 0) {
                                log "Creating a new volume(s) Drive: [$($_.Letter)] Size: [$($_.Size)] and tagging them" $logType
                                $vol = Invoke-ThisCode -scriptBlk {New-SMSVolume -Zone $new.Zone -Type gp2 -Size $_.Size -Tag @{Name=$new.Fqdn.ToLower(); Letter=$_.Letter} | Connect-SMSVolume -sms $sms -device "xvd$($_.Letter.ToLower())"}
                                if(![string]::IsNullOrEmpty($_.Company)) {Invoke-ThisCode -scriptBlk {$vol | Add-SMSTag -Tag @{company=$_.Company} | Out-Null}}
                            }
                        }
                        $sms = Get-SMSInstance -InstanceId $reservation.Instances.InstanceId -Provider 'aws' -doNotContinueWhenFound
                        $sms | % {Invoke-ThisCode -scriptBlk {$_.DrivesDeleteOnTermination = $true}}
                        $sms
                    }
                    else {
                        log "Error during New Instance creation [$($new.fqdn)] with role [$($new.Role)]. No instance(s) was created" 'error'
                        $null
                    }
                }
                'vmw' {

                }
            }
            $new = $null;
        }
    }
    finally {
        Save-SMSRemoteLog;
    }
}

function New-SMSInstance {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$NewServerRecord,
        [parameter(Mandatory=$false)]
        [switch]$WithoutWC,
        [parameter(Mandatory=$false)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $NewServerRecord}
    }
    end {
        # in the real world (!$WithoutWC.IsPresent) should be changed to $WithoutWC.IsPresent
        NewSMSInstance $toProcess $WithoutWC.IsPresent (!$DoNotLog.IsPresent)
    }
    # --- Code ---
}

# =======================================================================
# ======= [SMS OS level works] [os.ps1] [2018-04-20 15:42:26 UTC] =======
# =======================================================================
function SetSMSDriveConformity {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $script = @'
....
'@

    $str = '';
    $sms | Get-SMSDriveConformity -DoNotLog:(!$logging) | Out-Null
    $sms | Get-SMSVolume | % {
        if(![string]::IsNullOrEmpty($_.DriveLetter) -and ![string]::IsNullOrEmpty($_.OSDriveLetter) -and $_.OSDriveLetter -ne 'N/A') {
            $str += "RenameDrive -src '$($_.OSDriveLetter)' -dst '$($_.DriveLetter)'`r`n"
        }
    }
    $sms | Invoke-SMSInstanceScript -scriptStr ((DecompressString $script).Replace('{renameDrives}', $str)) -DoNotLog:(!$logging) | Out-Null
    $sms | Get-SMSDriveConformity -DoNotLog:(!$logging) | Out-Null
    $sms | Get-SMSVolume | % {$_ | Add-SMSTag -Tag @{Letter=$_.OSDriveLetter}} | Out-Null
}

function Set-SMSDriveConformity {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $NewServerRecord}
    }
    end {
        SetSMSDriveConformity $toProcess (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

function SetSMSDiskClusterSize {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $script = @'
....
'@
    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script) -DoNotLog:(!$logging) | Out-Null
}

function Set-SMSDiskClusterSize {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $NewServerRecord}
    }
    end {
        SetSMSDiskClusterSize $toProcess (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

function SetSMSDnsSettings {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $script = @'
....
'@
    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script).Replace('{fqdn}', $_.Name) -DoNotLog:(!$logging) | Out-Null
}

function Set-SMSDnsSettings {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        SetSMSDnsSettings $toProcess (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

function SetSMSPagefileSettings {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [bool]$Logging=$true
    )

    $script = @'
...
'@
    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script) -DoNotLog:(!$logging) | Out-Null
}

function Set-SMSPagefileSettings {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        SetSMSPagefileSettings $toProcess (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

function RenameSMSComputer {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Fqdn,
        [parameter(Mandatory=$true, position=2)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Ou,
        [parameter(Mandatory=$true, position=3)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$Credential,
        [parameter(Mandatory=$false, position=4)]
        [bool]$Logging=$true
    )

    $login = $Credential.UserName
    $pass = UnsecureString ($Credential.Password)

    $script = @'
....
'@

    for($i=0; $i -lt $sms.Count; $i++) {
        $sms[$i] | Invoke-SMSInstanceScript -scriptStr (DecompressString $script).Replace('{fqdn}', $fqdn[$i]).Replace('{ou}', (MakeOu $fqdn[$i] $ou[$i])).Replace('{login}', $login).Replace('{pass}', $pass) -DoNotLog:(!$logging) | Out-Null
    }
}

function Rename-SMSComputer {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Fqdn,
        [parameter(Mandatory=$true, position=2)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Ou,
        [parameter(Mandatory=$true, position=3)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$Credential,
        [parameter(Mandatory=$false, position=4)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        RenameSMSComputer $toProcess $Fqdn $Ou $Credential
        $toProcess
    }
    # --- Code ---
}

function CopySMSFile{
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)][ValidateSet('FromLocal','ToLocal','FromRemote','ToRemote')]
        [string]$Direction,
        [parameter(Mandatory=$true, position=2)][ValidateNotNull()]
        [string[]]$LocalPath,
        [parameter(Mandatory=$true, position=3)][ValidateNotNull()]
        [string[]]$RemotePath,
        [parameter(Mandatory=$false, position=4)]
        [bool]$Overwrite = $true,
        [parameter(Mandatory=$false, position=5)]
        [bool]$Compress = $true,
        [parameter(Mandatory=$false, position=6)]
        [bool]$Logging=$true
    )

    if($logging) {$logType = 'info'} else {$logType = 'rl'}

    $script1 = @'
....
'@
    $script2 = @'
....
'@

    try {
        if($LocalPath.Count -eq $RemotePath.Count) {
            $str = '';
            $p = ParseS3Path (Get-SMSVar 'smsFolderPath')
            $s3Path = (makeUrlPath $p.Bucket "$(Get-SMSVar 'smsFolderName')/$(Get-SMSVar 'tempFolderName')/$([guid]::NewGuid())")
            $toRemove = @()
            switch($Direction) {
                {$_ -eq 'ToRemote' -or $_ -eq 'FromLocal'}
                {
                    for($i=0; $i -lt $LocalPath.Count; $i++) {
                        if((Test-Path $LocalPath[$i]) -and !((dir $LocalPath[$i]).PsIsContainer)) {
                            log "Copying file [$($LocalPath[$i])] from Local computer. Compression: [$Compress]" $logType
                            Save-SMSStorageItem -Location $s3Path -localName $LocalPath[$i] -DoNotCompress:(!$Compress)
                            log "Copying file [$($LocalPath[$i])] from Local computer. Done" $logType
                            $s3From = makeUrlPath $s3path (Split-Path $LocalPath[$i] -Leaf)
                            $toRemove += $s3From
                            $str += '$files += New-Object PSObject -Property ' + "@{From='$s3From'; To='$($RemotePath[$i])'; Decompress=$" + $Compress.ToString() + "; Overwrite=$" + $Overwrite.ToString() + ";}; "
                        }
                    }
                    log "Copying to the Instance [$($sms.InstanceId)]..." $logType
                    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script1).Replace('{files}', $str) -DoNotLog:(!$logging) | Out-Null
                    $toRemove | % {Remove-SMSStorageItem -Location $_}
                    log "Copying to the Instance [$($sms.InstanceId)] complete" $logType
                    break;
                }
                {$_ -eq 'FromRemote' -or $_ -eq 'ToLocal'}
                {
                    for($i=0; $i -lt $LocalPath.Count; $i++) {
                        $str += '$files += New-Object PSObject -Property ' + "@{From='$($RemotePath[$i])'; To='$($LocalPath[$i])'; Compress=$" + $Compress.ToString() + ";}; "
                    }
                    log "Copying from the Instance [$($sms.InstanceId)]..." $logType
                    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script2).Replace('{files}', $str) -DoNotLog:(!$logging) | Out-Null
                    log "Copying from the Instance [$($sms.InstanceId)] complete" $logType
                    $sms | % {
                        $_.LastScriptRun.Result | % {
                            if($_.Code -eq 0) {
                                $folder = Join-Path -Path (Split-Path $_.To) -Child $_.Comp
                                if(!(Test-Path $folder)) {md $folder | Out-Null}
                                $lPath = Join-Path -Path $folder -Child (Split-Path $_.To -Leaf)
                                log "Downloading file to the local computer [$($_.File)]" 'rl'
                                $file = Get-SMSStorageItem -Location $_.File -NoDecompress:(!$Compress) -LeaveOnDisk
                                if(!([string]::IsNullOrEmpty($file))) {
                                    if(Test-Path $lPath) {
                                        if($Overwrite) {
                                            del $lPath -Force -Confirm:$false
                                            Move-Item $file $lPath -Force -Confirm:$false
                                        }
                                    }
                                    else {Move-Item $file $lPath -Force -Confirm:$false}
                                    del (Split-Path $file) -Recurse -Force -Confirm:$false
                                }
                                log "Removing file from the Cloud [$($_.File)]" 'rl'
                                Remove-SMSStorageItem -Location $_.File
                            }
                        }
                    }
                    break;
                }
            }
        }
        else {throw 'LocalFile and RemoteFiles counts must be equival'}
    }
    finally {
        Save-SMSRemoteLog;
    }
}

function Copy-SMSFile{
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)][ValidateSet('FromLocal','ToLocal','FromRemote','ToRemote')]
        [string]$Direction,
        [parameter(Mandatory=$true, position=2)][ValidateNotNull()]
        [string[]]$LocalPath,
        [parameter(Mandatory=$true, position=3)][ValidateNotNull()]
        [string[]]$RemotePath,
        [parameter(Mandatory=$false, position=4)]
        [switch]$DoNotOverwrite,
        [parameter(Mandatory=$false, position=5)]
        [switch]$DoNotCompress,
        [parameter(Mandatory=$false, position=6)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $NewServerRecord}
    }
    end {
        CopySMSFile -sms $toProcess -Direction $Direction -LocalPath $LocalPath -RemotePath $RemotePath -Overwrite (!($DoNotOverwrite.IsPresent)) -Compress (!($DoNotCompress.IsPresent)) -Logging (!($DoNotLog.IsPresent))
        $toProcess
    }
    # --- Code ---
}

function GetSMSOperatingSystem {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)][ValidateSet('CommonInfo','ComputerName','Ip','All')]
        [string]$About = 'All',
        [parameter(Mandatory=$false, position=2)][bool]$Logging=$true
    )

    $curr = $sms | Select -First 1
    if($sms -ne $null) {
        switch($About) {
            'All' {
                $curr.GetOSAll($sms);
                break;
            }
            'CommonInfo' {
                $curr.GetOSInfo($sms);
                break;
            }
            'ComputerName' {
                $curr.GetOSComputerName($sms)
                break;
            }
            'Ip' {
                $curr.GetOSIp($sms)
                break;
            }
        }
    }
}

function Get-SMSOperatingSystem {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)][ValidateSet('CommonInfo','ComputerName','Ip','All')][string]$About = 'All',
        [parameter(Mandatory=$false, position=2)][switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        GetSMSOperatingSystem $toProcess $About (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

function GetSMSWorkplaceInfo {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)][bool]$logging=$true
    )
    $script = @'
....
'@
    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script)
    $sms | % {
        if($_.LastScriptRun.Result -ne $null) {
            $_.__internal.WorkplaceInfo = $_.LastScriptRun.Result
            if($logging) {log "SMS: [$($sms.InstanceId)] Got WorkplaceInfo"}
        }
    }
    if($sms -eq $null) {if($logging) {log "($(GetInvokedFunctionName)) There is no SMS object passed" 'error'}}
}

function Get-SMSWorkplaceInfo {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)][switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        GetSMSWorkplaceInfo -sms $toProcess -logging (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

function GetSMSDriveConformity {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)][bool]$logging=$true
    )
    $script = @'
....
'@
    $sms | Invoke-SMSInstanceScript -scriptStr (DecompressString $script)
    $sms | % {
        if($_.LastScriptRun.Result -ne $null -and $_.LastScriptRun.Result.Count -gt 0) {
            $res = $_.LastScriptRun.Result
            $_ | Get-SMSVolume | ?{$_.VolumeId -in $res.EbsVolumeId} | % {
                $volId = $_.VolumeId
                $tmp = $res | ? {$_.EbsVolumeId -eq $volId};
                $_.OSDriveLetter = $tmp.Letter
                if($logging) {log "($(GetInvokedFunctionName)) SMS: [$($sms.InstanceId)] AWS letter: [$($_.VolumeId)] OS letter: [$($_.OSDriveLetter)]"}
            }
        }
    }
    if($sms -eq $null) {if($logging) {log "($(GetInvokedFunctionName)) There is no SMS object passed" 'error'}}
}

function Get-SMSDriveConformity {
    [CmdletBinding(ConfirmImpact='Low')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(Mandatory=$false, position=1)][switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        GetSMSDriveConformity -sms $toProcess -logging (!$DoNotLog.IsPresent)
        $toProcess
    }
    # --- Code ---
}

# ============================================================================================
# ======= [Reassembly SMS Instance] [instanceReassembly.ps1] [2018-04-20 15:42:26 UTC] =======
# ============================================================================================
function InvokeSMSInstanceReassembly {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]
        [object[]]$old,
        [parameter(Mandatory=$false, position=1)]
        [string]$NewInstanceType,
        [parameter(Mandatory=$false, position=2)]
        [string]$Fqdn,
        [parameter(Mandatory=$false, position=3)]
        [switch]$DedicatedHost,
        [parameter(Mandatory=$false, position=4)]
        [switch]$Run,
        [parameter(Mandatory=$false, position=5)]
        [string]$Script,
        [parameter(Mandatory=$false, position=6)]
        [switch]$RunScriptAwsDefault,
        [parameter(Mandatory=$false, position=7)]
        [string]$KeyPairName = 'infra-customer-ncalif',
        [parameter(Mandatory=$false, position=8)]
        [string]$NewImageName = 'OS33_LicensedImage',
        [parameter(Mandatory=$false, position=9)]
        [bool]$logging=$true
    )

    try {
        if(
            $old.Provider -eq 'aws' -and
            [string]::IsNullOrEmpty($newInstanceType) -or
            (
                ![string]::IsNullOrEmpty($newInstanceType) -and
                $NewInstanceType -in (Get-SMSAvailableInstanceTypes)
            )
        ) {
            $Zone = $old.Placement.AvailabilityZone
            $ami = Get-OsImage -Region $old.Region -Name $NewImageName
            if($ami -ne $null) {
                if([string]::IsNullOrEmpty($newInstanceType)) {$newInstanceType = ($old.InstanceType | Select-Object * -first 1).Value}
                if($DedicatedHost.IsPresent) {
                    $placement = Get-SMSDedicatedHost $newInstanceType MaxRooms $Zone
                    if($placement -eq $null) {throw "There is no rooms in the appropriated Dedicated Hosts or there is no dedicated hosts of such type"}
                    if($logging) {log "Instance is going to be created on the Dedicated Host [$($placement.HostId)]" 'semi'}
                }
                foreach($o in $old) {
                    $new = $null; $oldDisconnectedVol = $null; $newInstance = $null; $newDisconnectedVol = $null;
                    try {
                        if($logging) {log "Working with [$($o.InstanceId)] Name [$($o.Name)]" 'semi'}
                        $sg = $o | Get-SMSSecurityGroup
                        $subnets = $o | Get-SMSSubnet
                        $privateIp = $o.PrivateIp
                        # --------- Tagging all disks fromthe  old Volume before detaching start ----------
                        if($logging) {log "Tagging Disks before they are will be detached from [$($o.InstanceId)]" 'semi'}
                        $nameValue = $o | Get-SMSTag -Name 'Name'
                        if([string]::IsNullOrEmpty($fqdn)) {$fqdn = $nameValue.Split('_')[0].Split(' ')[0]}
                        $trysCnt = 3; $sleep = 5;
                        for($i=0; $i -lt $trysCnt; $i++) {
                            $error.Clear();
                            try {
                                if($logging) {log "Try #$($i+1)" 'semi'}
                                $o | Get-SMSVolume -Verbose | % {$_.AddTag(@{Name=$fqdn})}
                            }
                            catch {if($i -eq $trysCnt - 1) {if($logging) {log "Exception Tagging a drive(s) those going to be dtached from the InstanceID: [$($o.InstanceId)]" 'error'}}; Start-Sleep $sleep; $sleep += 5;}
                            if($error.Count -eq 0) {break;}
                        }
                        if($error.Count -gt 0) {
                            if($logging) {log "Can't tag all/some of volumes those are going to be detached. You must tag them manually. Please tag them and press <Enter> upon completion." 'warning'}
                            Read-Host;
                        }
                        else {if($logging) {log "Finally Volumes have been successfully tagged on the instance: [$($o.InstanceId)]" 'ok'}}
                        $error.Clear();
                        # --------- Tagging all disks from the old Volume before detaching end ------------
                        if($logging) {log "Instance [$($o.InstanceId)] will be stopped if it is not and it's Volumes are going to be detached"}
                        $oldDisconnectedVol = $o | Stop-SMSInstance -ForceStop -Timeout 1800 -Verbose | Get-SMSVolume -Verbose | Disconnect-SMSVolume -Timeout 1800 -Verbose
                        $oldDisconnectedVol | ? {$_.VolumeType -eq 'standard'} | ForEach-Object {Write-Verbose "On the instance [$($o.InstanceId)] Volume [$($_.VolumeId)] has a type [standard]. It wont be converted."}
                        $oldDisconnectedVol | ? {$_.VolumeType -ne 'gp2' -and $_.VolumeType -ne 'standard'} | % {$_ | Set-SMSVolume -What 'type' -Value 'gp2' -Timeout 1800 -Verbose | Out-Null}
                        if($logging) {
                            log "Instance [$($o.InstanceId)] Stopped and it's Volumes were detached."
                            log "New instance of type [$NewInstanceType] with followed specification will be created: $(Get-SMSInstanceSpecification -InstanceType $NewInstanceType -AsString)"
                            log "Terminating old instance [$($o.InstanceId)] Name [$($o.Name)]"
                        }
                        # === !!! Here the Old Instans gets terminated !!! ===
                        $o.InstanceTerminationProtection = $false;
                        $o = $o | Remove-SMSInstance -Verbose -Timeout 1800
                        if($logging) {log "Instance [$($o.InstanceId)] Name [$($o.Name)] has been terminated"}
                        # ====================================================
                        $runStr = 'New-EC2Instance -DisableApiTermination $true -ImageId $ami.ImageId -MinCount 1 -MaxCount 1 -KeyName $keyPairName -SecurityGroupIds ($sg.GroupId) -InstanceType $NewInstanceType -SubnetId ($subnets.SubnetId) -Region "' + $old.Region + '"';
                        if(![string]::IsNullOrEmpty($privateIp)) {
                            $runStr += " -PrivateIpAddress '$privateIp'"
                        }
                        if($placement -ne $null) {
                            $runStr += " -Tenancy host -HostId '$($placement.HostId)'"
                        }
                        if($logging) {
                            log 'Creating a new instance...'
                            # Trying to create a new instance until it did not be created. This is because sometime interface's IP has left and stay used
                            log "You are about to enter into a dead cycle. You will be there until new inctance was not created. Good luck..."
                        }
                        do {
                            if($logging) {log "Trying..."}
                            <# ... #>                        
                        }
                        until (($error.Count -ne 0) -and ($exc -ne $false))

                        if($newInstance) {
                            $new = $newInstance
                            if($logging) {log "Generating Tags from deleted instance to the new one [$($new.InstanceId)]"}
                            if($fqdn -ne $null) {
                                $new | Add-SMSTag -Tag @{Name=$fqdn.ToLower(); env='prod-us'; tier='customer'; domain=(DomainFromFqdn $fqdn).ToLower(); department='core';} | Out-Null
                            }
                            if($logging) {log "Waiting the instance [$($new.InstanceId)] for it's 'running' state"}
                            $new | Wait-SMSInstance -State 'running' -Status 'any' -Timeout 1800 -Verbose | Out-Null
                            # ----- Removing drive(s) from the newly created instance start ----------
                            if($logging) {log "Removing drives from newly created instance [$($new.InstanceId)]. Thrice. According to a russian habit"}
                            $trysCnt = 3; $sleep = 5;
                            for($i=0; $i -lt $trysCnt; $i++) {
                                if($logging) {log "Try #$($i+1)"}
                                $error.Clear(); $exc = $false;
                                try {
                                    if($new -eq $null -or [string]::IsNullOrEmpty($new.Volumes)) {$new = Get-SMSInstance -InstanceId $newInstance.InstanceId -Provider 'aws' -doNotContinueWhenFound}
                                    if($new -ne $null) {$new | Stop-SMSInstance -ForceStop -Timeout 1800 -Verbose | Out-Null}
                                    if($new -eq $null -or [string]::IsNullOrEmpty($new.Volumes)) {$new = Get-SMSInstance -InstanceId $newInstance.InstanceId -Provider 'aws' -doNotContinueWhenFound}
                                    if($new -ne $null) {$newDisconnectedVol = $new | Get-SMSVolume}
                                    if($newDisconnectedVol -ne $null) {$newDisconnectedVol | Remove-SMSVolume -ForceDismount -Timeout 1800 -Verbose | Out-Null}
                                    else {if($i -eq 0) {log "There is no volumes found belong to the Instance $($new.InstanceId) but expected at least 1." 'warning'}}
                                }
                                catch {
                                    $exc = $true;
                                    if($i -eq $trysCnt - 1) {
                                        if($logging) {log "FYI: Exception Detaching a Drive from newly created instance for the instance [$($new.InstanceId)] $($_.ToString())" 'exception';}
                                    };
                                    Start-Sleep $sleep; $sleep += 5;
                                }
                                if(($error.Count -eq 0) -and !$exc) {break;}
                            }
                            if($error.Count -gt 0) {
                                if($logging) {log "READ THIS CAREFULLY: Can't dismount Root device from the newly created instance. You must disconnect and delete it manually. Necessary data: InstanceId: [$($new.InstanceId)] Device [/dev/sda1]. Please disconnect and delete it and press <Enter> upon finished." 'warning'}
                                Read-Host;
                            }
                            else {if($logging) {log "Finally volume(s) have been successfully detached from the instance: [$($new.InstanceId)]" 'ok'}}
                            $error.Clear();
                            # ----- Removing drive(s) from the newly created instance end ------------
                            # First Device Name: /dev/sda1 (Root)
                            if($logging) {log "Mounting a Root drive from the deleted instance [$($o.InstanceId)] RootDevice: [$($old.RootDeviceName)]"}
                            $oldDisconnectedVol | Where-Object {$_.Attachments.Device -eq "$($old.RootDeviceName)"} | ForEach-Object {$_ | Connect-SMSVolume -sms $new -device '/dev/sda1' -Verbose | Out-Null}
                            if($logging) {log "Mounting all other drives from the deleted instance [$($o.InstanceId)]"}
                            $oldDisconnectedVol | Where-Object {$_.Attachments.Device -ne "$($old.RootDeviceName)"} | ForEach-Object {$_ | Connect-SMSVolume -sms $new -Verbose | Out-Null}
                            if($logging) {log "Check/Set TerminationProtection for the instance [$($new.InstanceId)]"}
                            if(!$new.InstanceTerminationProtection) {$new.InstanceTerminationProtection = $true;}
                            #$new = $new | Invoke-SMSRefresh
                            if($logging) {log "Set DeleteOnTermination for each Volumes for the instance [$($new.InstanceId)]. According to a russian traditions we are going to do it thrice"}
                            $trysCnt = 3; $sleep = 5;
                            for($i=0; $i -lt $trysCnt; $i++) {
                                $error.Clear();
                                try {
                                    if($logging) {log "Try #$($i+1)"}
                                    $new.DrivesDeleteOnTermination = $true;
                                }
                                catch {
                                    if($i -eq $trysCnt - 1) {
                                        if($logging) {log "Exception Set DeleteOnTermination for the instance [$($new.InstanceId)]" 'exception';}
                                        Start-Sleep $sleep; $sleep += 5;
                                    }
                                }
                                if($error.Count -eq 0) {break;}
                            }
                            if($error.Count -gt 0) {if($logging) {log "Can't set DeleteOnTermination for drives of the the newly created instance [$($new.InstanceId)]. You must do it manually." 'error'}}
                            else {if($logging) {log "Finally DeleteOnTermination has been set for the instanceId: [$($new.InstanceId)]" 'ok'}}
                            $error.Clear();
                            if($Run.IsPresent) {
                                if($logging) {log "Starting the instance [$($new.InstanceId)]"}
                                $new | Start-SMSInstance -Verbose -Timeout 1800 | Out-Null
                                if(![string]::IsNullOrEmpty($Script)) {
                                    if($RunScriptAwsDefault) {
                                        $ret = Invoke-SMSInstanceScript -Verbose -AwsDefault -Sms $new -ScriptStr $Script -Comment "Instance [$($new.InstanceId)] run script at [$(Get-Date)]"
                                    }
                                    else {
                                        $ret = Invoke-SMSInstanceScript -Verbose -Sms $new -ScriptStr "Out-Result ($Script) -Final" -Comment "Instance [$($new.InstanceId)] run script at [$(Get-Date)]"
                                    }
                                    log $ret
                                }
                            }
                            if($logging) {log "So, that's it folks" 'ok'}
                            return (Get-SMSInstance -InstanceId $new.InstanceId -Provider 'aws' -doNotContinueWhenFound)
                        }
                        else {if($logging) {log 'New instance did not created' 'error'}}
                    }
                    catch {
                        if($logging) {log "Exception: [$($_.ToString())]" 'exception'}
                    }
                } # foreach($o in $old) {
            }
            else {if($logging) {log "There is no AMI image with the next name [$NewImageName] among custom (non-Amazon) images" 'error'}}
        }
        else {if($logging) {log "No such instance type [$NewInstanceType] exists or Instance Provider [$($old.Provider)] is not supports this action" 'error'}}
    }
    finally {
        Save-SMSRemoteLog;
        if(![string]::IsNullOrEmpty($tempDir)) {Remove-Item $tempDir -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue}
    }
}

function Invoke-SMSInstanceReassembly {
    [CmdletBinding(DefaultParameterSetName='InstanceId')]
    param(
        [parameter(ParameterSetName='InstanceId', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Instance ID(s) from which Disk Volumes will be stoled')]
        [ValidateNotNullOrEmpty()]
        [string[]]$InstanceId,
        [parameter(ParameterSetName='Instance', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Instance(s) from which Disk Volumes will be stoled')]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.Instance[]]$Instance,
        [parameter(ParameterSetName='Reservation', Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Amazon.EC2.Model.Reservation[]]$Reservation,
        [parameter(Mandatory=$false)]
        [string]$NewInstanceType,
        [parameter(Mandatory=$false)]
        [string]$Fqdn,
        [parameter(Mandatory=$false)]
        [switch]$DedicatedHost,
        [parameter(Mandatory=$false)]
        [switch]$Run,
        [parameter(Mandatory=$false)]
        [string]$Script,
        [parameter(Mandatory=$false)]
        [switch]$RunScriptAwsDefault,
        [parameter(Mandatory=$false)]
        [string]$KeyPairName = 'infra-customer-ncalif',
        [parameter(Mandatory=$false)]
        [string]$NewImageName = 'OS33_LicensedImage',
        [parameter(Mandatory=$false)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin{$res = @();}
    process{
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
             # --- one by one ---
            if($PSCmdlet.ParameterSetName -eq 'Instance') {$iId += $_.InstanceId}
            elseif($PSCmdlet.ParameterSetName -eq 'InstanceId') {$iId += $_}
            else {$iId += $_.Instances.InstanceId}
        }
        else {
            # --- array ---
            if($PSCmdlet.ParameterSetName -eq 'Instance') {$iId = $Instance.InstanceId}
            elseif($PSCmdlet.ParameterSetName -eq 'InstanceId') {$iId = $InstanceId}
            else {$iId = $Reservation.Instances.InstanceId}
        }
        $sb = 'InvokeSMSInstanceReassembly -Logging $' + !($DoNotLog.IsPresent) + ' -Old (Get-SMSInstance -InstanceId $iId)'
        if(![string]::IsNullOrEmpty($NewInstanceType)) {$sb += ' -NewInstanceType $NewInstanceType'}
        if(![string]::IsNullOrEmpty($Fqdn)) {$sb += ' -Fqdn $Fqdn'}
        $sb += ' -Run:$' + $($Run.IsPresent)
        $sb += ' -DedicatedHost:$' + $($DedicatedHost.IsPresent)
        if($Run.IsPresent) {
            if(![string]::IsNullOrEmpty($Script)) {$sb += ' -Script $Script'}
            $sb += ' -RunScriptAwsDefault:$' +$($RunScriptAwsDefault.IsPresent)
        }
        if(![string]::IsNullOrEmpty($KeyPairName)) {$sb += ' -KeyPairName $KeyPairName'}
        if(![string]::IsNullOrEmpty($NewImageName)) {$sb += ' -NewImageName $NewImageName'}
        if(!$DoNotLog.IsPresent) {log "($(GetInvokedFunctionName)) Running..."}
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            $res += .([scriptblock]::Create($sb))
        }
        else {
            $res = .([scriptblock]::Create($sb))
        }
    }
    end{
        if($res -ne $null) {
            if($res.Count -eq 1) {$res[0]}
            else {$res}
        }
        else {$null}
    }
    # --- Code ---
}

# ======================================================================================================================================================
# ======= [Code invocation (Invoke-SMSInstanceScript, Invoke-ThisCode, Invoke-ThisCodeByAutoregions)] [invokeCode.ps1] [2018-04-20 15:42:26 UTC] =======
# ======================================================================================================================================================
function Invoke-ThisCode {
    [CmdletBinding(DefaultParameterSetName='Str')]
    param(
        [parameter(ParameterSetName='Str', Mandatory=$true)][ValidateNotNullOrEmpty()][string]$scriptStr,
        [parameter(ParameterSetName='Arr', Mandatory=$true)][ValidateNotNullOrEmpty()][string[]]$scriptArr,
        [parameter(ParameterSetName='Code', Mandatory=$true)][ValidateNotNullOrEmpty()][scriptblock]$scriptBlk,
        [parameter(Mandatory=$false)][uint32]$trysCnt,
        [parameter(Mandatory=$false)][uint32]$secAprox = 180,
        [parameter(Mandatory=$false)][uint32]$pause = 5,
        [parameter(Mandatory=$false)][string[]]$stopIfErrorStartsWith=@(),
        [parameter(Mandatory=$false)][string[]]$stopIfErrorEndsWith=@(),
        [parameter(Mandatory=$false)][Hashtable[]]$stopIfErrorStartsOrEndsWith=@(), # @{starts=''; ends='';}
        [parameter(Mandatory=$false)][Hashtable[]]$stopIfErrorStartsAndEndsWith=@(), # @{starts=''; ends='';}
        [parameter(Mandatory=$false)][ValidateSet('aws', 'vmw')][string]$provider='aws'
    )
    # --- Code ---
    $enough = $false;
    if($secAprox -eq $null -and $trysCnt -eq $null) {$enough = $true}
    $cur = Get-Date; $delta = [math]::Abs(((Get-Date) - $cur).TotalSeconds); $try = 0;
    $allOk = $false; $pauseIncreaseBy = 5; $lastAwsException = $null

    if($PSCmdlet.ParameterSetName -eq 'Str') {
        $script = ScriptToStringArray -scriptStr $scriptStr
    }
    elseif($PSCmdlet.ParameterSetName -eq 'Arr') {
        $script = ScriptToStringArray -scriptArr $scriptArr;
    }
    # elseif($PSCmdlet.ParameterSetName -eq 'Code') {
    #     $script = ScriptToStringArray -scriptBlk $scriptBlk
    # }

    if($provider -eq 'aws') {
        # --- Preparing $stopIfErrorStartsWith, ...EndsWith, ... variables ---
        # StartsWith
        $stopIfErrorStartsWith = (@('Invalid id') + $stopIfErrorStartsWith)
        $stopIfErrorStartsWith = (@('Access Denied') + $stopIfErrorStartsWith)
        $stopIfErrorStartsWith = (@('The AWS Access Key Id you provided does not exist') + $stopIfErrorStartsWith) | select -Unique | ?{![string]::IsNullOrEmpty($_)}
        # EndsWith
        $stopIfErrorEndsWith = (@('does not exist') + $stopIfErrorEndsWith)
        $stopIfErrorEndsWith = (@('does not exist.') + $stopIfErrorEndsWith) | select -Unique | ?{![string]::IsNullOrEmpty($_)}
        #StartOrEndWith
        #StartsAndEndsWith
        $stopIfErrorStartsAndEndsWith = (@(@{starts='The instance ID'; ends='does not exist'}) + $stopIfErrorStartsAndEndsWith)
        $stopIfErrorStartsAndEndsWith = (@(@{starts='The volume'; ends='does not exist.'}) + $stopIfErrorStartsAndEndsWith) | ?{$_ -ne $null}
        # --------------------------------------------------------------------
    }
    elseif($provider -eq 'vmw') {
        # --- VMWare.PowerCLI doen't return exception, but $Error. In this case we will emulate Exception ---
        # StartsWith
        # EndsWith
        $stopIfErrorEndsWith = (@('was not found using the specified filter(s)') + $stopIfErrorEndsWith) | select -Unique | ?{![string]::IsNullOrEmpty($_)}
        #StartOrEndWith
        #StartsAndEndsWith
        # ---------------------------------------------------------------------------------------------------
    }
    while(!$enough -and !$allOk) {
        if($secAprox -gt 0) {
            $delta = [math]::Abs(((Get-Date) - $cur).TotalSeconds)
            if($delta -gt $secAprox) {$enough = $true}
        }
        elseif($trysCnt -gt 0) {
            $try ++;
            if($try -gt $trysCnt) {$enough = $true}
        }
        if(!$enough) {
            $stopWatch = Start-SMSStopwatch
            try {
                $Error.Clear();
                log "[$stopWatch] Trying to invoke [$($provider.ToUpper())] Code..." 'rl'
                if($PSCmdlet.ParameterSetName -eq 'Code') {
                    log "[$stopWatch] Invoke-ThisCode: scriptblock: [$($scriptBlk.ToString())]" 'rl'
                    . $scriptBlk
                }
                else {
                    log "[$stopWatch] Invoke-ThisCode: script: [$script]" 'rl'
                    . ([scriptblock]::Create($script))
                }
                $allOk = $true;
                log "[$stopWatch] Code invocation successfully" 'rl'

                # --- Exception emulation in case VMWare used and Error has occured ---
                if($Error.Count -gt 0 -and $provider -eq 'vmw') {
                    if($Error[0].CategoryInfo.Reason.ToString() -eq 'VimException') {
                        $vmwExc = $Error[0].CategoryInfo.Reason.ToString()
                        throw $Error[0].Exception
                    }
                }
                # --------------------------------------------------------------------
            }
            catch {
                $excName = $_.FullyQualifiedErrorId.Split(',')[0].Trim();
                if(
                    (
                        $excName -eq 'Amazon.EC2.AmazonEC2Exception' -or
                        $excName -eq 'Amazon.S3.AmazonS3Exception' -or
                        $vmwExc -eq 'VimException'
                    ) -and
                    ((!(ItStartsOrEndsWith $_.ToString() `
                            -startsWithArray $stopIfErrorStartsWith `
                            -endsWithArray $stopIfErrorEndsWith `
                            -startsOrEndsWithArray $stopIfErrorStartsOrEndsWith `
                            -startsAndEndsWithArray $stopIfErrorStartsAndEndsWith
                        )
                    ))
                )
                {
                    $allOk = $false;
                    Sleep $pause;
                    $pause += $pauseIncreaseBy;
                    $lastAwsException = $_
                    log "[$stopWatch] There was an [$($provider.ToUpper())] Exception [$excName] [$($_.ToString())]. Will wait [$pause] sec. until next try" 'semi'
                }
                else {
                    $enough = $true;
                    $allOk = $false;
                    if(!(ItStartsOrEndsWith $_.ToString() `
                            -startsWithArray $stopIfErrorStartsWith `
                            -endsWithArray $stopIfErrorEndsWith `
                            -startsOrEndsWithArray $stopIfErrorStartsOrEndsWith `
                            -startsAndEndsWithArray $stopIfErrorStartsAndEndsWith
                        )
                    ) {log "[$stopWatch] Code invocation error [$($_.ToString())]" 'rl';}
                    else {log "[$stopWatch] Code invocation info [$($_.ToString())]" 'rl';}
                    throw;
                }
            }
            finally {
                log "[$stopWatch] Code execution time: [$((Get-SMSStopwatch -Id $stopWatch -Stop).TotalSeconds.ToString('# ### ##0.00'))] sec." 'rl'
            }
        }
        else {$allOk = $false; throw "Trys count or Timeout is exceeded. Tries:[$try/$trysCnt]. Timeout: [$($delta.ToString('# ### ##0.0'))/$secAprox] sec. Exception: [$($lastAwsException.ToString())]"}
    }
    if($lastAwsException -ne $null -and !$allOk) {throw $lastAwsException}
    # --- Code ---
}

function InvokeSMSInstanceScript {
    param(
        [parameter(Mandatory=$true, position=0)]
        [ValidateNotNullOrEmpty()]
        [object[]]$sms,
        [parameter(Mandatory=$true, position=1)][ValidateNotNull()]
        [string[]]$script,
        [parameter(Mandatory=$false, position=2)]
        [switch]$awsDefault,
        [parameter(Mandatory=$false, position=3)]
        [string]$comment = "SMS [$((Get-Date).ToString('yyyy-MM-dd hh:mm:ss'))]",
        [parameter(Mandatory=$false, position=4)]
        [uint64]$timeout = [uint64]::MaxValue,
        [parameter(Mandatory=$false, position=5)]
        [switch]$noOutputExpected,
        [parameter(Mandatory=$false, position=6)]
        [switch]$outResult,
        [parameter(Mandatory=$false, position=7)]
        [switch]$doNotStoreResult,
        [parameter(Mandatory=$false, position=8)]
        [bool]$logging=$true
    )

    if($logging) {log "Running script on the Instances: [$(StringsToString $sms.InstanceId)]"}
    ($sms | select -first 1).RunScript($sms, $script, $awsDefault.IsPresent, $comment, $timeout, $noOutputExpected.IsPresent, $outResult.IsPresent, $doNotStoreResult.IsPresent);
}

function Invoke-SMSInstanceScript {
    [CmdletBinding(ConfirmImpact='Low', DefaultParameterSetName='String')]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()][ValidateScript({$_.__internal -and $_.__internal.author -eq 'alex'})]
        [Alias('object')]
        [object[]]$sms,
        [parameter(ParameterSetName='String', Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$scriptStr,
        [parameter(ParameterSetName='Strings', Mandatory=$true, position=1)]
        [ValidateNotNull()]
        [string[]]$scriptArr,
        [parameter(ParameterSetName='Scriptblock', Mandatory=$true, position=1)]
        [ValidateNotNullOrEmpty()]
        [scriptblock]$scriptBlk,
        [parameter(Mandatory=$false, position=2)]
        [switch]$AwsDefault,
        [parameter(Mandatory=$false, position=3)]
        [string]$Comment,
        [parameter(Mandatory=$false, position=4)]
        [uint64]$Timeout = [uint64]::MaxValue,
        [parameter(Mandatory=$false, position=5)]
        [switch]$NoOutputExpected,
        [parameter(Mandatory=$false, position=6)]
        [switch]$OutResult,
        [parameter(Mandatory=$false, position=7)]
        [switch]$DoNotStoreResult,
        [parameter(Mandatory=$false, position=8)]
        [switch]$ReturnResult,
        [parameter(Mandatory=$false, position=9)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {
        $toProcess = @()
        $script = @();
        if($PSCmdlet.ParameterSetName -eq 'String') {
            $script = $scriptStr.Split("`r`n").Trim("`r").Trim("`n").Trim();
        }
        elseif($PSCmdlet.ParameterSetName -eq 'Strings') {
            $script = $scriptArr;
        }
        elseif($PSCmdlet.ParameterSetName -eq 'Scriptblock') {
            $script = $scriptBlk.ToString().Split("`r`n").Trim("`r").Trim("`n").Trim();
        }
        else {throw "Unknown ParameterSet [$($PSCmdlet.ParameterSetName)]"}
        $script = $script | ? {![string]::IsNullOrEmpty($_)}
    }
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $sms}
    }
    end {
        $tmp = $toProcess | ? {$_.IsRunning}
        if($tmp -ne $null) {InvokeSMSInstanceScript -Sms $tmp -Script $script -awsDefault:($AwsDefault.IsPresent) -Comment $Comment -Timeout $Timeout -NoOutputExpected:($NoOutputExpected.IsPresent) -OutResult:($OutResult.IsPresent) -DoNotStoreResult:($DoNotStoreResult.IsPresent) -logging (!$DoNotLog.IsPresent)}
        return $toProcess
    }
    # --- Code ---
}

# ================================================================================================
# ======= [Cloud Storage (Save, Delete, ...)] [cloudStorage.ps1] [2018-04-20 15:42:26 UTC] =======
# ================================================================================================
function Get-SMSStorageItem {
    [CmdletBinding(ConfirmImpact="Low")]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()][string[]]$Location,
        [parameter(Mandatory=$false, position=1)][string]$LocalFileName,
        [parameter(Mandatory=$false, position=2)][switch]$LeaveOnDisk,
        [parameter(Mandatory=$false, position=4)][switch]$NoDecompress,
        [parameter(Mandatory=$false, position=5)][switch]$AsString,
        [parameter(Mandatory=$false, position=6)][switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $Location}
    }
    end {
        Get-S3 -s3Path $toProcess -LocalFileName $LocalFileName -LeaveOnDisk:($LeaveOnDisk.IsPresent) -Decompress:(!($NoDecompress.IsPresent)) -AsString:($AsString.IsPresent)
    }
    # --- Code ---
}

function Remove-SMSStorageItem {
    [CmdletBinding(ConfirmImpact="Low")]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()][string[]]$Location,
        [parameter(Mandatory=$false, position=1)][switch]$IsFolder=$false,
        [parameter(Mandatory=$false, position=2)][switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $Location}
    }
    end {Remove-S3 -s3Path $toProcess -IsFolder:($IsFolder.IsPresent)}
    # --- Code ---
}

function Save-SMSStorageItem {
    [CmdletBinding(DefaultParameterSetName='file', ConfirmImpact="Low")]
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$Location,
        [parameter(Mandatory=$false, position=1)][switch]$DoNotCompress,
        [parameter(Mandatory=$false, position=2)][switch]$DoNotDeleteOld,
        [parameter(Mandatory=$false, position=3)][switch]$DoNotPublicReadonly,
        [parameter(Mandatory=$false, position=4)][switch]$DoNotLog,
        [parameter(ParameterSetName="file", Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [string[]]$localName,
        [parameter(ParameterSetName="file", Mandatory=$false)][switch]$IsFolder,
        [parameter(ParameterSetName="file", Mandatory=$false)][switch]$DoNotSameAsLocalName,
        [parameter(ParameterSetName="byte", Mandatory=$true)][ValidateNotNull()][byte[]]$Arr,
        [parameter(ParameterSetName="str", Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Str,
        [parameter(ParameterSetName="strs", Mandatory=$true)][ValidateNotNull()][string[]]$Strings
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $localName}
    }
    end {
        switch ($PSCmdlet.ParameterSetName) {
            'file' {
                Save-S3 -LocalName $toProcess -s3Path $Location -Compress:(!($DoNotCompress.IsPresent)) -DeleteOld:(!($DoNotDeleteOld.IsPresent)) -PublicReadonly:(!($DoNotPublicReadonly)) -IsSameAsLocalName:(!($DoNotSameAsLocalName.IsPresent)) -IsFolder:($IsFolder.IsPresent)
                break;
            }
            'byte' {
                Save-S3 -Arr $Arr -s3Path $Location -Compress:(!($DoNotCompress.IsPresent)) -DeleteOld:(!($DoNotDeleteOld.IsPresent)) -PublicReadonly:(!($DoNotPublicReadonly))
                break;
            }
            'str' {
                Save-S3 -Str $str -s3Path $Location -Compress:(!($DoNotCompress.IsPresent)) -DeleteOld:(!($DoNotDeleteOld.IsPresent)) -PublicReadonly:(!($DoNotPublicReadonly))
                break;
            }
            'strs' {
                Save-S3 -Strings $Strings -s3Path $Location -Compress:(!($DoNotCompress.IsPresent)) -DeleteOld:(!($DoNotDeleteOld.IsPresent)) -PublicReadonly:(!($DoNotPublicReadonly))
                break;
            }
        }
    }
    # --- Code ---
}

function Read-SMSStorageItem {
    [CmdletBinding(ConfirmImpact="Low")]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()][string[]]$Location,
        [parameter(Mandatory=$false, position=1)][switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $Location}
    }
    end {Read-S3 -s3Path $toProcess}
    # --- Code ---
}

function Wait-SMSStorageItem {
    [CmdletBinding(ConfirmImpact="Low")]
    param(
        [parameter(Mandatory=$true, position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNull()][string[]]
        $Location,
        [parameter(Mandatory=$false, position=1)]
        [ValidateSet('all','any')]
        [string]$waitFor='any',
        [parameter(Mandatory=$false, position=2)]
        [int]$Timeout = 30,
        [parameter(Mandatory=$false, position=3)]
        [int]$WaitFilesCount=0,
        [parameter(Mandatory=$false, position=4)]
        [switch]$DoNotLog
    )
    # --- Code ---
    begin {$toProcess = @()}
    process {
        if ($PSCmdlet.MyInvocation.ExpectingInput) {$toProcess += $_}
        else {$toProcess = $Location}
    }
    end {Wait-S3 -s3Path $toProcess -WaitFor $WaitFor -Timeout $Timeout -WaitFilesCount $WaitFilesCount}
    # --- Code ---
}

# =====================================================================
# ======= [VMWare works] [vmware.ps1] [2018-04-20 15:42:26 UTC] =======
# =====================================================================
function GetVmwConnectionInfoSettings {
    param(
        $vmwRegion
    )

    switch($vmwRegion) {
        'vm-nj4-1' {
            @{Name='nj4vvc001.mgmt.local'; Ip='10.34.5.200'; Connected=$false;}
            break;
        }
        'vm-nj5-1' {
            @{Name='nj5vvc001.mgmt.local'; Ip='10.35.11.200'; Connected=$false;}
            break;
        }
        'vm-da-1' {
            @{Name='da1vvc001.mgmt.local'; Ip='172.17.51.200'; Connected=$false;}
            break;
        }
        'vm-kc-1' {
            @{Name='kc1vvc001.mgmt.local'; Ip='172.18.10.200'; Connected=$false;}
            break;
        }
        'vm-lab-1' {
            @{
                Name='lab2vvc001.lab.local'; Ip='172.17.85.200'; Connected=$false;
                Host=@{
                    Auto=$true;
                    Name=@(
                        'lab1esx000b.lab.local'
                        'lab1esx000c.lab.local'
                        'lab1esx000a.lab.local'
                    );
                };
                Folder=@{
                    Auto=$true;
                    Name=@(
                        '2012'
                    )
                }
                Resource=@{
                    Auto=$true;
                    Name=@(
                        'Resources'
                    )
                }
            };
            break;
        }
    }
}

function ConnectVMWareServer {
    param
    (
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][hashtable[]]$servers, # @{Name, Ip}
        [parameter(Mandatory=$true, position=1)][ValidateNotNullOrEmpty()][string]$login,
        [parameter(Mandatory=$true, position=2)][ValidateNotNullOrEmpty()][SecureString]$pass
    )

    $connection = $null;
    foreach ($s in $servers) {
        $connection = Connect-VIServer -Server $s.Ip -Credential (New-Object PSCredential($login, $pass))
        if($connection -ne $null) {$s.Connected = $true; return $true;}
    }
    $false;
 }

function DisconnectVMWareServer {
    $tmp = @();
    (Get-SMSVar 'VmwConnectionInfo').Keys | % {
        $res = @();
        (Get-SMSVar 'VmwConnectionInfo').$_ | ? {$_.'Connected' -eq $true} | % {
            Disconnect-VIServer -Server $_.'Ip' -Force -Confirm:$false -ErrorAction SilentlyContinue
            $res += @{Name=$_.Name; Ip=$_.Ip; Connected=$false;}
        }
        (Get-SMSVar 'VmwConnectionInfo').$_ | ? {$_.'Connected' -eq $false} | % {
            $res += @{Name=$_.Name; Ip=$_.Ip; Connected=$_.Connected;}
        }
        $tmp += @{$_ = $res}
    }
    Set-SMSVar 'VmwConnectionInfo' $tmp
}

function Get-SMSVMWareConnectionInfo {
    # --- There is no parameters ---
    # --- Code ---
    (Get-SMSVar 'VmwConnectionInfo')."$(Get-SMSVar 'Region')"
    # --- Code ---
}

function Get-SMSVMWareConnectedRegion {
    # --- There is no parameters ---
    # --- Code ---
    $res = @();
    (Get-SMSVar 'VmwConnectionInfo').Keys | % {
        $reg = $_
        (Get-SMSVar 'VmwConnectionInfo').$_ | ? {$_.'Connected' -eq $true} | % {$res  += $reg}
    }
    if($res -ne $null -and $res.Count -gt 0) {$res[0];} else {$null;}
    # --- Code ---
}

function Disconnect-SMSVMWare {
    param(
        [parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][switch]$Force
    )
    # --- Code ---
    if((Test-SMSVMWareUsable)) {
        if((Test-SMSVMWareConnected) -or $Force.IsPresent) {try {DisconnectVMWareServer} catch{}}
    }
    else {throw $vmwErrMsg}
    # --- Code ---
}

function Connect-SMSVMWare {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$region,
        [parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][switch]$ForceDisconnect,
        [parameter(Mandatory=$false)][ValidateNotNullOrEmpty()][switch]$ConnectToProperRegion
    )
    # --- Code ---
    if((Test-SMSVMWareUsable)) {
        if((Test-RegionIs $region 'vm')) {

            $connectedRegion = Test-SMSVMWareConnected -returnConnectedRegion
            if(($ForceDisconnect.IsPresent) -or ($ConnectToProperRegion.IsPresent -and $connectedRegion -ne $region)) {
                Disconnect-SMSVMWare
            }

            $connectedRegion = Test-SMSVMWareConnected -returnConnectedRegion
            if(([string]::IsNullOrEmpty($connectedRegion))) {
                $cred = Get-VMWCredential (Get-SMSVar 'Environment')
                if($cred -ne $null) {
                    ConnectVMWareServer (Get-SMSVar 'VmwConnectionInfo').$region $cred.Login $cred.Password
                }
                else {throw "There is no Credential for [$(Get-SMSVar 'Environment')] region is stored. You need to define the Credential first."}
            }
            elseif($connectedRegion -eq $region) {return $true;}
            else {throw "You are already connected to a VMWare Server. Region [$connectedRegion]. Use -Force switch for disconnect and connect again"}

        }
        else {throw "You can't connect to VMWare using [$region] region"}
    }
    else {throw $vmwErrMsg}
    # --- Code ---
}

function Test-SMSVMWareConnected {
    param(
        [switch]$returnConnectedRegion
    )
    # --- Code ---
    if((Test-SMSVMWareUsable)) {
        foreach($k in (Get-SMSVar 'VmwConnectionInfo').Keys) {
            if(((Get-SMSVar 'VmwConnectionInfo').$k.Connected) -and $DefaultVIServer -ne $null) {
                if(!($returnConnectedRegion.IsPresent)) {return $true}
                else {return $k}
            }
        }
        if(!($returnConnectedRegion.IsPresent)) {return $false}
        else {$null}
    }
    else {throw $vmwErrMsg}
    # --- Code ---
}

function Test-SMSVMWareUsable {
    # --- Params are empty ---
    # --- Code ---
    Get-SMSVar 'VmwPresent'
    # --- Code ---
}

# ==========================================================================
# ======= [SMS Variable work] [smsVar.ps1] [2018-04-20 15:42:26 UTC] =======
# ==========================================================================
function Test-SMSVar {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$name
    )
    # --- Code ---
    if((dir variable:"$($SMSPrefix)$name" -ErrorAction SilentlyContinue) -ne $null) {$true}
    else {$false}
    # --- Code ---
}

function Get-SMSVar {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()][string]$name
    )
    # --- Code ---
    Get-Variable -Name "$($SMSPrefix)$name" -ValueOnly -ErrorAction SilentlyContinue
    # --- Code ---
}

function Set-SMSVar {
    param(
        [parameter(Mandatory=$true, position=0)][ValidateNotNullOrEmpty()]
        [string]$name,
        [parameter(Mandatory=$false, position=1)]
        [object]$val,
        [parameter(Mandatory=$false, position=2)]
        [ValidateSet('ReadOnly', 'Constant')]
        [string]$option,
        [parameter(Mandatory=$false, position=3)]
        [ValidateSet('continue', 'silentlyContinue', 'error', 'silentError')]
        [string]$onError='silentlyContinue',
        [parameter(Mandatory=$false, position=4)]
        [switch]$doNotForce,
        [parameter(Mandatory=$false, position=5)]
        [switch]$returnResult
    )
    # --- Code ---
    try {
        $opt = @('AllScope')
        if(![string]::IsNullOrEmpty($option)) {$opt = $opt + $option}

        if(((dir variable:"$($SMSPrefix)$name" -ErrorAction SilentlyContinue) -eq $null)) {
            # New SMS Variable
            Set-Variable -Name "$($SMSPrefix)$name" -Value $val -Option $opt -Scope Global -Force:(!$doNotForce.IsPresent) -ErrorAction SilentlyContinue
        }
        else {
            # Existent SMS Variable
            $var = Get-Variable "$($SMSPrefix)$name" -ErrorAction SilentlyContinue;
            if($var -ne $null) {
                if(!($var.Options.ToString().ToLower().Contains('Constant'.ToLower()))) {
                    if(($var.Options.ToString().ToLower().Contains('ReadOnly'.ToLower()))) {
                        del variable:$name -Force -Confirm:$false -ErrorAction SilentlyContinue
                    }
                    Set-Variable -Name "$($SMSPrefix)$name" -Value $val -Option $opt -Scope Global -Force:(!$doNotForce.IsPresent) -ErrorAction SilentlyContinue
                    $res = $true;
                }
                else {throw "Error set variable [$name] because it is a Constant"}
            }
            else {throw "Variable [$name] exists but can't be accessible"}
        }
    }
    catch{
        switch ($onError) {
            'continue' {toLog "SetSmsVar: $($_.ToLog())" 'error'; break;}
            'silentlyContinue' {break;}
            'error' {toLog "SetSmsVar: $($_.ToLog())" 'error'; throw; break;}
            'silentError' {throw; break;}
        }
        $res = $false;
    }
    finally {
        if($returnResult.IsPresent) {$res;}
    }
    # --- Code ---
}

# ===============================================================================================
# ======= [SMS Module finalizalization] [_sms_module_final.ps1] [2018-04-20 15:42:26 UTC] =======
# ===============================================================================================
function Complete-SMSWork {
    # --- There is no any parameters ---
    # --- Code ---
    Save-SMSRemoteLog;
    if((Test-SMSVMWareUsable)) {if((Test-SMSVMWareConnected)) {Disconnect-SMSVMWare -Force}}
    # --- Code ---
}

# ============================================================================================
# ======= [SMS Module initialization] [_sms_module_init.ps1] [2018-04-20 15:42:26 UTC] =======
# ============================================================================================
toLog "SMS starting..." 'semi'
Set-SMSVar 'smsLoadedOk' $true
Export-ModuleMember *-*

# --- Initial vars ---
if((dir variable:NoScriptUpdate -ErrorAction SilentlyContinue) -eq $null) {
    Set-Variable -Name NoScriptUpdate -Value $true -Scope Global -Option AllScope
}
if(!(Test-SMSVar 'TestMode')) {Set-SMSVar 'TestMode' $false}
Set-SMSVar Stopwatch @()
Set-SMSVar 'AwsRegions' $((Get-AWSRegion).Region)
Set-SMSVar 'VmwRegions' @('vm-nj4-1', 'vm-nj5-1', 'vm-da-1', 'vm-kc-1', 'vm-lab-1')
Set-SMSVar 'AllRegions' ((Get-SMSVar 'AwsRegions') + (Get-SMSVar 'VmwRegions'))
Set-SMSAutoRegions @('us-west-2', 'us-east-1', 'us-east-2', 'us-west-1')

# --- Set VMWare presence start ---
$vmwModule = 'VMware.PowerCLI'
$vmwErrMsg = "There is no $vmwModule module present";
$vmwIdPrefix = 'VirtualMachine-vm-'
$tmp = $true;
if((Get-Module $vmwModule) -eq $null) {$tmp = $false;}
Set-SMSVar 'VmwPresent' $tmp -Option ReadOnly
# --- Set VMWare presence end   ---

# --- Check Region passed correctly start ---
if((Test-SMSVMWareUsable)) {$findIn = (Get-SMSVar AllRegions)} else {$findIn = (Get-SMSVar 'AwsRegions')}
if((Get-SMSVar Region) -notin $findIn) {
    $thisErrorMsg="Region [$(Get-SMSVar Region)] does not support by your SMS";
    toLog $thisErrorMsg 'fatal';
    Set-SMSVar 'smsLoadedOk' $false;
}
# --- Check Region passed correctly end   ---

CorrectAutoregions

if((Get-SMSVar smsLoadedOk)) {
    # --- VMWare Servers definition for each region start ---
    if((Get-SMSVar 'Environment') -eq 'Prod') {
        Set-SMSVar 'VmwConnectionInfo' (
            @{
                'vm-nj4-1' = @((GetVmwConnectionInfoSettings 'vm-nj4-1'));
                'vm-nj5-1' = @((GetVmwConnectionInfoSettings 'vm-nj5-1'));
                'vm-da-1' = @((GetVmwConnectionInfoSettings 'vm-da-1'));
                'vm-kc-1' = @((GetVmwConnectionInfoSettings 'vm-kc-1'));
                'vm-lab-1' = @((GetVmwConnectionInfoSettings 'vm-lab-1'));
            }
        )
    }
    elseif((Get-SMSVar 'Environment') -eq 'Dev') {
        Set-SMSVar 'VmwConnectionInfo' (
            @{
                'vm-lab-1' = @((GetVmwConnectionInfoSettings 'vm-lab-1'));
            }
        )
    }
    # --- VMWare Servers definition for each region end   ---

    $reloadModules = @('smsCommon')
    $reloadModules | % {
        toLog "Trying to reload bootstrap module [$_]..." 'semi'
        # --- lines below because there is no smsCommon module loaded yet. But it can be reloaded ))) this i becasuse we are loading _from_ smsCommon logic ---
        if((Get-Module -Name 'alexCommon' -ErrorAction SilentlyContinue) -ne $null) {
            $modulePath = (Get-Module -Name 'alexCommon' | Select ModuleBase).ModuleBase
        }
        # -----------------------------------------------------------------------------------------------------------------------------------------------------
        if([string]::IsNullOrEmpty($modulePath)) {$modulePath = '.\'}
        Remove-Module $_ -ErrorAction SilentlyContinue
        $isDev = ((Get-Variable "$($SMSPrefix)Environment" -ValueOnly) -eq 'Dev')
        Import-Module (Join-Path -Path $modulePath -Child "$_.psm1") -ArgumentList ($isDev, $true, (Get-Variable "$($SMSPrefix)Zone" -ValueOnly)) -Global
        toLog "Bootstrap module [$_] reloaded" 'semi'
    }
    $error.Clear()

    # --------- WC Team ---------
    if((Get-SMSVar 'Environment') -eq 'Dev') {Set-SMSVar 'wc_cat_codeBase' 'os33.workplace.config-dev/Bootstrap/WorkplaceConfigSMSProvisioning.ps1'}
    else {Set-SMSVar 'wc_cat_codeBase' 'workplace.config-prod/Bootstrap/WorkplaceConfigSMSProvisioning.ps1'}

    Set-SMSVar 'wc_cat_region' 'us-east-1'
    Set-SMSVar 'wc_cat_magicFunction' 'Invoke-wpSMSProvisioning'
    # ---------------------------
    if(((dir variable:pleaseDontDoRemoteLogging -ErrorAction SilentlyContinue) -eq $null) -or $pleaseDontDoRemoteLogging -eq $false) {
        # Preparing for remote logging. Just for a debugging purposes only ;)
        Set-Variable -Name pleaseDontDoRemoteLogging -Value $false -Scope Global -Option AllScope -Force
        Set-Variable -Name remoteLogId -Value ([guid]::NewGuid()) -Scope Global -Option AllScope -Force
        Set-Variable -Name remoteLogLastSave -Value (Get-Date) -Scope Global -Option AllScope -Force
        Set-Variable -Name remoteLogSaveInterval -Value 60 -Scope Global -Option AllScope -Force
        Set-Variable -Name remoteLogData -Value (New-Object 'collections.generic.list[string]') -Scope Global -Option AllScope -Force
        Set-Variable -Name remoteLogClearedMsg -Value 'Remote Log Cleared'
        FirstPreparationOfRemoteLogData;
        toLog "Your Remote Log Id is: [$remoteLogId]. Usage: [Get-SMSRemoteLog $remoteLogId]" 'ok'
    }
    log 'Single Management System (SMS) v0.6.7 Copyright (c) 2017-2018 OS33 os33@os33.com. Built 2018-04-20 15:42:29 UTC' 'ok'
    if((Get-SMSVar 'smsLoadedOk') -ne $false) {Set-SMSVar 'smsLoadedOk' $true}
}
else {toLog "SMS module is not completely initialized. You should correct the error shown and try to rerun your code." 'error'}
