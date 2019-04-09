# vcd-h5-themes.psm1
#
# PS Module to maintain HTML5 UI Themes for vCloud Director 9.x.
# NOTE: Some commands require vCloud Director v9.1 (API 30.0 or later)
# NOTE: Some commands require vCloud Director v9.5 (API 31.0 or later)
#
# Requires that you are already connected to the vCD API
# (Connect-CIServer) system contaxt prior to running the command.
#
# Copyright 2018-2019 Jon Waite, All Rights Reserved
# Released under MIT License - see https://opensource.org/licenses/MIT
# Date:    9th April 2019
# Version: 1.4.0


# Get-SessionId is a helper function that gets the SessionId of the vCloud
# session (Connect-CIServer) that matches the specified vCD Host endpoint.
# Returns SessionId as a [string] or empty string if matching session is
# not found.
Function Get-SessionId(
    [string]$Server
)
{
    # If we are only connected to a single vCD endpoint, return that sessionId:
    if ($Global:DefaultCIServers.Count -eq 1) {
        if ($Server) {
            if ($Global:DefaultCIServers.Name -eq $Server) {
                return $Global:DefaultCIServers.SessionID
            } else {
                Write-Error("The specified Server is not currently connected, connect first using Connect-CIServer.")
            }
        } else {
            return $Global:DefaultCIServers.SessionID
        }
    } else {
        if (!$Server) {
            Write-Error("No Server specified and connected to multiple servers, please use the -Server option to specify which connection should be used for this operation.")
            return
        }
        $mySessionID = ($Global:DefaultCIServers | Where-Object { $_.Name -eq $Server }).SessionID
        if (!$mySessionID) { 
            Write-Error("Cannot find a connection that matches Server $Server, connect first using Connect-CIServer.")
            return
        }         
        return $mySessionID   
    }
}


# Get-APIVersion is a helper function that retrieves the highest supported
# API version from the given vCD endpoint. This ensures that commands are not
# run against unsupported versions of the vCloud Director API.
Function Get-APIVersion(
    [string]$Server
)
{
    # If Server not specified, obtain from connected sessions
    $Server = Get-Server -Server $Server

    if ($Server) {
        try {
            [xml]$apiversions = Invoke-WebRequest -Uri "https://$Server/api/versions" -Method Get -Headers @{"Accept"='application/*+xml'}
        } catch {
            Write-Error ("Could not retrieve API versions, Status Code is $($_.Exception.Response.StatusCode.Value__).")
            Write-Error ("This can be caused by an untrusted SSL certificate on your Server.")
            return   
        }
        return [int](($apiversions.SupportedVersions.VersionInfo | Where-Object { $_.deprecated -eq $false } | Sort-Object Version -Descending | Select-Object -First 1).Version)
    } else {
        Write-Error ("Could not establish Server, if you are connected to multiple servers you must specify -Server option.")
    }
}


# Get-Server is a helper function to identify the correct Server value to
# be used (specified directly, default if only 1 connection to vCD or empty
# otherwise).
Function Get-Server(
    [string]$Server
)
{
    if ($Server) { return $Server }
    if ($global:DefaultCIServers.Count -gt 1) { return }
    return $global:DefaultCIServers.ServiceUri.Host
}

Function Get-Branding(
    [string]$Server,  # The vCD host to connect to, required if more than one vCD endpoint is connected.
    [string]$Tenant   # The tenant to retrieve branding from (will return system default branding if not configured for this tenant or the tenant is not found).
)
{
<#
.SYNOPSIS
Gets the currently defined branding settings for a vCloud Director v9.1+
instance.
.DESCRIPTION
Get-Branding provides a simple method to retrieve the current defined branding
settings in a vCloud Director instance.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Tenant
Which vCloud Director Tenant to retrieve branding from, if no custom branding
has been specified for the given tenant then the system-level branding will
be returned.
.OUTPUTS
The currently defined branding settings as a PSObject
.EXAMPLE
Get-Branding -Server my.cloud.com
.EXAMPLE
Get-Branding -Server my.cloud.com -Tenant ABCInc
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases. Per-tenant branding requires functionality first
introduced in vCloud Director 9.7 (API Version 32.0) and will *NOT* work with
any prior release.
#>
    $Server = Get-Server -Server $Server
    
    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Get-Branding requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    if (($Tenant) -and ($apiVersion -lt 32)) {
        Write-Error("Get-Branding for a specified Tenant requires vCloud API v32 or later (vCloud Director 9.7), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=30.0' }
    
    try {
        $r1 = Invoke-WebRequest -Method Get -Uri "https://$Server/cloudapi/branding" -Headers $headers
    } catch {
        Write-Error ("Could not retrieve branding from API, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return        
    }
    return ($r1.Content | ConvertFrom-Json)
}


Function Set-Branding(
    [string]$Server,                               # The vCD host to connect to
    [string]$portalName,                           # Portal title string
    [string]$portalColor,                          # Portal color (hex format '#ABCD12') or 'Remove' to revert to default
    [System.Object]$customLinks,                   # Custom links to be added to portal
    [string]$Tenant                                # The tenant to configure this branding for (if not configuring system default)
)
{
<#
.SYNOPSIS
Set the vCloud Director HTML5 portal branding configuration
.DESCRIPTION
Set-Branding provides an easy method to configure the portal branding for
the vCloud Director v9.1+ HTML user interface.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER portalName
An optional description of the portal which will be displayed at login and in
the vCloud Director banner in every page. (e.g. 'My Cloud Portal'). If not
specified the existing value will be unchanged.
.PARAMETER portalColor
An optional hex-formatted color values (in upper case) which determine the
default portal background banner color (e.g. '#1A2A3A'). If not specified
the existing value will be unchanged. If specified as the string 'Remove' will
remove any defined portal color value.
.PARAMETER customLinks
An object consisting of custom URL links to be included in the vCloud
Director portal. Links will be validated by the vCloud API and rejected if 
they are not properly formed URL specifications. See README.md for an example
of a well-formatted object.
.OUTPUTS
The results of setting the portal Branding
.EXAMPLE
Set-Branding -Server my.cloud.com -portalName 'My Cloud Portal' -portalColor #1A2A3A
.EXAMPLE
Set-Branding -Server my.cloud.com -customLinks /// TODO ///
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
For some reason, sending "" (empty string) as part of the JSON document doesn't
leave existing values in place (as per VMware documentation) but overwrites with
a Null value so we check existing settings and maintain these for any options
not specified in the Set-Branding options.
#>
    $Server = Get-Server -Server $Server

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Set-Branding requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    if (($Tenant) -and ($apiVersion -lt 32)) {
        Write-Error("Set-Branding per-Tenant requires vCloud API v32 or later (vCloud Director 9.7), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    $oldbranding = Get-Branding -Server $Server

    $branding = New-Object System.Collections.Specialized.OrderedDictionary

    if ($portalName) {
        $branding.Add('portalName',$portalName)
    } else {
        $branding.Add('portalName',$oldbranding.portalName)
    }

    if ($portalColor) {
        if ($portalColor = 'Remove') {
            $branding.Add('portalColor','')
        } else {
            $branding.Add('portalColor',$portalColor)
        }     
    } else {
        $branding.Add('portalColor',$oldbranding.portalColor)
    }
    
    # Maintain existing selectedTheme settings by retrieving from API, use Set-Theme to change
    $selectedTheme = new-Object System.Collections.Specialized.OrderedDictionary
    $selectedTheme.Add('themeType',$oldbranding.selectedTheme.themeType)
    $selectedTheme.Add('name',$oldbranding.selectedTheme.name)
    $branding.Add('selectedTheme',$selectedTheme)

    if ($customLinks) {
        if ($APIVersion -lt 32) {
            Write-Error("Definiting custom links requires vCloud API v32 or later (vCloud Director 9.7), the detected API version is $apiVersion.")
            return
        }
        $branding.Add('customLinks',$customLinks)
    } else {
        $branding.Add('customLinks',$oldbranding.customLinks)
    }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=31.0' }
    if ($Tenant) {
        $uri = 'https://' + $Server + '/cloudapi/branding/tenant/' + $Tenant
    } else {
        $uri = 'https://' + $Server + '/cloudapi/branding'
    }

    try {
        $r1 = Invoke-WebRequest -Method Put -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($branding | ConvertTo-Json)
    } catch {
        Write-Error ("Error occurred configuring branding, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return        
    }

    if ($r1.StatusCode -eq 200) {
        Write-Host("Branding configuration sent successfully.")
    } else {
        Write-Warning("Branding configuration gave an unexpected status code: $($r1.StatusCode)")
    }
}


Function Get-Theme(
    [string]$Server,                              # The vCD host to connect to
    [string]$Theme                             # A specific Theme to match
)
{
<#
.SYNOPSIS
Gets a list of any themes defined in the vCloud Director v9.1+ HTML5 interface.
.DESCRIPTION
Get-Theme provides a simple method to retrieve the names of any custom themes
defined in the vCloud Director 9.1+ HTML interface.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Theme
An optional parameter which specifies a theme name to try and match. This can
be used to see if a theme is already registered with the given name.
.OUTPUTS
The names of any custom themes defined in the vCloud Director HTML5 interface.
.EXAMPLE
Get-Theme -Server my.cloud.com
.EXAMPLE
Get-Theme -Server my.cloud.com -Theme mytheme
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Get-Theme requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }
    
    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=30.0' }
    $uri = 'https://' + $Server + '/cloudapi/branding/themes'
    $r1 = Invoke-WebRequest -Method Get -Uri $uri -Headers $headers -ContentType 'application/json'
    $results = ($r1.Content | ConvertFrom-Json) #| Where-Object { $_.themeType -eq 'CUSTOM' }
    if ($Theme) {
        return ($results | Where-Object { $_.name -eq $Theme })
    } else {
        return $results
    }
}


Function Set-Theme(
    $Server,  # The vCD host to connect to
    [Parameter(Mandatory=$true)][string]$Theme, # The theme to be activated
    [bool]$custom = $true   # Whether this is a custom theme (default) or 'BUILT_IN'
)
{
<#
.SYNOPSIS
Sets the system default theme to the specified value.
.DESCRIPTION
Set-Theme provides a simple method to set the current vCD system default
theme.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Theme
A mandatory parameter which specifies the theme name to make the system default
thenme. An error is returned if the specified theme cannot be found.
.PARAMETER custom
A boolean parameter which defaults to 'True' indicating the theme to be set is
a 'CUSTOM' type (user-defined). If set to 'False' the theme will need to be set
to one of the two 'BUILT-IN' themes ('Default' or 'Dark').
.OUTPUTS
A status message is returned showing whether or not the command was successful.
.EXAMPLE
Set-Theme -Server my.cloud.com -Theme mytheme
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Set-Theme requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    if (!(Get-Theme -Server $Server -Theme $Theme)) {
        Write-Warning "Specified theme does not exist, cannot set as system default."
        return
    }

    $branding = Get-Branding -Server $Server

    $branding.selectedTheme.name = $Theme
    if ($custom) {
        $branding.selectedTheme.themeType = 'CUSTOM'
    } else {
        $branding.selectedTheme.themeType = 'DEFAULT'
    }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=30.0' }
    $uri = "https://$Server/cloudapi/branding"
    
    try {
        $r1 = Invoke-WebRequest -Method Put -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($branding | ConvertTo-Json)
    } catch {
        Write-Error ("Error occurred setting theme, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return        
    }

    if ($r1.StatusCode -eq 200) {
        Write-Host("Default theme configuration set successfully.")
    } else {
        Write-Warning("Default theme configuration gave an unexpected status code: $($r1.StatusCode)")
    }
}

Function New-Theme(
    [string]$Server,   # The vCD host to connect to
    [Parameter(Mandatory=$true)][string]$Theme # The name of the Theme to create
)
{
<#
.SYNOPSIS
Creates a new (custom) theme for vCloud Director v9.1+ HTML5 interface.
.DESCRIPTION
New-Theme provides a simple method to register a new custom theme for the
vCloud Director 9.1 (or later) HTML5 interface.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Theme
A mandatory parameter which specifies the name of the theme to be created.
.OUTPUTS
A message will confirm whether the theme is created successfully or not.
.EXAMPLE
New-Theme -Server my.cloud.com -Theme mytheme
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("New-Theme requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    if (Get-Theme -Server $Server -Theme $Theme) {
        Write-Warning "Cannot create theme with name $Theme as this theme already exists."
        return
    }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=30.0' }
    $uri = "https://$Server/cloudapi/branding/themes/"
    
    # For API v32.0 (and later?) we must specify a themeType value for this call to work:
    if ($apiVersion -lt 32) {
        $body = [PSCustomObject]@{ name = $Theme } | ConvertTo-Json
    } else {
        $body = [PSCustomObject]@{ themeType = "CUSTOM"; name = $Theme } | ConvertTo-Json
    }

    try{
        Invoke-WebRequest -Method Post -Uri $uri -Headers $headers -Body $body -ContentType 'application/json' | Out-Null
    } catch {
        Write-Error ("Theme $Theme could not be created, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return
    }
    Write-Host("Theme $Theme created successfully.")
}

Function Remove-Theme(
    [string]$Server,                            # The vCD host to connect to
    [Parameter(Mandatory=$true)][string]$Theme  # The name of the vCD theme
)
{
<#
.SYNOPSIS
Removes a custom theme from the vCloud Director v9.1+ HTML5 interface.
.DESCRIPTION
Remove-Theme provides a simple method to remove a custom theme from the
vCloud Director 9.1 (or later) HTML5 interface.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Theme
A mandatory parameter which specifies the name of the theme to be removed.
.OUTPUTS
A message will confirm whether the theme is created successfully or not.
.EXAMPLE
Remove-Theme -Server my.cloud.com -Theme mytheme
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Remove-Theme requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    if (!(Get-Theme -Server $Server -Theme $Theme)) {
        Write-Warning "Cannot delete theme with name $Theme as this theme does not exist."
        return
    }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=30.0' }
    $uri = "https://$Server/cloudapi/branding/themes/$Theme"
    $body = [PSCustomObject]@{ name = $Theme } | ConvertTo-Json

    try {
        Invoke-WebRequest -Method Delete -Uri $uri -Headers $headers -Body $body -ContentType 'application/json' | Out-Null
    } catch {
        Write-Error ("Error occurred obtaining removing theme, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return        
    }
    Write-Host("Theme $Theme was removed successfully.")   
}

Function Publish-Css(
    [string]$Server,   # The vCD host to connect to
    [Parameter(Mandatory=$true)][string]$Theme, # The name of the vCD theme
    [Parameter(Mandatory=$true)][string]$CssFile    # The CSS file to be uploaded
)
{
<#
.SYNOPSIS
Uploads a new (or replaces existing) CSS theme for vCloud Director 9.5 or
later.
.DESCRIPTION
Publish-Css provides an easy way to upload a new or replace an existing CSS
(Cascading Style Sheet) for a vCloud Director 9.5 (or later) environment. Theme
files can be generated using the VMware theme-generator located at
https://github.com/vmware/vcd-ext-sdk/tree/master/ui/theme-generator.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Theme
A mandatory parameter which specifies the name of the theme for which this CSS
theme will be uploaded as the content.
.PARAMETER CssFile
A mandatory parameter which specifies the filename of the CSS file generated by
the VMware theme-generator code which will be uploaded.
.OUTPUTS
A message will confirm whether the CSS file has been sucessfully uploaded or a
failure alert will be generated.
.EXAMPLE
Publish-Css -Server my.cloud.com -Theme mytheme -CssFile mytheme.css
.NOTES
Requires functionality first introduced in vCloud Director v9.5 and will *NOT*
work with any prior releases.
The CSS theme uploaded will only apply to the vCloud HTML5 interface, any
customization required for the Flex (Flash) UI must still be set in the Flex
administration options as for previous vCloud Director versions.
#>
    $Server = Get-Server -Server $Server    

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 31) {
        Write-Error("Publish-Css requires vCloud API v31 or later (vCloud Director 9.5), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    if (!(Test-Path -Path $CssFile)){
        Write-Error ("Error, could not locate css theme file: $CssFile.")
        Return
    }

    if (!(Get-Theme -Server $Server -Theme $Theme)) {
        Write-Warning "Cannot upload .CSS for Theme $Theme as this theme does not exist."
        return
    }

    $CssFileName = $CssFile | Split-Path -Leaf

    # Request 1 - register the filename to retrieve the upload link for the .CSS content:
    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=31.0' }
    $uri = 'https://' + $Server + '/cloudapi/branding/themes/' + $Theme + '/contents'
    $body = [pscustomobject]@{fileName=$CssFileName; size=$((Get-Item $CssFile).Length)} | ConvertTo-Json

    try {
        $r1 = Invoke-WebRequest -Method Post -Uri $URI -Headers $headers -Body $body -ContentType 'application/json'
    } catch {
        Write-Error ("Error occurred obtaining upload link, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return        
    }
  
    # Request 2 - use the retrieved upload link to upload the file:
    $uploaduri = $r1.RelationLink['upload:default']

    try {
        Invoke-WebRequest -Uri $uploaduri -Headers $headers -Method Put -InFile $CssFile | Out-Null
    } catch {
        Write-Error ("Error occurred obtaining uploading CSS file, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return
    }

    Write-Host("Theme CSS file uploaded succesfully.")

}


Function Get-Css(
    [string]$Server,   # The vCD host to connect to
    [Parameter(Mandatory=$true)][string]$Theme, # The name of the vCD theme
    [Parameter(Mandatory=$true)][string]$CssFile    # The CSS file to be downloaded
)
{
<#
.SYNOPSIS
Retrieves the CSS code for a specified theme for vCloud Director 9.5 or
later.
.DESCRIPTION
Get-Css provides an easy way to download the CSS file (Cascading Style Sheet)
for a vCloud Director 9.5 (or later) environment.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER Theme
A mandatory parameter which specifies the name of the theme for which this CSS
theme will be downloaded.
.PARAMETER CssFile
The file to which the CSS data for the specified Theme will be saved as.
Any existing file with the same name will be overwritten.
.OUTPUTS
A message will confirm whether the CSS file has been sucessfully downloaded or
a failure alert will be generated.
.EXAMPLE
Get-Css -Server my.cloud.com -Theme mytheme -CssFile mytheme.css
.NOTES
Requires functionality first introduced in vCloud Director v9.5 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server    

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 31) {
        Write-Error("Get-Css requires vCloud API v31 or later (vCloud Director 9.5), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    if (!(Get-Theme -Server $Server -Theme $Theme)) {
        Write-Warning "Cannot download .CSS for Theme $Theme as this theme does not exist."
        return
    }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'text/css;version=31.0' }
    $uri = "https://$Server/cloudapi/branding/themes/$Theme/css"
    
    try {
        $r1 = Invoke-WebRequest -Method Get -Uri $URI -Headers $headers -ContentType 'application/json'
    } catch {
        Write-Error ("Error occurred retrieving CSS, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return
    }
  
    try {
        $r1.Content | Out-File $CssFile -Append:$false
    } catch {
        Write-Error ("Error occurred attempting to write to $CssFile.")
        return
    }

    Write-Host("Theme CSS file downloaded succesfully.")
}


Function Publish-Logo(
    [string]$Server,  # The vCD host to connect to, required if more than one vCD endpoint is connected.
    [Parameter(Mandatory=$true)][string]$LogoFile   # The filename for the logo to be uploaded
)
{
<#
.SYNOPSIS
Uploads a graphic file (PNG format) to be used as the site logo.
.DESCRIPTION
Publish-Logo provides an easy method to change the global site logo for a
vCloud Director site. This logo will appear in the title bar and on the
default login screen for the site.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER LogoFile
A mandatory parameter of the png file containing the logo to be uploaded.
.OUTPUTS
A message indicating whether the logo has been successfully uploaded.
.EXAMPLE
Publish-Logo -Server my.cloud.com -LogoFile mylogo.png
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server
    
    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Publish-Logo requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    if (!(Test-Path -Path $LogoFile)){
         Write-Error ("Error, could not locate css theme file: $CssFile.")
         Return
    }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/json;version=30.0' }
    $uri = 'https://' + $Server + '/cloudapi/branding/logo'
    
    try {
        Invoke-WebRequest -Uri $uri -Headers $headers -Method Put -InFile $LogoFile -ContentType 'image/png' | Out-Null
    } catch {
        Write-Error ("Error occurred obtaining uploading logo file, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return
    }

    Write-Host("System logo file uploaded succesfully.")
}


Function Get-Logo(
    [string]$Server,   # The vCD host to connect to
    [Parameter(Mandatory=$true)][string]$LogoFile    # The Logo file to be downloaded
)
{
<#
.SYNOPSIS
Retrieves the site logo for vCloud Director 9.1 or later.
.DESCRIPTION
Get-Logo provides an easy way to download the PNG system logo file 
for a vCloud Director 9.1 (or later) environment.
.PARAMETER Server
Which vCloud Director API host to connect to (e.g. my.cloud.com). You must be
connected to this host as a user in the system (Administrative) context using
Connect-CIServer prior to running this command. This parameter is required
if you are connected to multiple vCD environments.
.PARAMETER LogoFile
The file to which the logo will be saved as. Any existing file with the same
name will be overwritten.
.OUTPUTS
A message will confirm whether the logo file has been sucessfully downloaded or
a failure alert will be generated.
.EXAMPLE
Get-Logo -Server my.cloud.com -LogoFile mylogo.png
.NOTES
Requires functionality first introduced in vCloud Director v9.1 and will *NOT*
work with any prior releases.
#>
    $Server = Get-Server -Server $Server    

    $apiVersion = Get-APIVersion -Server $Server
    if ($apiVersion -lt 30) {
        Write-Error("Get-Logo requires vCloud API v30 or later (vCloud Director 9.1), the detected API version is $apiVersion.")
        return
    }

    $mySessionID = Get-SessionId($Server)
    if (!$mySessionID) { return }

    $headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'image/png;version=30.0' }
    $uri = "https://$Server/cloudapi/branding/logo"
    
    try {
        Invoke-WebRequest -Method Get -Uri $URI -Headers $headers -OutFile $LogoFile
    } catch {
        Write-Error ("Error occurred retrieving CSS, Status Code is $($_.Exception.Response.StatusCode.Value__).")
        return
    }
    Write-Host("Logo PNG file downloaded succesfully.")
}


# Make module functions accessible publically:
Export-ModuleMember -Function Get-Branding
Export-ModuleMember -Function Set-Branding
Export-ModuleMember -Function Get-Theme
Export-ModuleMember -Function Set-Theme
Export-ModuleMember -Function Remove-Theme
Export-ModuleMember -Function New-Theme
Export-ModuleMember -Function Publish-Css
Export-ModuleMember -Function Get-Css
Export-ModuleMember -Function Publish-Logo
Export-ModuleMember -Function Get-Logo